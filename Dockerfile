#This solution, non-production-ready template describes AWS Codepipeline based CICD Pipeline for terraform code deployment.
#© 2024 Amazon Web Services, Inc. or its affiliates. All Rights Reserved.
#This AWS Content is provided subject to the terms of the AWS Customer Agreement available at
#http://aws.amazon.com/agreement or other written agreement between Customer and either
#Amazon Web Services, Inc. or Amazon Web Services EMEA SARL or both.

FROM public.ecr.aws/ubuntu/ubuntu:24.04

ENV TARGETARCH=linux-x64 \
    DEBIAN_FRONTEND=noninteractive

# Install only essential runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    sudo \
    curl \
    jq \
    curl \
    git \
    libicu74 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    # Remove unnecessary packages and files to reduce size
    rm -rf /usr/share/man /usr/share/doc /usr/share/info && \
    rm -rf /usr/share/locale/* && \
    rm -rf /usr/share/perl* && \
    rm -rf /usr/share/bash-completion && \
    rm -rf /usr/share/zsh && \
    find /usr/share -type d -name "locale" -exec rm -rf {} + 2>/dev/null || true

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
    chown agent ./ -R

USER agent

ENTRYPOINT ["./start.sh"]

HEALTHCHECK --interval=1m --timeout=10s --start-period=2m --retries=3 \
  CMD pgrep -x "Agent.Listener" > /dev/null || exit 1