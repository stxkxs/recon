# Dockerfile for recond - Infrastructure reconnaissance toolkit
#
# Build: docker build -t recond:latest -f docker/Dockerfile .
# Run:   docker run --rm -it recond:latest example.com
#        docker run --rm -it recond:latest --json example.com
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
RUN adduser -D -s /bin/bash recond

# Create directories
RUN mkdir -p /opt/recond/bin \
             /opt/recond/lib/core \
             /opt/recond/lib/modules \
             /opt/recond/lib/batch \
             /opt/recond/etc \
             /home/recond/.local/share/recond/results \
             /home/recond/.local/share/recond/state \
    && chown -R recond:recond /opt/recond /home/recond

# Copy project files
COPY --chown=recond:recond bin/recond /opt/recond/bin/
COPY --chown=recond:recond lib/core/*.sh /opt/recond/lib/core/
COPY --chown=recond:recond lib/modules/*.sh /opt/recond/lib/modules/
COPY --chown=recond:recond lib/batch/*.sh /opt/recond/lib/batch/
COPY --chown=recond:recond etc/*.txt etc/*.yaml.example /opt/recond/etc/

# Make executable
RUN chmod +x /opt/recond/bin/recond

# Update paths in main script for container environment
RUN sed -i 's|PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"|PROJECT_ROOT="/opt/recond"|' /opt/recond/bin/recond

# Add to PATH
ENV PATH="/opt/recond/bin:${PATH}"

# Set working directory
WORKDIR /home/recond

# Switch to non-root user
USER recond

# Default output directory
ENV RECOND_OUTPUT_DIR="/home/recond/.local/share/recond/results"

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD recond --version || exit 1

# Default command shows help
ENTRYPOINT ["recond"]
CMD ["--help"]
