# Stage 1: Official Trivy Binary
FROM aquasec/trivy:0.59.1 AS trivy-bin

# Stage 2: Official OpenShift CLI Binary (oc)
FROM quay.io/openshift/origin-cli:4.14 AS oc-bin

# Stage 3: Hardened Ephemeral Worker Container for OpenShift Restricted SCC
FROM alpine:3.19

LABEL maintainer="SecOps Team"
LABEL description="OpenShift-Native Ephemeral Trivy Scanner with oc CLI & Scoped RBAC"

# Install essential lightweight utilities and glibc compatibility for oc binary
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    ca-certificates \
    gcompat \
    libc6-compat

# Copy Trivy binary
COPY --from=trivy-bin /usr/local/bin/trivy /usr/local/bin/trivy

# Copy OpenShift CLI binary
COPY --from=oc-bin /usr/bin/oc /usr/local/bin/oc

# Copy self-contained OpenShift scanner script
COPY scan-openshift.sh /usr/local/bin/scan-openshift.sh
RUN chmod +x /usr/local/bin/scan-openshift.sh

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

ENTRYPOINT ["/usr/local/bin/scan-openshift.sh"]
