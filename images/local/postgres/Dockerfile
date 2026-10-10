FROM postgres:15-alpine

LABEL maintainer="SecOps Team"
LABEL description="Hardened PostgreSQL 15 for OWASP Dependency-Track on OpenShift"

# Copy custom configurations & init scripts
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY init-dtrack-db.sql /docker-entrypoint-initdb.d/01-init-dtrack.sql

# Prepare directories and grant group-zero (root group) permissions for OpenShift Arbitrary UID
RUN mkdir -p /var/run/postgresql /var/lib/postgresql/data /etc/postgresql && \
    chgrp -R 0 /var/run/postgresql /var/lib/postgresql /etc/postgresql /docker-entrypoint-initdb.d && \
    chmod -R g=u /var/run/postgresql /var/lib/postgresql /etc/postgresql /docker-entrypoint-initdb.d && \
    chmod 644 /etc/postgresql/postgresql.conf /docker-entrypoint-initdb.d/01-init-dtrack.sql

# Expose standard PostgreSQL port
EXPOSE 5432

ENV PGDATA=/var/lib/postgresql/data/pgdata

CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
