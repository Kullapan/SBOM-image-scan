#!/usr/bin/env bash
# ==============================================================================
# Script: scan-openshift.sh
# Description: OpenShift-Native Ephemeral Trivy Scanner & SBOM Ingestion Worker
#              Supports both Pipeline Targeted Scan and Scoped Auto-Discovery.
# ==============================================================================

set -euo pipefail

TARGET_IMAGE="${1:-${TARGET_IMAGE:-ALL}}"
DTRACK_URL="${DTRACK_URL:-http://dtrack-apiserver:8080}"
DTRACK_API_KEY="${DTRACK_API_KEY:-}"
PARENT_VERSION="${PARENT_VERSION:-main}"
MAX_POLL_RETRIES="${MAX_POLL_RETRIES:-40}"
POLL_DELAY_SEC="${POLL_DELAY_SEC:-3}"
TZ_OFFSET_SEC=25200   # UTC+7
TZ_LABEL="+07:00"

echo "================================================================="
echo "   OPENSHIFT EPHEMERAL TRIVY SCANNER & SBOM INGESTION WORKER    "
echo "================================================================="

if [[ -z "$DTRACK_API_KEY" ]]; then
    echo "ERROR: DTRACK_API_KEY environment variable is not set." >&2
    exit 1
fi

# Configure OpenShift In-Cluster Registry Authentication for Trivy
SA_TOKEN_FILE="/var/run/secrets/kubernetes.io/serviceaccount/token"
if [[ -f "$SA_TOKEN_FILE" ]]; then
    export TRIVY_USERNAME="${TRIVY_USERNAME:-serviceaccount}"
    export TRIVY_PASSWORD="${TRIVY_PASSWORD:-$(cat "$SA_TOKEN_FILE")}"
    export TRIVY_INSECURE="${TRIVY_INSECURE:-true}"
    echo "✓ In-cluster ServiceAccount token configured for Registry auth"
fi

iso_from_epoch() { 
    jq -rn --argjson e "$1" --argjson o "$TZ_OFFSET_SEC" --arg l "$TZ_LABEL" \
        '(($e + $o) | strftime("%Y-%m-%dT%H:%M:%S")) + $l'
}

epoch_from_tag() { 
    jq -rn --arg v "$1" --argjson o "$TZ_OFFSET_SEC" \
        'if ($v|test("^[0-9]+$")) then ($v|tonumber)
         else ($v | ascii_upcase | .[0:19] | strptime("%Y-%m-%dT%H:%M:%S") | mktime) - $o end' 2>/dev/null || echo 0
}

