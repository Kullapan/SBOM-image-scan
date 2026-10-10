#!/usr/bin/env bash
# ==============================================================================
# Script: build-sample-image.sh (Phase 1 Local PoC)
# Description: Builds the test sample application container image
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_TAG="${1:-ecommerce-prod/payment-service:v1.0.0}"
SAMPLE_DIR="$SCRIPT_DIR/test-samples"

echo "================================================================="
echo "📦 Building Test Sample Image..."
echo "  Context:   $SAMPLE_DIR"
echo "  Image Tag: $SAMPLE_TAG"
echo "================================================================="

docker build -t "$SAMPLE_TAG" "$SAMPLE_DIR"

echo ""
echo "✓ Successfully built test image: $SAMPLE_TAG"
echo "You can now scan it using:"
echo "  ./scan-local-image.sh $SAMPLE_TAG"
