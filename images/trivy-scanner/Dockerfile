# Stage 1: Official Trivy Binary
FROM aquasec/trivy:0.59.1 AS trivy-bin

# Stage 2: Hardened Ephemeral Worker Container for OpenShift Restricted SCC
FROM alpine:3.19

LABEL maintainer="SecOps Team"
LABEL description="Ultra-lean Ephemeral Trivy Scanner for OpenShift Restricted SCC (<100MB)"

# Install essential lightweight utilities
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    ca-certificates

# Copy Trivy binary from official image
COPY --from=trivy-bin /usr/local/bin/trivy /usr/local/bin/trivy

# Copy self-contained scan and upload entrypoint script
COPY scan-and-upload.sh /usr/local/bin/scan-and-upload.sh
RUN chmod +x /usr/local/bin/scan-and-upload.sh

# Configure directories and OpenShift Group 0 (Arbitrary UID) permissions
RUN mkdir -p /tmp/trivy-cache /tmp/reports && \
    chgrp -R 0 /tmp /etc/ssl/certs && \
    chmod -R g=u /tmp /etc/ssl/certs

# Set environment variables for non-root execution
ENV HOME=/tmp
ENV TRIVY_CACHE_DIR=/tmp/trivy-cache
ENV TRIVY_QUIET=false

# Run as non-root user (Restricted SCC compliant)
USER 10001

ENTRYPOINT ["/usr/local/bin/scan-and-upload.sh"]
