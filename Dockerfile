FROM public.ecr.aws/ubuntu/ubuntu:24.04

ENV TARGETARCH=linux-x64 \
    DEBIAN_FRONTEND=noninteractive

# Install essential runtime deps, system Python, and Docker CLI.
# No dockerd inside the container: agents use the host Docker Engine via
# the bind-mounted /var/run/docker.sock (Docker Swarm on the EC2 host).
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    sudo \
    curl \
    gnupg \
    jq \
    git \
    libicu74 \
    # Install Python 3 and related packages
    python3 \
    python3-pip \
    python3-venv \
    python-is-python3 && \
    # Install Docker CLI and related plugins
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
      > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    docker-ce-cli \
    docker-buildx-plugin \
    docker-compose-plugin && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    # Remove unnecessary packages and files to reduce size
    rm -rf /usr/share/man /usr/share/doc /usr/share/info && \
    rm -rf /usr/share/locale/* && \
    rm -rf /usr/share/perl* && \
    rm -rf /usr/share/bash-completion && \
    rm -rf /usr/share/zsh && \
    find /usr/share -type d -name "locale" -exec rm -rf {} + 2>/dev/null || true && \
    # Show installed versions for verification
    python --version && \
    docker --version

WORKDIR /azp/

COPY ./download_agent.sh ./
RUN chmod +x ./download_agent.sh

# Download and extract Azure Pipelines agent, then clean up unnecessary files
RUN ./download_agent.sh $TARGETARCH /azp && \
    # Remove build and debug files to reduce image size  
    rm -f /azp/download_agent.sh /azp/reauth.sh && \
    find /azp/externals -type f \( -name "*.md" -o -name "*.txt" -o -name "*.pdb" -o -name "*.map" \) -delete && \
    find /azp -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true && \
    find /azp -type f -name "*.pyc" -delete && \
    # Remove old Node.js versions, keep node20_1 and node24 which are used by Azure Pipelines tasks
    rm -rf /azp/externals/node10 /azp/externals/node16 /azp/externals/node && \
    # Show final size
    du -sh /azp

COPY ./start.sh ./
RUN chmod +x ./start.sh && \
    useradd agent && \
    echo "agent ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/agent && \
    chown agent ./ -R

USER agent

ENTRYPOINT ["./start.sh"]

HEALTHCHECK --interval=1m --timeout=10s --start-period=2m --retries=3 \
  CMD pgrep -x "Agent.Listener" > /dev/null || exit 1