#!/usr/bin/env bash
# ==============================================================================
# Script: test-job-run.sh
# Description: Triggers an Ephemeral Trivy Scanner Job on OpenShift and tails logs.
#              Supports both Single Image mode and Scoped Auto-Discovery (ALL).
# Usage:
#   ./test-job-run.sh <target-image> [parent-version]   # Single Image Mode
#   ./test-job-run.sh ALL                               # Scoped Auto-Discovery Mode
#   ./test-job-run.sh                                   # Defaults to ALL
# ==============================================================================

set -euo pipefail

TARGET_IMAGE="${1:-ALL}"
PARENT_VERSION="${2:-main}"
NAMESPACE="secops-sbom"

JOB_ID=$(date +%s)
JOB_NAME="sbom-scan-job-${JOB_ID}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================================="
echo "🚀 Triggering OpenShift Ephemeral Trivy Scan Job..."
echo "  Job Name:       $JOB_NAME"
echo "  Target Image:   $TARGET_IMAGE"
echo "  Parent Version: $PARENT_VERSION"
echo "  Namespace:      $NAMESPACE"
echo "================================================================="

IMAGE_CREATED=""
if [[ "$TARGET_IMAGE" != "ALL" && "$TARGET_IMAGE" != "--all" ]]; then
    # Parse image name: [registry/]<parent>/<project>:<tag>
    img_no_tag="${TARGET_IMAGE%:*}"
    tag="${TARGET_IMAGE##*:}"
    [[ "$img_no_tag" == "$tag" ]] && tag="latest"
    img_no_reg="$img_no_tag"
    first_part="${img_no_tag%%/*}"
    if [[ "$first_part" == *"."* || "$first_part" == *":"* ]]; then
        img_no_reg="${img_no_tag#*/}"
    fi
    parent_ns="${img_no_reg%%/*}"
    project="${img_no_reg#*/}"

    if command -v oc &>/dev/null; then
        echo "Pre-fetching ImageStream creation date via oc..."
        IMAGE_CREATED=$(oc get is "$project" -n "$parent_ns" \
            -o jsonpath="{.status.tags[?(@.tag==\"$tag\")].items[0].created}" 2>/dev/null || true)
        [[ -n "$IMAGE_CREATED" ]] && echo "  Found creation date: $IMAGE_CREATED"
    fi
fi

# Export variables for envsubst
export JOB_ID
export TARGET_IMAGE
export PARENT_VERSION
export IMAGE_CREATED

# Generate and apply Job manifest
envsubst < "$SCRIPT_DIR/job-template.yaml" | oc apply -n "$NAMESPACE" -f -

echo "Job created successfully. Waiting for Pod to start..."
oc wait --for=condition=Ready pod -l app.kubernetes.io/name=sbom-scanner,job-name="$JOB_NAME" -n "$NAMESPACE" --timeout=60s || true

echo "Streaming logs from Scanner Job..."
oc logs -f "job/$JOB_NAME" -n "$NAMESPACE"

echo "Job finished. Checking completion status:"
oc get job "$JOB_NAME" -n "$NAMESPACE"
