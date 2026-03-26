#!/bin/bash
set -e

REPO="enrell/searxng-web-fetch-mcp"
BIN_DIR="${HOME}/.local/bin"
BIN_NAME="searxng-web-fetch-mcp"
INSTALL_PATH="${BIN_DIR}/${BIN_NAME}"

mkdir -p "${BIN_DIR}"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "${OS}" in
  linux)
    case "${ARCH}" in
      x86_64)
        PLATFORM="linux-x86_64"
        ;;
      aarch64|arm64)
        PLATFORM="linux-arm64"
        ;;
      riscv64)
        PLATFORM="linux-riscv64"
        ;;
      *)
        echo "Unsupported Linux architecture: ${ARCH}"
        exit 1
        ;;
    esac
    ;;
  darwin)
    case "${ARCH}" in
      arm64)
        PLATFORM="darwin-arm64"
        ;;
      x86_64|x86_64h)
        PLATFORM="darwin-x86_64"
        ;;
      *)
        echo "Unsupported macOS architecture: ${ARCH}"
        exit 1
        ;;
    esac
    ;;
  mingw*|msys*|cygwin*|windows)
    case "${ARCH}" in
      x86_64)
        PLATFORM="windows-x86_64"
        ;;
      *)
        echo "Unsupported Windows architecture: ${ARCH}"
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Unsupported platform: ${OS}"
    exit 1
    ;;
esac

echo "Downloading searxng-web-fetch-mcp for ${PLATFORM}..."
curl -sL "https://github.com/${REPO}/releases/latest/download/searxng-web-fetch-mcp-${PLATFORM}" -o "${INSTALL_PATH}"
chmod +x "${INSTALL_PATH}"

echo "Installed to: ${INSTALL_PATH}"