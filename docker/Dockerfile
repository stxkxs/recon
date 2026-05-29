# Dockerfile for recon - Infrastructure reconnaissance toolkit
#
# Build: docker build -t recon:latest -f docker/Dockerfile .
# Run:   docker run --rm -it recon:latest example.com
#        docker run --rm -it recon:latest --json example.com
#

FROM alpine:3.19

LABEL maintainer="SRE Team"
LABEL description="Infrastructure reconnaissance toolkit"
LABEL version="2.1.0"

# Install dependencies
RUN apk add --no-cache \
    bash \
    bind-tools \
    curl \
    openssl \
    whois \
    jq \
    yq \
    coreutils \
    grep \
    sed \
    gawk \
    bc \
    && rm -rf /var/cache/apk/*

# Create non-root user
RUN adduser -D -s /bin/bash recon

# Create directories
RUN mkdir -p /opt/recon/bin \
             /opt/recon/lib/core \
             /opt/recon/lib/modules \
             /opt/recon/lib/batch \
             /opt/recon/etc \
             /home/recon/.local/share/recon/results \
             /home/recon/.local/share/recon/state \
    && chown -R recon:recon /opt/recon /home/recon

# Copy project files
COPY --chown=recon:recon bin/recon /opt/recon/bin/
COPY --chown=recon:recon lib/core/*.sh /opt/recon/lib/core/
COPY --chown=recon:recon lib/modules/*.sh /opt/recon/lib/modules/
COPY --chown=recon:recon lib/batch/*.sh /opt/recon/lib/batch/
COPY --chown=recon:recon etc/*.txt etc/*.yaml.example /opt/recon/etc/

# Make executable
RUN chmod +x /opt/recon/bin/recon

# Update paths in main script for container environment
RUN sed -i 's|PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"|PROJECT_ROOT="/opt/recon"|' /opt/recon/bin/recon

# Add to PATH
ENV PATH="/opt/recon/bin:${PATH}"

# Set working directory
WORKDIR /home/recon

# Switch to non-root user
USER recon

# Default output directory
ENV RECON_OUTPUT_DIR="/home/recon/.local/share/recon/results"

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD recon --version || exit 1

# Default command shows help
ENTRYPOINT ["recon"]
CMD ["--help"]
