require "mcp"
require "log"
require "./tools/*"
require "./extraction/*"
require "./utils/*"

module SearxngWebFetchMcp
  VERSION = "0.1.4"

  LOG_LEVEL               = ENV.fetch("LOG_LEVEL", "INFO").upcase
  MCP_TIMEOUT             = ENV.fetch("MCP_TIMEOUT", "30").to_i
  MAX_CONCURRENT_REQUESTS = ENV.fetch("MAX_CONCURRENT_REQUESTS", "10").to_i

  def self.log(level, message)
    STDERR.puts "[#{level}] #{message}" if should_log?(level)
  end

  private def self.should_log?(level)
    levels = {"DEBUG" => 0, "INFO" => 1, "WARN" => 2, "ERROR" => 3}
    current = levels[LOG_LEVEL]?
    msg = levels[level]?
    current && msg && current <= msg
  end
end

SEARXNG_URL = ENV.fetch("SEARXNG_URL", "http://localhost:8080")
BYPARR_URL  = ENV.fetch("BYPARR_URL", "http://localhost:8191")

unless PROGRAM_NAME.includes?("spec")
  SearxngWebFetchMcp.log("INFO", "Starting MCP server v#{SearxngWebFetchMcp::VERSION}")
  SearxngWebFetchMcp.log("INFO", "SEARXNG_URL: #{SEARXNG_URL}")
  SearxngWebFetchMcp.log("INFO", "BYPARR_URL: #{BYPARR_URL}")
  SearxngWebFetchMcp.log("INFO", "MAX_CONCURRENT_REQUESTS: #{SearxngWebFetchMcp::MAX_CONCURRENT_REQUESTS}")
  SearxngWebFetchMcp.log("INFO", "MCP_TIMEOUT: #{SearxngWebFetchMcp::MCP_TIMEOUT}s")

  ConcurrentStdioHandler.start_server
end

class ConcurrentStdioHandler
  @@request_id = 0
  @@request_id_mutex = Mutex.new
  @@active_requests = 0
  @@active_requests_mutex = Mutex.new

  def self.next_request_id
    @@request_id_mutex.synchronize do
      @@request_id += 1
      "req_#{@@request_id}"
    end
  end

  def self.increment_active
    @@active_requests_mutex.synchronize { @@active_requests += 1 }
  end

  def self.decrement_active
    @@active_requests_mutex.synchronize { @@active_requests -= 1 }
  end

  def self.active_requests
    @@active_requests_mutex.synchronize { @@active_requests }
  end

  def self.start_server
    STDERR.puts "MCP stdio server started. Available tools:"
    STDERR.puts MCP.registered_tools.keys.join(", ")
    STDERR.puts "---"
    STDOUT.flush

    while !STDIN.closed?
      begin
        line = STDIN.gets
        break unless line

        line = line.strip
        next if line.empty?

        if active_requests >= SearxngWebFetchMcp::MAX_CONCURRENT_REQUESTS
          error_response = {
            "jsonrpc" => "2.0",
            "error"   => {
              "code"    => -32000,
              "message" => "Server busy: max concurrent requests (#{SearxngWebFetchMcp::MAX_CONCURRENT_REQUESTS}) reached",
            },
            "id" => nil,
          }
          puts error_response.to_json
          STDOUT.flush
          next
        end

        spawn handle_request(line)
      rescue ex
        error_response = {
          "jsonrpc" => "2.0",
          "error"   => {
            "code"    => -32603,
            "message" => "Internal error: #{ex.message}",
          },
          "id" => nil,
        }
        puts error_response.to_json
        STDOUT.flush
      end
    end
  end

  def self.handle_request(line : String)
    increment_active
    begin
      json_request = JSON.parse(line)
      request_id = json_request["id"]?

      unless json_request["jsonrpc"]? == "2.0"
        response = send_error(-32600, "Invalid Request", request_id)
        puts response
        STDOUT.flush
        return
      end

      method = json_request["method"]?.try(&.as_s)
      params = json_request["params"]?.try(&.as_h) || {} of String => JSON::Any

      response = case method
                 when "initialize"
                   handle_initialize(params, request_id)
                 when "tools/list"
                   handle_tools_list(params, request_id)
                 when "tools/call"
                   handle_tools_call(params, request_id)
                 else
                   send_error(-32601, "Method not found: #{method}", request_id)
                 end

      puts response
      STDOUT.flush
    rescue ex
      error_response = {
        "jsonrpc" => "2.0",
        "error"   => {
          "code"    => -32603,
          "message" => "Internal error: #{ex.message}",
        },
        "id" => nil,
      }
      puts error_response.to_json
      STDOUT.flush
    ensure
      decrement_active
    end
  end

  def self.handle_tools_call(params, request_id)
    tool_name = params["name"]?.try(&.as_s)
    unless tool_name
      return send_error(-32602, "Missing tool name", request_id)
    end

    tool = MCP.registered_tools[tool_name]?
    unless tool
      return send_error(-32602, "Unknown tool: #{tool_name}", request_id)
    end

    arguments = params["arguments"]?.try(&.as_h) || params["params"]?.try(&.as_h) || {} of String => JSON::Any

    begin
      result = tool.invoke(arguments, nil)

      response = {
        "jsonrpc" => "2.0",
        "id"      => request_id,
        "result"  => result,
      }

      response.to_json
    rescue ex : Exception
      send_error(-32602, "Tool error: #{ex.message}", request_id)
    end
  end

  def self.handle_initialize(params, id)
    response = {
      "jsonrpc" => "2.0",
      "id"      => id,
      "result"  => {
        "protocolVersion" => "2024-11-05",
        "capabilities"    => {
          "tools" => {
            "listChanged" => true,
          },
        },
        "serverInfo" => {
          "name"    => "searxng-web-fetch-mcp",
          "version" => SearxngWebFetchMcp::VERSION,
        },
      },
    }
    response.to_json
  end

  def self.handle_tools_list(params, id)
    tools_list = MCP.registered_tools.values.map do |tool|
      {
        "name"        => tool.name,
        "description" => tool.description,
        "inputSchema" => JSON.parse(tool.input_schema),
      }
    end

    response = {
      "jsonrpc" => "2.0",
      "id"      => id,
      "result"  => {
        "tools" => tools_list,
      },
    }
    response.to_json
  end

  def self.send_error(code, message, id)
    error_response = Hash(String, JSON::Any).new
    error_response["jsonrpc"] = JSON::Any.new("2.0")
    error_response["error"] = JSON::Any.new({
      "code"    => JSON::Any.new(code),
      "message" => JSON::Any.new(message),
    } of String => JSON::Any)

    if id && !id.nil?
      error_response["id"] = id
    end

    error_response.to_json
  end
end
