#!/usr/bin/env bash
# ==============================================================================
# Script: export-total-sbom.sh
# Description: Wrapper to export aggregated components and CycloneDX SBOM
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-$SCRIPT_DIR/../reports}"

if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
else
    echo "ERROR: Python is required to run export-total-sbom." >&2
    exit 1
fi

"$PYTHON_CMD" "$SCRIPT_DIR/export-total-sbom.py" "$OUTPUT_DIR"
