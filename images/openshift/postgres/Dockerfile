# ==============================================================================
# Hardened PostgreSQL 15 for OpenShift Restricted SCC
#
# Uses the Red Hat / SCLOrg PostgreSQL container image, which is explicitly
# designed for OpenShift Arbitrary UID / Group 0 execution:
#   - Automatic effective UID lookup via nss_wrapper
#   - Pre-configured entrypoint `/usr/bin/container-entrypoint run-postgresql`
#   - Built-in container health check: `/usr/libexec/check-container`
#   - Drop-in configuration via `/opt/app-root/src/postgresql-cfg/*.conf`
#   - Drop-in init SQL via `/opt/app-root/src/postgresql-init/*.sql`
#
# Production Note: On clusters with a Red Hat Registry pull secret, you can
# substitute BASE_IMAGE with `registry.redhat.io/rhel9/postgresql-15:latest`.
# ==============================================================================
ARG BASE_IMAGE=quay.io/sclorg/postgresql-15-c9s:latest
FROM ${BASE_IMAGE}

LABEL maintainer="SecOps Team"
LABEL description="Hardened PostgreSQL 15 for OWASP Dependency-Track on OpenShift Restricted SCC"

# Copy custom configuration tuning for Dependency-Track
COPY postgresql.conf /opt/app-root/src/postgresql-cfg/dtrack-tuning.conf

# Copy initialization SQL (uuid-ossp extension, UTC timezone)
COPY init-dtrack-db.sql /opt/app-root/src/postgresql-init/01-init-dtrack.sql

# Ensure files are readable by arbitrary UID (Group 0)
USER 0
RUN chgrp -R 0 /opt/app-root/src/postgresql-cfg /opt/app-root/src/postgresql-init && \
    chmod -R g=u /opt/app-root/src/postgresql-cfg /opt/app-root/src/postgresql-init && \
    chmod 0644 /opt/app-root/src/postgresql-cfg/dtrack-tuning.conf \
               /opt/app-root/src/postgresql-init/01-init-dtrack.sql

# Run as unprivileged postgres user (UID 26, OpenShift will override with namespace UID)
USER 26

EXPOSE 5432
