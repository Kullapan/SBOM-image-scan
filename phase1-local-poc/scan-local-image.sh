#!/usr/bin/env bash
# ==============================================================================
# Script: scan-local-image.sh (Phase 1 Local PoC)
# Description: Triggers ephemeral Trivy scanner container to scan local image
#              via Docker socket and ingest into Dependency-Track.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_IMAGE="${1:-}"

# Load .env if present
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
elif [[ -f "$SCRIPT_DIR/.env.example" && -z "${DTRACK_API_KEY:-}" ]]; then
    echo "Notice: .env not found. Please copy .env.example to .env and configure your DTRACK_API_KEY."
fi

DTRACK_API_KEY="${DTRACK_API_KEY:-}"
NETWORK_NAME="sbom-poc-net"
SCANNER_IMAGE="custom-trivy-scanner:latest"

# 1. Check for sample flag or argument
DEFAULT_SAMPLE_IMAGE="ecommerce-prod/payment-service:v1.0.0"

if [[ "$TARGET_IMAGE" == "--sample" || "$TARGET_IMAGE" == "-s" ]]; then
    TARGET_IMAGE="$DEFAULT_SAMPLE_IMAGE"
fi

if [[ -z "$TARGET_IMAGE" ]]; then
    echo "================================================================="
    echo "❌ ERROR: Target image name is required."
    echo "Usage:   $0 <image-name> [parent-version]"
    echo "         $0 --sample  (Builds & scans sample application)"
    echo "Example: $0 ecommerce-prod/payment-service:v1.0.0 main"
    echo "================================================================="
    exit 1
fi

if [[ -z "$DTRACK_API_KEY" || "$DTRACK_API_KEY" == "your_dtrack_api_key_here" ]]; then
    echo "================================================================="
    echo "❌ ERROR: DTRACK_API_KEY is not configured."
    echo "1. Open Dependency-Track at http://localhost:8080 (admin / admin)"
    echo "2. Go to: Administration -> Access Management -> Teams -> Automation"
    echo "3. Copy an API Key and set it in phase1-local-poc/.env (or export DTRACK_API_KEY=...)"
    echo "================================================================="
    exit 1
fi

PARENT_VERSION="${2:-main}"

# 2. Check if Target Image exists in local Docker daemon
if ! docker image inspect "$TARGET_IMAGE" >/dev/null 2>&1; then
    if [[ "$TARGET_IMAGE" == "$DEFAULT_SAMPLE_IMAGE" ]]; then
        echo "Sample image '$TARGET_IMAGE' not found. Building automatically..."
        "$SCRIPT_DIR/build-sample-image.sh" "$TARGET_IMAGE"
    else
        echo "Notice: Target image '$TARGET_IMAGE' not found locally. Trivy will attempt to pull if accessible."
    fi
fi

# 3. Build Scanner Image if not exists
if ! docker image inspect "$SCANNER_IMAGE" >/dev/null 2>&1; then
    echo "Scanner image '$SCANNER_IMAGE' not found locally. Building from ../images/local/trivy-scanner..."
    docker build -t "$SCANNER_IMAGE" "$SCRIPT_DIR/../images/local/trivy-scanner"
fi

# 4. Ensure Docker network exists
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "Docker network '$NETWORK_NAME' not found. Please start docker-compose first:"
    echo "  cd $SCRIPT_DIR && docker compose up -d"
    exit 1
fi

echo "================================================================="
echo "🚀 Spawning Ephemeral Trivy Scanner Container..."
echo "  Target:        $TARGET_IMAGE"
echo "  Parent Version: $PARENT_VERSION"
echo "  Scanner Image: $SCANNER_IMAGE"
echo "  D-Track URL:   http://dtrack-apiserver:8080"
echo "================================================================="

# 5. Run Ephemeral Trivy Container
# Mounts docker.sock for pure layer inspection (Zero code execution)
# Note: --user 0 is used only in local PoC to read the host docker.sock
IMAGE_CREATED=$(docker image inspect "$TARGET_IMAGE" --format '{{.Created}}' 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

docker run --rm \
    --user 0 \
    --network "$NETWORK_NAME" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e DTRACK_URL="http://dtrack-apiserver:8080" \
    -e DTRACK_API_KEY="$DTRACK_API_KEY" \
    -e PARENT_VERSION="$PARENT_VERSION" \
    -e IMAGE_CREATED="$IMAGE_CREATED" \
    "$SCANNER_IMAGE" \
    "$TARGET_IMAGE"

echo ""
echo "👉 View results in Dependency-Track Dashboard:"
echo "   http://localhost:8080/projects"
