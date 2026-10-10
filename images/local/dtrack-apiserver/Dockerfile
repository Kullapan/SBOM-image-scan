FROM dependencytrack/apiserver:4.11.7

LABEL maintainer="SecOps Team"
LABEL description="OWASP Dependency-Track API Server hardened for OpenShift Restricted SCC"

# Switch to root temporarily to adjust OpenShift Group 0 permissions and CA directories
USER root

# Setup directories for arbitrary non-root UID (OpenShift Restricted SCC)
# Dependency-Track uses /data for Lucene indexes and temporary files in /tmp
RUN mkdir -p /data /tmp /etc/ssl/certs && \
    chgrp -R 0 /data /tmp /etc/ssl/certs && \
    chmod -R g=u /data /tmp /etc/ssl/certs

# Expose standard API server port
EXPOSE 8080

# Run as non-root user (compatible with OpenShift arbitrary UID)
USER 10001
