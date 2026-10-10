FROM dependencytrack/frontend:4.11.7

LABEL maintainer="SecOps Team"
LABEL description="OWASP Dependency-Track Frontend Web UI hardened for OpenShift Restricted SCC"

# Switch to root to configure unprivileged permissions
USER root

# Copy unprivileged nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Configure directory permissions for OpenShift Group 0 (Arbitrary UID)
RUN mkdir -p /tmp/client_temp /tmp/proxy_temp_path /tmp/fastcgi_temp /tmp/uwsgi_temp /tmp/scgi_temp /var/cache/nginx /var/log/nginx && \
    chgrp -R 0 /tmp /var/cache/nginx /var/log/nginx /etc/nginx /usr/share/nginx/html /opt/owasp/dependency-track-frontend && \
    chmod -R g=u /tmp /var/cache/nginx /var/log/nginx /etc/nginx /usr/share/nginx/html /opt/owasp/dependency-track-frontend

WORKDIR /opt/owasp/dependency-track-frontend

# Expose unprivileged port
EXPOSE 8080

# Run as non-root user
USER 10001
