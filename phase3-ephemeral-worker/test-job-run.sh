#!/usr/bin/env bash
# ==============================================================================
# Script: test-job-run.sh
# Description: Triggers an Ephemeral Trivy Scanner Job on OpenShift and tails logs
# ==============================================================================

set -euo pipefail

TARGET_IMAGE="${1:-}"
PARENT_VERSION="${2:-main}"
NAMESPACE="secops-sbom"

if [[ -z "$TARGET_IMAGE" ]]; then
    echo "Usage: $0 <target-image-name> [parent-version]"
    echo "Example: $0 image-registry.openshift-image-registry.svc:5000/ecommerce-prod/payment-service:v1.0.0 main"
    exit 1
fi

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

# Export variables for envsubst
export JOB_ID
export TARGET_IMAGE
export PARENT_VERSION

# Generate and apply Job manifest
envsubst < "$SCRIPT_DIR/job-template.yaml" | oc apply -n "$NAMESPACE" -f -

echo "Job created successfully. Waiting for Pod to start..."
oc wait --for=condition=Ready pod -l app.kubernetes.io/name=sbom-scanner,job-name="$JOB_NAME" -n "$NAMESPACE" --timeout=60s || true

echo "Streaming logs from Scanner Job..."
oc logs -f "job/$JOB_NAME" -n "$NAMESPACE"

echo "Job finished. Checking completion status:"
oc get job "$JOB_NAME" -n "$NAMESPACE"
