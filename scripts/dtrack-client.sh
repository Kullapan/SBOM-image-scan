#!/usr/bin/env bash
# ==============================================================================
# Script: dtrack-client.sh
# Description: REST Client helper functions for OWASP Dependency-Track API
# ==============================================================================

set -euo pipefail

# 1. Check API server connectivity
dtrack_check_health() {
    local base_url="$1"
    local health_url="${base_url%/}/api/version"
    
    local response
    response=$(curl -s -w "\n%{http_code}" "$health_url" || echo -e "\n000")
    local http_code
    http_code=$(tail -n1 <<< "$response")
    local body
    body=$(sed '$d' <<< "$response")

    if [[ "$http_code" == "200" ]]; then
        echo "Dependency-Track API is reachable (Version: $body)"
        return 0
    else
        echo "ERROR: Dependency-Track is not reachable at $health_url (HTTP $http_code)" >&2
        return 1
    fi
}

# 2. Upload CycloneDX BOM to Dependency-Track
# Returns the Processing Token UUID
dtrack_upload_bom() {
    local base_url="$1"
    local api_key="$2"
    local bom_path="$3"
    local project_name="$4"
    local project_version="$5"
    local parent_name="$6"
    local parent_version="${7:-main}"

    if [[ ! -f "$bom_path" ]]; then
        echo "ERROR: BOM file not found: $bom_path" >&2
        return 1
    fi

    local upload_url="${base_url%/}/api/v1/bom"
    
    echo "Uploading BOM to Dependency-Track..."
    echo "  URL: $upload_url"
    echo "  Project: $project_name ($project_version)"
    echo "  Parent:  $parent_name ($parent_version)"

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "$upload_url" \
        -H "X-Api-Key: $api_key" \
        -H "Content-Type: multipart/form-data" \
        -F "autoCreate=true" \
        -F "projectName=$project_name" \
        -F "projectVersion=$project_version" \
        -F "parentName=$parent_name" \
        -F "parentVersion=$parent_version" \
        -F "bom=@$bom_path")

    local http_code
    http_code=$(tail -n1 <<< "$response")
    local body
    body=$(sed '$d' <<< "$response")

    if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
        # Parse token from JSON response {"token":"uuid"}
        local token
        token=$(echo "$body" | grep -o '"token":"[^"]*' | cut -d'"' -f4 || true)
        if [[ -z "$token" ]] && command -v jq >/dev/null 2>&1; then
            token=$(echo "$body" | jq -r '.token // empty')
        fi

        if [[ -n "$token" ]]; then
            echo "$token"
            return 0
        else
            echo "ERROR: Could not parse token from response: $body" >&2
            return 1
        fi
    else
        echo "ERROR: Failed to upload BOM (HTTP $http_code): $body" >&2
        return 1
    fi
}

# 3. Wait / Poll for BOM processing token to complete
dtrack_wait_for_token() {
    local base_url="$1"
    local api_key="$2"
    local token="$3"
    local max_retries="${4:-30}"
    local delay_sec="${5:-3}"

    local token_url="${base_url%/}/api/v1/bom/token/$token"
    echo "Waiting for Dependency-Track to index and process BOM (Token: $token)..."

    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        local response
        response=$(curl -s -w "\n%{http_code}" -X GET "$token_url" \
            -H "X-Api-Key: $api_key" \
            -H "Accept: application/json")

        local http_code
        http_code=$(tail -n1 <<< "$response")
        local body
        body=$(sed '$d' <<< "$response")

        if [[ "$http_code" == "200" ]]; then
            # Body: {"processing":true} or {"processing":false}
            local is_processing="true"
            if echo "$body" | grep -q '"processing":false'; then
                is_processing="false"
            fi

            if [[ "$is_processing" == "false" ]]; then
                echo "✓ BOM processing completed successfully! (Attempt $attempt)"
                return 0
            else
                echo "  [$attempt/$max_retries] BOM is still being processed in queue... retrying in ${delay_sec}s"
                sleep "$delay_sec"
            fi
        else
            echo "  WARNING: Checking token returned HTTP $http_code: $body"
            sleep "$delay_sec"
        fi

        attempt=$((attempt + 1))
    done

    echo "WARNING: Reached maximum timeout waiting for token $token, processing continues in background." >&2
    return 0
}
