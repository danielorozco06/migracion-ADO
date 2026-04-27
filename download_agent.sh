#!/bin/bash
set -e

TARGETARCH="${1:-linux-x64}"
WORKDIR="${2:-.}"

# Map architecture names to agent package names
case "$TARGETARCH" in
  linux-x64)
    AGENT_PACKAGE="vsts-agent-linux-x64"
    ;;
  linux-arm)
    AGENT_PACKAGE="vsts-agent-linux-arm"
    ;;
  linux-arm64)
    AGENT_PACKAGE="vsts-agent-linux-arm64"
    ;;
  *)
    echo "ERROR: Unsupported architecture: $TARGETARCH"
    exit 1
    ;;
esac

echo "Downloading Azure Pipelines agent for $TARGETARCH..."
echo "Working directory: $WORKDIR"

# Use fixed agent version to reduce network calls
# Check on https://github.com/microsoft/azure-pipelines-agent/releases for latest version updates
AGENT_VERSION="4.271.0"

echo "Using fixed agent version: $AGENT_VERSION"

# Build download URL from official Azure DevOps agent download server
RELEASE_URL="https://download.agent.dev.azure.com/agent/${AGENT_VERSION}/${AGENT_PACKAGE}-${AGENT_VERSION}.tar.gz"

echo "Download URL: $RELEASE_URL"
echo "Downloading agent..."
if ! curl -f -L --max-time 300 -o "$WORKDIR/agent.tar.gz" "$RELEASE_URL"; then
  echo "ERROR: Failed to download agent from $RELEASE_URL"
  exit 1
fi

if [ ! -f "$WORKDIR/agent.tar.gz" ]; then
  echo "ERROR: Failed to download agent"
  exit 1
fi

echo "Extracting agent..."
cd "$WORKDIR"
tar -xzf agent.tar.gz
rm -f agent.tar.gz

echo "Agent extracted successfully!"
ls -la
