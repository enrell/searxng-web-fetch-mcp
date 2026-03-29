require "./spec_helper"
require "json"
require "openssl"

describe "MCP Tool Invocation Regression Test" do
  it "handles searxng_web_search tool invocation without crashing" do
    tool = SearxngWebSearch.new

    args = {
      "query"       => JSON::Any.new("test"),
      "num_results" => JSON::Any.new(3),
    } of String => JSON::Any

    result = tool.invoke(args, nil)

    result.should be_a(Hash(String, JSON::Any))
    result.has_key?("content").should be_true
    result.has_key?("isError").should be_true
  end

  it "handles web_fetch tool invocation without crashing" do
    tool = WebFetch.new

    args = {
      "url" => JSON::Any.new("https://example.com"),
    } of String => JSON::Any

    result = tool.invoke(args, nil)

    result.should be_a(Hash(String, JSON::Any))
    result.has_key?("content").should be_true
    result.has_key?("isError").should be_true
  end

  it "returns proper MCP response format from tool invocation" do
    tool = SearxngWebSearch.new

    args = {
      "query" => JSON::Any.new("test"),
    } of String => JSON::Any

    result = tool.invoke(args, nil)

    result["content"].should be_a(JSON::Any)
    result["content"].as_a.should be_a(Array(JSON::Any))
    result["content"].as_a.size.should eq(1)
    result["content"].as_a[0]["type"].as_s.should eq("text")
    result["content"].as_a[0]["text"].should be_a(JSON::Any)
  end

  it "handles missing optional parameters gracefully" do
    tool = SearxngWebSearch.new

    args = {
      "query" => JSON::Any.new("test"),
    } of String => JSON::Any

    result = tool.invoke(args, nil)

    result.should be_a(Hash(String, JSON::Any))
    result.has_key?("content").should be_true
  end

  it "web_fetch handles url and urls parameters correctly" do
    single_tool = WebFetch.new

    single_args = {
      "url" => JSON::Any.new("https://example.com"),
    } of String => JSON::Any

    single_result = single_tool.invoke(single_args, nil)
    single_result.should be_a(Hash(String, JSON::Any))
    single_result.has_key?("content").should be_true
  end

  it "does not crash with empty result sets" do
    tool = WebFetch.new

    args = {
      "url" => JSON::Any.new("https://invalid-domain-that-does-not-exist-12345.com"),
    } of String => JSON::Any

    result = tool.invoke(args, nil)

    result.should be_a(Hash(String, JSON::Any))
    result.has_key?("content").should be_true
    result["isError"].as_bool.should be_true
  end
end
