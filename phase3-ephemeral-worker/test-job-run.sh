#!/usr/bin/env bash
# ==============================================================================
# Script: test-job-run.sh
# Description: Triggers an Ephemeral Trivy Scanner Job on OpenShift, tails logs,
#              and exits non-zero if the Job fails (CI/CD friendly).
#              Supports both Single Image mode and Scoped Auto-Discovery (ALL).
# Usage:
#   ./test-job-run.sh <target-image> [parent-version]   # Single Image Mode
#   ./test-job-run.sh ALL                               # Scoped Auto-Discovery Mode
#   ./test-job-run.sh                                   # Defaults to ALL
# Env:
#   NAMESPACE (default secops-sbom), JOB_TIMEOUT (default 7200s)
#   DRY_RUN=true  -> only render the manifest to stdout
# ==============================================================================

set -euo pipefail

TARGET_IMAGE="${1:-ALL}"
PARENT_VERSION="${2:-main}"
NAMESPACE="${NAMESPACE:-secops-sbom}"
JOB_TIMEOUT="${JOB_TIMEOUT:-7200s}"
DRY_RUN="${DRY_RUN:-false}"

JOB_ID=$(date +%s)
JOB_NAME="sbom-scan-job-${JOB_ID}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for bin in envsubst oc; do
    if [[ "$bin" == "oc" && "$DRY_RUN" == "true" ]]; then continue; fi
    command -v "$bin" &>/dev/null || { echo "ERROR: '$bin' is required" >&2; exit 1; }
done

echo "=================================================================" >&2
echo "🚀 Triggering OpenShift Ephemeral Trivy Scan Job..." >&2
echo "  Job Name:       $JOB_NAME" >&2
echo "  Target Image:   $TARGET_IMAGE" >&2
echo "  Parent Version: $PARENT_VERSION" >&2
echo "  Namespace:      $NAMESPACE" >&2
echo "=================================================================" >&2

IMAGE_CREATED=""
if [[ "$TARGET_IMAGE" != "ALL" && "$TARGET_IMAGE" != "--all" && "$DRY_RUN" != "true" ]]; then
    # Parse image name: [registry[:port]/]<namespace>/<name>[:tag]
    ref="${TARGET_IMAGE%%@*}"
    last="${ref##*/}"
    tag="latest"
    if [[ "$last" == *:* ]]; then tag="${last##*:}"; ref="${ref%:*}"; fi
    first="${ref%%/*}"
    if [[ "$ref" == */* && ( "$first" == *.* || "$first" == *:* || "$first" == "localhost" ) ]]; then
        ref="${ref#*/}"
    fi
    parent_ns="${ref%%/*}"
    project="${ref#*/}"

    echo "Pre-fetching ImageStream creation date via oc..." >&2
    IMAGE_CREATED=$(oc get is "$project" -n "$parent_ns" \
        -o jsonpath="{.status.tags[?(@.tag==\"$tag\")].items[0].created}" 2>/dev/null || true)
    [[ -n "$IMAGE_CREATED" ]] && echo "  Found creation date: $IMAGE_CREATED" >&2
fi

export JOB_ID TARGET_IMAGE PARENT_VERSION IMAGE_CREATED

# Restricted variable list: only these placeholders are substituted
MANIFEST=$(envsubst '${JOB_ID} ${TARGET_IMAGE} ${PARENT_VERSION} ${IMAGE_CREATED}' \
    < "$SCRIPT_DIR/job-template.yaml")

if [[ "$DRY_RUN" == "true" ]]; then
    echo "$MANIFEST"
    exit 0
fi

echo "$MANIFEST" | oc apply -n "$NAMESPACE" -f -

echo "Job created. Waiting for Pod to start..." >&2
oc wait --for=condition=Ready pod -l job-name="$JOB_NAME" -n "$NAMESPACE" --timeout=180s || true

echo "Streaming logs from Scanner Job..." >&2
oc logs -f "job/$JOB_NAME" -n "$NAMESPACE" || true

# Wait for a terminal state (complete OR failed)
echo "Waiting for Job completion (timeout $JOB_TIMEOUT)..." >&2
end=$(( $(date +%s) + ${JOB_TIMEOUT%s} ))
while :; do
    succeeded=$(oc get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)
    failed_cond=$(oc get job "$JOB_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || true)
    if [[ "${succeeded:-0}" -ge 1 ]]; then
        echo "✓ Job $JOB_NAME succeeded" >&2
        oc get job "$JOB_NAME" -n "$NAMESPACE"
        exit 0
    fi
    if [[ "$failed_cond" == "True" ]]; then
        echo "✗ Job $JOB_NAME FAILED" >&2
        oc get job "$JOB_NAME" -n "$NAMESPACE"
        exit 1
    fi
    if [[ $(date +%s) -ge $end ]]; then
        echo "✗ Timed out waiting for Job $JOB_NAME" >&2
        exit 1
    fi
    sleep 5
done