parse_epoch_from_iso() {
    local d="$1"
    jq -rn --arg d "$d" '
        ($d | .[0:19] | strptime("%Y-%m-%dT%H:%M:%S") | mktime) as $t
        | ($d | capture("(?<s>[+-])(?<h>[0-9]{2}):(?<m>[0-9]{2})$") // null) as $z
        | if $z == null then $t
          else $t - (($z.s + "1" | tonumber) * (($z.h|tonumber)*3600 + ($z.m|tonumber)*60)) end' 2>/dev/null || echo 0
}

# ------------------------------------------------------------------------------
# Function: scan_and_ingest_image
# Args: <target-image> [explicit-created-date]
# ------------------------------------------------------------------------------
scan_and_ingest_image() {
    local target="$1"
    local explicit_created="${2:-}"
    local bom_file="/tmp/cyclonedx-bom.json"
    rm -f "$bom_file"

    echo "-----------------------------------------------------------------"
    echo "Target Image:       $target"
    echo "Dependency-Track:   $DTRACK_URL"

    # 1. Parse Image Name to Portfolio Hierarchy
    local image_without_tag="${target%:*}"
    local tag="${target##*:}"
    [[ "$image_without_tag" == "$tag" ]] && tag="latest"

    local first_part="${image_without_tag%%/*}"
    local image_without_registry="$image_without_tag"
    if [[ "$first_part" == *"."* || "$first_part" == *":"* ]]; then
        image_without_registry="${image_without_tag#*/}"
    fi

    local parent_name="default-portfolio"
    local project_name="$image_without_registry"
    if [[ "$image_without_registry" == *"/"* ]]; then
        parent_name="${image_without_registry%%/*}"
        project_name="${image_without_registry#*/}"
    fi

    echo "  Parent Portfolio: $parent_name ($PARENT_VERSION)"
    echo "  Project Name:     $project_name"
    echo "  Project Version:  $tag"

    # 2. Extract Creation Date from OpenShift ImageStream
    local image_created="$explicit_created"
    if [[ -z "$image_created" ]] && command -v oc &>/dev/null; then
        echo "  Querying ImageStream creation date via oc CLI..."
        image_created=$(oc get is "$project_name" -n "$parent_name" \
            -o jsonpath="{.status.tags[?(@.tag==\"$tag\")].items[0].created}" 2>/dev/null || true)
    fi

    # Fallback to in-cluster registry V2 API if needed
    if [[ -z "$image_created" && -f "$SA_TOKEN_FILE" ]]; then
        local token
        token=$(cat "$SA_TOKEN_FILE")
        local manifest_url="https://image-registry.openshift-image-registry.svc:5000/v2/${parent_name}/${project_name}/manifests/${tag}"
        local cfg_digest
        cfg_digest=$(curl -ks -H "Authorization: Bearer $token" \
            -H "Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json" \
            "$manifest_url" | jq -r '.config.digest // empty' 2>/dev/null || true)
        if [[ -n "$cfg_digest" ]]; then
            local blob_url="https://image-registry.openshift-image-registry.svc:5000/v2/${parent_name}/${project_name}/blobs/${cfg_digest}"
            image_created=$(curl -ks -H "Authorization: Bearer $token" "$blob_url" | jq -r '.created // empty' 2>/dev/null || true)
        fi
    fi

    local created_epoch=0
    [[ -n "$image_created" ]] && created_epoch=$(parse_epoch_from_iso "$image_created")
    local created_local="unknown"
    [[ "$created_epoch" -gt 0 ]] && created_local=$(iso_from_epoch "$created_epoch")
    echo "  Image Created:    ${image_created:-unknown} -> $created_local (UTC+7)"

    # 3. Generate CycloneDX SBOM with Trivy (Direct layer inspection)
    echo "  Generating CycloneDX SBOM..."
    local start_time
    start_time=$(date +%s)
    trivy image \
        --format cyclonedx \
        --output "$bom_file" \
        "$target"

    local duration=$(( $(date +%s) - start_time ))
    echo "  ✓ CycloneDX SBOM generated in ${duration}s"

    if [[ ! -s "$bom_file" ]]; then
        echo "ERROR: Generated BOM file is empty: $bom_file" >&2
        return 1
    fi

    # 4. Ensure Parent Project Exists in Dependency-Track
    local parent_resp
    parent_resp=$(curl -s -X PUT "${DTRACK_URL%/}/api/v1/project" \
        -H "X-Api-Key: $DTRACK_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$parent_name\",\"version\":\"$PARENT_VERSION\",\"classifier\":\"APPLICATION\",\"active\":true}" || true)

    local parent_uuid
    parent_uuid=$(echo "$parent_resp" | jq -r '.uuid // empty' 2>/dev/null || true)
    if [[ -z "$parent_uuid" ]]; then
        parent_resp=$(curl -s -X GET "${DTRACK_URL%/}/api/v1/project/lookup?name=${parent_name}&version=${PARENT_VERSION}" \
            -H "X-Api-Key: $DTRACK_API_KEY" || true)
        parent_uuid=$(echo "$parent_resp" | jq -r '.uuid // empty' 2>/dev/null || true)
    fi

    # 5. Upload CycloneDX BOM
    echo "  Uploading BOM to Dependency-Track..."
    local extra_args=()
    [[ -n "$parent_uuid" ]] && extra_args+=(-F "parentUUID=$parent_uuid")

    local upload_resp
    upload_resp=$(curl -s -w "\n%{http_code}" -X POST "${DTRACK_URL%/}/api/v1/bom" \
        -H "X-Api-Key: $DTRACK_API_KEY" \
        -H "Content-Type: multipart/form-data" \
        -F "autoCreate=true" \
        -F "projectName=$project_name" \
        -F "projectVersion=$tag" \
        -F "parentName=$parent_name" \
        -F "parentVersion=$PARENT_VERSION" \
        "${extra_args[@]}" \
        -F "bom=@$bom_file")

    local http_status
    http_status=$(tail -n1 <<< "$upload_resp")
    local http_body
    http_body=$(sed '$d' <<< "$upload_resp")

    if [[ "$http_status" != "200" && "$http_status" != "201" ]]; then
        echo "ERROR: Failed to upload BOM (HTTP $http_status): $http_body" >&2
        return 1
    fi

    local token
    token=$(echo "$http_body" | jq -r '.token // empty' 2>/dev/null || true)
    echo "  ✓ BOM accepted. Processing Token: $token"

    # 6. Polling Ingestion Status
    local attempt=1
    while [[ $attempt -le $MAX_POLL_RETRIES ]]; do
        local poll_resp
        poll_resp=$(curl -s -w "\n%{http_code}" -X GET "${DTRACK_URL%/}/api/v1/bom/token/$token" \
            -H "X-Api-Key: $DTRACK_API_KEY" \
            -H "Accept: application/json")
        local p_status
        p_status=$(tail -n1 <<< "$poll_resp")
        local p_body
        p_body=$(sed '$d' <<< "$poll_resp")

        if [[ "$p_status" == "200" ]]; then
            local is_proc
            is_proc=$(echo "$p_body" | jq -r '.processing // empty' 2>/dev/null || true)
            if [[ "$is_proc" == "false" ]]; then
                echo "  ✓ Ingestion and analysis completed successfully!"
                break
            else
                echo "    [$attempt/$MAX_POLL_RETRIES] Processing in background... (${POLL_DELAY_SEC}s)"
                sleep "$POLL_DELAY_SEC"
            fi
        fi
        attempt=$((attempt + 1))
    done

    # 7. Version Lifecycle Reconciliation (image-created tag + active state)
    echo "  Reconciling version active status by creation date..."
    local api="${DTRACK_URL%/}/api/v1"
    local auth=(-H "X-Api-Key: $DTRACK_API_KEY")

    local child_resp
    child_resp=$(curl -s "${auth[@]}" "$api/project/lookup?name=${project_name}&version=${tag}" || true)
    local child_uuid
    child_uuid=$(echo "$child_resp" | jq -r '.uuid // empty' 2>/dev/null || true)

    if [[ -n "$child_uuid" && "$created_epoch" -gt 0 ]]; then
        local label
        label=$(iso_from_epoch "$created_epoch")
        local tag_payload
        tag_payload=$(echo "$child_resp" | jq -c --arg t "image-created:$label" \
            '{active:true, tags:(((.tags // []) | map(select(.name|startswith("image-created:")|not))) + [{name:$t}])}')
        curl -s -o /dev/null -X PATCH "${auth[@]}" -H "Content-Type: application/json" \
            -d "$tag_payload" "$api/project/$child_uuid"
    fi

    # Reconcile all siblings of this project
    local all_projects
    all_projects=$(curl -s "${auth[@]}" "$api/project?excludeInactive=false" || true)
    local siblings
    siblings=$(echo "$all_projects" | jq -c --arg n "$project_name" '[.[] | select(.name==$n)]' 2>/dev/null || echo "[]")
    local sib_count
    sib_count=$(echo "$siblings" | jq 'length')

    if [[ "$sib_count" -gt 1 ]]; then
        local max_e=0
        local newest_u=""
        local i=0
        while [[ $i -lt $sib_count ]]; do
            local row
            row=$(echo "$siblings" | jq -c ".[$i]")
            local u
            u=$(echo "$row" | jq -r '.uuid')
            local raw_tag
            raw_tag=$(echo "$row" | jq -r '.tags[]? | select(.name|startswith("image-created:")) | .name' 2>/dev/null | head -n1 || true)
            local tag_val="${raw_tag#image-created:}"
            local ep=0
            [[ -n "$tag_val" ]] && ep=$(epoch_from_tag "$tag_val")
            if [[ $ep -gt $max_e ]]; then
                max_e=$ep
                newest_u="$u"
            fi
            i=$((i + 1))
        done

        if [[ -n "$newest_u" ]]; then
            i=0
            while [[ $i -lt $sib_count ]]; do
                local row
                row=$(echo "$siblings" | jq -c ".[$i]")
                local u
                u=$(echo "$row" | jq -r '.uuid')
                local v
                v=$(echo "$row" | jq -r '.version')
                local want=false
                [[ "$u" == "$newest_u" ]] && want=true
                local cur_act
                cur_act=$(echo "$row" | jq -r '.active')
                if [[ "$cur_act" != "$want" ]]; then
                    curl -s -o /dev/null -X PATCH "${auth[@]}" -H "Content-Type: application/json" \
                        -d "{\"active\":$want}" "$api/project/$u"
                    echo "  State update: version $v -> active: $want"
                fi
                i=$((i + 1))
            done
        fi
    fi
    echo "  ✓ Project reconciled successfully."
}

# ==============================================================================
# MAIN ENTRYPOINT
# ==============================================================================

if [[ "$TARGET_IMAGE" != "ALL" && "$TARGET_IMAGE" != "--all" ]]; then
    # --------------------------------------------------------------------------
    # MODE 1: Targeted Single Image Scan (CI/CD Pipeline)
    # --------------------------------------------------------------------------
    echo "[+] Mode: TARGETED SINGLE IMAGE SCAN"
    scan_and_ingest_image "$TARGET_IMAGE" "${IMAGE_CREATED:-}"
else
    # --------------------------------------------------------------------------
    # MODE 2: Scoped Auto-Discovery Scan (All Permitted Namespaces)
    # --------------------------------------------------------------------------
    echo "[+] Mode: SCOPED AUTO-DISCOVERY SCAN"
    if ! command -v oc &>/dev/null; then
        echo "ERROR: oc CLI not available in container for Auto-Discovery mode." >&2
        exit 1
    fi

    echo "Querying accessible projects (Scoped RBAC: view)..."
    PROJECTS=$(oc get projects -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    SCANNED_TOTAL=0
    for ns in $PROJECTS; do
        # Exclude OpenShift and Kubernetes internal system namespaces
        if [[ "$ns" =~ ^(openshift|kube|secops-sbom) ]]; then
            continue
        fi

        echo ">>> Scanning Namespace: $ns"
        IS_JSON=$(oc get is -n "$ns" -o json 2>/dev/null || echo "{}")
        IMAGE_ENTRIES=$(echo "$IS_JSON" | jq -r '
            .items[]? |
            .metadata.name as $app |
            .status.dockerImageRepository as $repo |
            .status.tags[]? |
            "\($repo):\(\.tag) \(\.items[0].created // empty)"
        ' 2>/dev/null || true)

        if [[ -z "$IMAGE_ENTRIES" ]]; then
            echo "    No ImageStream tags found in $ns"
            continue
        fi

        while IFS=' ' read -r full_img img_created; do
            [[ -z "$full_img" ]] && continue
            echo "[*] Auto-discovered image: $full_img (created: $img_created)"
            scan_and_ingest_image "$full_img" "$img_created" || echo "WARNING: Scan failed for $full_img" >&2
            SCANNED_TOTAL=$((SCANNED_TOTAL + 1))
        done <<< "$IMAGE_ENTRIES"
    done

    echo "================================================================="
    echo "✓ Scoped Auto-Discovery complete. Total images scanned: $SCANNED_TOTAL"
    echo "================================================================="
fi
