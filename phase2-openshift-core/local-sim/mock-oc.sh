#!/usr/bin/env bash
# ==============================================================================
# Script: mock-oc.sh
# Description: Mock OpenShift CLI for local integration testing of scan-openshift.sh
#              without requiring a real OpenShift cluster.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="${MOCK_FIXTURES_DIR:-$SCRIPT_DIR/fixtures}"

# Subcommand routing
case "${1:-}" in
    version)
        echo "Client Version: 4.14.0 (mocked)"
        ;;
    get)
        shift
        resource="${1:-}"
        shift || true

        case "$resource" in
            projects|project)
                # Parse -o jsonpath
                for arg in "$@"; do
                    if [[ "$arg" == *"metadata.name"* ]]; then
                        echo "ecommerce-prod core-banking"
                        exit 0
                    fi
                done
                echo "ecommerce-prod"
                echo "core-banking"
                ;;
            is|imagestream|imagestreams)
                ns=""
                specific_is=""
                jsonpath=""
                while [[ $# -gt 0 ]]; do
                    case "$1" in
                        -n) ns="$2"; shift 2 ;;
                        -o)
                            if [[ "$2" == jsonpath=* ]]; then
                                jsonpath="${2#jsonpath=}"
                            elif [[ "$2" == "json" ]]; then
                                jsonpath="json"
                            fi
                            shift 2
                            ;;
                        -*) shift ;;
                        *)
                            if [[ -z "$specific_is" ]]; then
                                specific_is="$1"
                            fi
                            shift
                            ;;
                    esac
                done

                fixture_file="$FIXTURES_DIR/${ns:-default}-is.json"
                if [[ ! -f "$fixture_file" ]]; then
                    echo "Error from server (NotFound): imagestreams in namespace \"$ns\" not found" >&2
                    exit 1
                fi

                if [[ "$jsonpath" == "json" ]]; then
                    cat "$fixture_file"
                elif [[ -n "$jsonpath" && -n "$specific_is" ]]; then
                    # Extract creation date for a specific tag
                    # Typically: {.status.tags[?(@.tag=="...")].items[0].created}
                    tag=$(echo "$jsonpath" | sed -n 's/.*@\.tag=="\([^"]*\)".*/\1/p')
                    jq -r --arg is "$specific_is" --arg tag "$tag" '
                        .items[] | select(.metadata.name==$is) |
                        .status.tags[] | select(.tag==$tag) |
                        .items[0].created // empty
                    ' "$fixture_file" 2>/dev/null || true
                else
                    cat "$fixture_file"
                fi
                ;;
            *)
                echo "Mock oc: unhandled resource '$resource'" >&2
                exit 1
                ;;
        esac
        ;;
    *)
        echo "Mock oc: unhandled command '$*'" >&2
        exit 1
        ;;
esac
