ARG BASE_IMAGE=dependencytrack/apiserver:4.11.7
FROM ${BASE_IMAGE}

LABEL maintainer="SecOps Team"
LABEL description="OWASP Dependency-Track API Server hardened for OpenShift Restricted SCC"

# Switch to root temporarily to adjust OpenShift Group 0 permissions and CA directories
USER root

# Setup directories for arbitrary non-root UID (OpenShift Restricted SCC)
# Dependency-Track stores Lucene search indexes, embedded templates, and temp files here.
RUN mkdir -p /data /tmp /etc/ssl/certs && \
    chgrp -R 0 /data /tmp /etc/ssl/certs && \
    chmod -R g=u /data /tmp /etc/ssl/certs

# Ensure /data is the default home for arbitrary UIDs
ENV HOME=/data \
    ALPINE_DATA_DIRECTORY=/data

EXPOSE 8080

# Run as non-root user (OpenShift will override with arbitrary UID from namespace range)
USER 10001
