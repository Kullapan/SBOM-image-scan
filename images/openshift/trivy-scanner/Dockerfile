# ==============================================================================
# OpenShift Ephemeral Trivy Scanner (trivy + oc + jq + curl)
#
# Base images are parameterised so they can be redirected to an internal mirror
# (Nexus / Quay) via BuildConfig `dockerStrategy.buildArgs` or `--build-arg`.
# For production, pin each image by digest, e.g. aquasec/trivy:0.59.1@sha256:...
# ==============================================================================
ARG TRIVY_IMAGE=docker.io/aquasec/trivy:0.59.1
ARG OC_IMAGE=quay.io/openshift/origin-cli:4.14
ARG BASE_IMAGE=registry.access.redhat.com/ubi9/ubi-minimal:latest

# Stage 1: Official Trivy Binary (statically linked Go binary)
FROM ${TRIVY_IMAGE} AS trivy-bin

# Stage 2: Official OpenShift CLI Binary (oc, glibc-linked)
FROM ${OC_IMAGE} AS oc-bin

# Stage 3: Hardened Ephemeral Worker on UBI (glibc => native `oc` compatibility)
FROM ${BASE_IMAGE}

LABEL maintainer="SecOps Team"
LABEL description="OpenShift-Native Ephemeral Trivy Scanner with oc CLI & Scoped RBAC"

# Essential utilities (bash is already part of ubi-minimal)
RUN microdnf install -y --nodocs jq ca-certificates && \
    (command -v curl >/dev/null || microdnf install -y --nodocs curl-minimal) && \
    microdnf clean all

COPY --from=trivy-bin /usr/local/bin/trivy /usr/local/bin/trivy
COPY --from=oc-bin /usr/bin/oc /usr/local/bin/oc

# Fail the build early if any binary cannot execute on this base image
RUN trivy --version && oc version --client && jq --version && curl --version | head -n1

COPY scan-openshift.sh /usr/local/bin/scan-openshift.sh
RUN chmod 0755 /usr/local/bin/scan-openshift.sh

# Writable dirs for arbitrary UID (OpenShift Group 0). At runtime /tmp is an emptyDir.
RUN mkdir -p /tmp/trivy-cache /tmp/reports && \
    chgrp -R 0 /tmp && \
    chmod -R g=u /tmp

ENV HOME=/tmp \
    TRIVY_CACHE_DIR=/tmp/trivy-cache \
    TRIVY_QUIET=false

# Non-root (OpenShift will override with an arbitrary UID from the namespace range)
USER 10001

ENTRYPOINT ["/usr/local/bin/scan-openshift.sh"]
