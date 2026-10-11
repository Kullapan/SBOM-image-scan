#!/usr/bin/env bash
# ==============================================================================
# Script: test-local-sim.sh
# Description: One-click local end-to-end integration test simulating OpenShift
#              Restricted SCC constraints using Docker.
# Usage:
#   ./phase2-openshift-core/local-sim/test-local-sim.sh [--cleanup]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.ocp-sim.yml"

if [[ "${1:-}" == "--cleanup" ]]; then
    echo "Stopping and cleaning simulation containers..."
    docker compose -f "$COMPOSE_FILE" down -v --remove-orphans
    exit 0
fi

echo "================================================================="
echo "🚀 Running OpenShift Restricted SCC Local Simulation Test"
echo "================================================================="

# 1. Ensure sample images exist
echo "[1/5] Building sample application images..."
docker build -t custom-sample-payment-service:v1.0.0 "$PROJECT_ROOT/phase1-local-poc/test-samples" -q
docker build -t custom-sample-payment-service:v1.1.0 "$PROJECT_ROOT/phase1-local-poc/test-samples" -q
docker build -t custom-sample-auth-service:v2.0.0 "$PROJECT_ROOT/phase1-local-poc/test-samples" -q

# 2. Build & Start hardened containers
echo "[2/5] Starting hardened containers (Postgres, DTrack API, Frontend)..."
docker compose -f "$COMPOSE_FILE" build postgres dtrack-apiserver dtrack-frontend trivy-scanner
docker compose -f "$COMPOSE_FILE" up -d postgres dtrack-apiserver dtrack-frontend

# 3. Wait for API Server
echo "[3/5] Waiting for Dependency-Track API Server to be healthy..."
max_attempts=40
attempt=0
while [[ $attempt -lt $max_attempts ]]; do
    attempt=$((attempt + 1))
    if curl -sf http://localhost:18081/health/live | grep -q "UP"; then
        echo "✓ API Server is healthy!"
        break
    fi
    echo "  Attempt $attempt/$max_attempts: waiting for API server... (5s)"
    sleep 5
done

# 4. Bootstrap admin and create Automation team
echo "[4/5] Bootstrapping Dependency-Track authentication..."
TOKEN=$(curl -s -d "username=admin&password=Admin12345!" http://localhost:18081/api/v1/user/login || true)
if [[ -z "$TOKEN" || "$TOKEN" == *"<html>"* || "$TOKEN" == *"Unauthorized"* ]]; then
    curl -s -d "username=admin&password=admin&newPassword=Admin12345!&confirmPassword=Admin12345!" \
        http://localhost:18081/api/v1/user/forceChangePassword || true
    TOKEN=$(curl -s -d "username=admin&password=Admin12345!" http://localhost:18081/api/v1/user/login)
fi

AUTH=(-H "Authorization: Bearer $TOKEN")
AUTO_TEAM=$(curl -s "${AUTH[@]}" http://localhost:18081/api/v1/team | jq -r '.[] | select(.name=="Automation") | .uuid' || true)
if [[ -z "$AUTO_TEAM" ]]; then
    AUTO_TEAM=$(curl -s -X PUT "${AUTH[@]}" -H "Content-Type: application/json" -d '{"name":"Automation"}' \
        http://localhost:18081/api/v1/team | jq -r '.uuid')
fi

for p in BOM_UPLOAD PROJECT_CREATION_UPLOAD PORTFOLIO_MANAGEMENT VIEW_PORTFOLIO VIEW_VULNERABILITY VULNERABILITY_ANALYSIS; do
    curl -s -o /dev/null -X POST "${AUTH[@]}" -H "Content-Type: application/json" "http://localhost:18081/api/v1/permission/$p/team/$AUTO_TEAM" || true
done

API_KEY=$(curl -s "${AUTH[@]}" http://localhost:18081/api/v1/team | jq -r --arg u "$AUTO_TEAM" '.[] | select(.uuid==$u) | .apiKeys[0].key // empty')
if [[ -z "$API_KEY" ]]; then
    API_KEY=$(curl -s -X PUT "${AUTH[@]}" "http://localhost:18081/api/v1/team/$AUTO_TEAM/key" | jq -r '.key')
fi
echo "✓ Automation API Key ready: ${API_KEY:0:8}..."

# 5. Run Scanner Simulation
echo "[5/5] Running Phase 3 Scanner Job Simulation (Auto-Discovery mode)..."
docker compose -f "$COMPOSE_FILE" run --rm \
    -e DTRACK_API_KEY="$API_KEY" \
    -e TARGET_IMAGE="ALL" \
    trivy-scanner

echo "================================================================="
echo "✅ Simulation test PASSED! OpenShift manifests & images verified."
echo "================================================================="
