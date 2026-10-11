#!/usr/bin/env bash
# ==============================================================================
# Script: scan-openshift.sh
# Description: OpenShift-Native Ephemeral Trivy Scanner & SBOM Ingestion Worker
#              Supports both Pipeline Targeted Scan and Scoped Auto-Discovery.
#
# Environment variables:
#   TARGET_IMAGE        Image to scan, or "ALL" / "--all" for auto-discovery (default: ALL)
#   IMAGE_CREATED       Optional explicit image creation timestamp (ISO-8601)
#   DTRACK_URL          Dependency-Track API base URL (default: http://dtrack-apiserver:8080)
#   DTRACK_API_KEY      Dependency-Track API key (required)
#   PARENT_VERSION      Version used for the parent (namespace) project (default: main)
#   MAX_POLL_RETRIES    BOM processing poll attempts (default: 40)
#   POLL_DELAY_SEC      Delay between polls in seconds (default: 3)
#   SKIP_NS_REGEX       Namespaces skipped in ALL mode
#                       (default: ^(openshift|openshift-.*|kube-.*|default|secops-sbom.*)$)
#   FAIL_ON_ERROR       In ALL mode, exit 1 if any image failed (default: true)
#   TRIVY_EXTRA_ARGS    Extra arguments appended to `trivy image`
#   TRIVY_INSECURE      Force skipping TLS verification (default: false; auto-enabled
#                       only when no service CA is available)
#   Native Trivy env vars (e.g. TRIVY_JAVA_DB_REPOSITORY, TRIVY_SKIP_JAVA_DB_UPDATE,
#   TRIVY_TIMEOUT) and proxy env vars (HTTP_PROXY/HTTPS_PROXY/NO_PROXY) are honoured.
# ==============================================================================

set -euo pipefail

TARGET_IMAGE="${1:-${TARGET_IMAGE:-ALL}}"
[[ -z "$TARGET_IMAGE" ]] && TARGET_IMAGE="ALL"
DTRACK_URL="${DTRACK_URL:-http://dtrack-apiserver:8080}"
DTRACK_API_KEY="${DTRACK_API_KEY:-}"
PARENT_VERSION="${PARENT_VERSION:-main}"
[[ -z "$PARENT_VERSION" ]] && PARENT_VERSION="main"
MAX_POLL_RETRIES="${MAX_POLL_RETRIES:-40}"
POLL_DELAY_SEC="${POLL_DELAY_SEC:-3}"
SKIP_NS_REGEX="${SKIP_NS_REGEX:-^(openshift|openshift-.*|kube-.*|default|secops-sbom.*)$}"
FAIL_ON_ERROR="${FAIL_ON_ERROR:-true}"
TRIVY_EXTRA_ARGS="${TRIVY_EXTRA_ARGS:-}"
INTERNAL_REGISTRY="${INTERNAL_REGISTRY:-image-registry.openshift-image-registry.svc:5000}"
TZ_OFFSET_SEC=25200   # UTC+7
TZ_LABEL="+07:00"

API="${DTRACK_URL%/}/api/v1"
SA_DIR="/var/run/secrets/kubernetes.io/serviceaccount"
SA_TOKEN_FILE="$SA_DIR/token"
SERVICE_CA_FILE="$SA_DIR/service-ca.crt"

echo "================================================================="
echo "   OPENSHIFT EPHEMERAL TRIVY SCANNER & SBOM INGESTION WORKER    "
echo "================================================================="

if [[ -z "$DTRACK_API_KEY" ]]; then
    echo "ERROR: DTRACK_API_KEY environment variable is not set." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# TLS trust: system CA bundle + OpenShift service CA (signs the internal registry)
# ------------------------------------------------------------------------------
SYSTEM_CA_BUNDLE=""
for f in /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt; do
    [[ -f "$f" ]] && { SYSTEM_CA_BUNDLE="$f"; break; }
done

if [[ -f "$SERVICE_CA_FILE" ]]; then
    CA_BUNDLE="/tmp/ca-bundle.crt"
    { [[ -n "$SYSTEM_CA_BUNDLE" ]] && cat "$SYSTEM_CA_BUNDLE"; cat "$SERVICE_CA_FILE"; } > "$CA_BUNDLE"
    export SSL_CERT_FILE="$CA_BUNDLE"      # Go (trivy, oc)
    export CURL_CA_BUNDLE="$CA_BUNDLE"     # curl
    export TRIVY_INSECURE="${TRIVY_INSECURE:-false}"
    echo "✓ OpenShift service CA trusted (TRIVY_INSECURE=$TRIVY_INSECURE)"
elif [[ -f "$SA_TOKEN_FILE" ]]; then
    export TRIVY_INSECURE="${TRIVY_INSECURE:-true}"
    echo "⚠ service-ca.crt not found; falling back to TRIVY_INSECURE=$TRIVY_INSECURE" >&2
fi

# Registry authentication with the pod ServiceAccount token
SA_TOKEN=""
if [[ -f "$SA_TOKEN_FILE" ]]; then
    SA_TOKEN="$(cat "$SA_TOKEN_FILE")"
    export TRIVY_USERNAME="${TRIVY_USERNAME:-serviceaccount}"
    export TRIVY_PASSWORD="${TRIVY_PASSWORD:-$SA_TOKEN}"
    echo "✓ In-cluster ServiceAccount token configured for Registry auth"
fi

# ------------------------------------------------------------------------------
# Time helpers
# ------------------------------------------------------------------------------
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
    jq -rn --arg d "$1" '
        ($d | .[0:19] | strptime("%Y-%m-%dT%H:%M:%S") | mktime) as $t
        | ($d | capture("(?<s>[+-])(?<h>[0-9]{2}):(?<m>[0-9]{2})$") // null) as $z
        | if $z == null then $t
          else $t - (($z.s + "1" | tonumber) * (($z.h|tonumber)*3600 + ($z.m|tonumber)*60)) end' 2>/dev/null || echo 0
}

# ------------------------------------------------------------------------------
# Dependency-Track API helper
# Usage: dt_api <METHOD> <path-or-url> [curl args...]
# Sets DT_STATUS to the HTTP status code ("000" on failure) and DT_BODY to response body.
# ------------------------------------------------------------------------------
DT_STATUS=""
DT_BODY=""
dt_api() {
    local method="$1" path="$2"; shift 2
    local url="$path"
    [[ "$url" != http* ]] && url="$API$path"
    local tmp_out
    tmp_out=$(mktemp)
    DT_STATUS=$(curl -sS -w '%{http_code}' -X "$method" \
        -H "X-Api-Key: $DTRACK_API_KEY" "$@" -o "$tmp_out" "$url" 2>/dev/null) || DT_STATUS="000"
    DT_BODY=$(cat "$tmp_out" 2>/dev/null || true)
    rm -f "$tmp_out"
}

# ------------------------------------------------------------------------------
# Image reference parser
# Supports: [registry[:port]/]<namespace>/<name>[:tag][@sha256:digest]
# Sets: IMG_PARENT IMG_PROJECT IMG_TAG
# ------------------------------------------------------------------------------
parse_image_ref() {
    local ref="$1" digest="" tag=""
    if [[ "$ref" == *@* ]]; then
        digest="${ref#*@}"
        ref="${ref%%@*}"
    fi
    local last="${ref##*/}"
    if [[ "$last" == *:* ]]; then
        tag="${last##*:}"
        ref="${ref%:*}"
    fi
    if [[ -z "$tag" ]]; then
        if [[ -n "$digest" ]]; then tag="${digest:0:19}"; else tag="latest"; fi
    fi

    local first="${ref%%/*}"
    if [[ "$ref" == */* && ( "$first" == *.* || "$first" == *:* || "$first" == "localhost" ) ]]; then
        ref="${ref#*/}"
    fi

    if [[ "$ref" == */* ]]; then
        IMG_PARENT="${ref%%/*}"
        IMG_PROJECT="${ref#*/}"
    else
        IMG_PARENT="default-portfolio"
        IMG_PROJECT="$ref"
    fi
    IMG_TAG="$tag"
}

# ------------------------------------------------------------------------------
# Resolve image creation timestamp (ImageStream -> Registry V2 config blob)
# ------------------------------------------------------------------------------
resolve_image_created() {
    local parent="$1" project="$2" tag="$3" created=""

    if command -v oc &>/dev/null; then
        created=$(oc get is "$project" -n "$parent" \
            -o jsonpath="{.status.tags[?(@.tag==\"$tag\")].items[0].created}" 2>/dev/null || true)
    fi

    if [[ -z "$created" && -n "$SA_TOKEN" ]]; then
        local base="https://${INTERNAL_REGISTRY}/v2/${parent}/${project}"
        local accept="application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json"
        local cfg_digest="" auth
        for auth in bearer basic; do
            local auth_args=(-H "Authorization: Bearer $SA_TOKEN")
            [[ "$auth" == "basic" ]] && auth_args=(-u "serviceaccount:$SA_TOKEN")
            cfg_digest=$(curl -s "${auth_args[@]}" -H "Accept: $accept" "$base/manifests/$tag" \
                | jq -r '.config.digest // empty' 2>/dev/null || true)
            if [[ -n "$cfg_digest" ]]; then
                created=$(curl -sL "${auth_args[@]}" "$base/blobs/$cfg_digest" \
                    | jq -r '.created // empty' 2>/dev/null || true)
                break
            fi
        done
    fi
    printf '%s' "$created"
}

# ------------------------------------------------------------------------------
# Function: scan_and_ingest_image
# Args: <target-image> [explicit-created-date]
# Returns non-zero on failure (safe to call with `|| ...`)
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
    parse_image_ref "$target"
    local parent_name="$IMG_PARENT" project_name="$IMG_PROJECT" tag="$IMG_TAG"
    echo "  Parent Portfolio: $parent_name ($PARENT_VERSION)"
    echo "  Project Name:     $project_name"
    echo "  Project Version:  $tag"

    # 2. Extract Creation Date
    local image_created="$explicit_created"
    if [[ -z "$image_created" ]]; then
        echo "  Resolving image creation date (ImageStream / Registry)..."
        image_created=$(resolve_image_created "$parent_name" "$project_name" "$tag")
    fi
    local created_epoch=0
    [[ -n "$image_created" ]] && created_epoch=$(parse_epoch_from_iso "$image_created")
    [[ "$created_epoch" =~ ^[0-9]+$ ]] || created_epoch=0
    local created_local="unknown"
    [[ "$created_epoch" -gt 0 ]] && created_local=$(iso_from_epoch "$created_epoch")
    echo "  Image Created:    ${image_created:-unknown} -> $created_local (UTC+7)"

    # 3. Generate CycloneDX SBOM with Trivy (direct layer inspection, no execution)
    echo "  Generating CycloneDX SBOM..."
    local start_time
    start_time=$(date +%s)
    local extra_args=()
    [[ -n "$TRIVY_EXTRA_ARGS" ]] && read -r -a extra_args <<< "$TRIVY_EXTRA_ARGS"
    if ! trivy image --format cyclonedx --output "$bom_file" "${extra_args[@]}" "$target"; then
        echo "ERROR: Trivy failed for $target" >&2
        return 1
    fi
    echo "  ✓ CycloneDX SBOM generated in $(( $(date +%s) - start_time ))s"

    if [[ ! -s "$bom_file" ]]; then
        echo "ERROR: Generated BOM file is empty: $bom_file" >&2
        return 1
    fi

    # 4. Ensure Parent Project Exists in Dependency-Track
    local parent_payload parent_resp parent_uuid=""
    parent_payload=$(jq -cn --arg n "$parent_name" --arg v "$PARENT_VERSION" \
        '{name:$n, version:$v, classifier:"APPLICATION", active:true}')
    dt_api PUT /project -H "Content-Type: application/json" -d "$parent_payload"
    parent_resp="$DT_BODY"
    if [[ "$DT_STATUS" == "000" ]]; then
        echo "ERROR: Cannot reach Dependency-Track at $DTRACK_URL" >&2
        return 1
    fi
    parent_uuid=$(jq -r '.uuid // empty' <<< "$parent_resp" 2>/dev/null || true)
    if [[ -z "$parent_uuid" ]]; then
        dt_api GET /project/lookup -G \
            --data-urlencode "name=$parent_name" --data-urlencode "version=$PARENT_VERSION"
        parent_resp="$DT_BODY"
        parent_uuid=$(jq -r '.uuid // empty' <<< "$parent_resp" 2>/dev/null || true)
    fi
    [[ -z "$parent_uuid" ]] && echo "  ⚠ Could not resolve parent UUID; relying on parentName/parentVersion" >&2

    # 5. Upload CycloneDX BOM
    echo "  Uploading BOM to Dependency-Track..."
    local form_args=(
        -F "autoCreate=true"
        -F "projectName=$project_name"
        -F "projectVersion=$tag"
        -F "parentName=$parent_name"
        -F "parentVersion=$PARENT_VERSION"
    )
    [[ -n "$parent_uuid" ]] && form_args+=(-F "parentUUID=$parent_uuid")

    local upload_body
    dt_api POST /bom "${form_args[@]}" -F "bom=@$bom_file"
    upload_body="$DT_BODY"
    if [[ "$DT_STATUS" != "200" && "$DT_STATUS" != "201" ]]; then
        echo "ERROR: Failed to upload BOM (HTTP $DT_STATUS): $upload_body" >&2
        return 1
    fi

    local token
    token=$(jq -r '.token // empty' <<< "$upload_body" 2>/dev/null || true)
    echo "  ✓ BOM accepted. Processing Token: ${token:-<none>}"

    # 6. Poll Ingestion Status
    if [[ -n "$token" ]]; then
        local attempt=1 done_processing=false
        while [[ $attempt -le $MAX_POLL_RETRIES ]]; do
            local p_body
            dt_api GET "/bom/token/$token" -H "Accept: application/json"
            p_body="$DT_BODY"
            if [[ "$DT_STATUS" == "200" && "$(jq -r '.processing' <<< "$p_body" 2>/dev/null)" == "false" ]]; then
                done_processing=true
                echo "  ✓ Ingestion and analysis completed successfully!"
                break
            fi
            echo "    [$attempt/$MAX_POLL_RETRIES] Processing in background (HTTP $DT_STATUS)... (${POLL_DELAY_SEC}s)"
            sleep "$POLL_DELAY_SEC"
            attempt=$((attempt + 1))
        done
        if [[ "$done_processing" != "true" ]]; then
            echo "  ⚠ BOM still processing after $MAX_POLL_RETRIES attempts; continuing with reconciliation" >&2
        fi
    else
        echo "  ⚠ No processing token returned; skipping status polling" >&2
    fi

    # 7. Version Lifecycle Reconciliation (scoped to siblings under the SAME parent)
    echo "  Reconciling version active status by creation date..."
    local all_versions
    dt_api GET /project -G \
        --data-urlencode "name=$project_name" \
        --data-urlencode "excludeInactive=false" \
        --data-urlencode "pageNumber=1" \
        --data-urlencode "pageSize=500"
    all_versions="$DT_BODY"
    if [[ "$DT_STATUS" != "200" ]]; then
        echo "  ⚠ Could not list project versions (HTTP $DT_STATUS); skipping reconciliation" >&2
        return 0
    fi

    local siblings
    siblings=$(jq -c --arg n "$project_name" '[.[] | select(.name==$n)]' <<< "$all_versions" 2>/dev/null || echo "[]")

    # 7a. Tag current version with its image creation date and mark it active
    local child
    child=$(jq -c --arg v "$tag" '[.[] | select(.version==$v)][0] // empty' <<< "$siblings")
    if [[ -n "$child" && "$created_epoch" -gt 0 ]]; then
        local child_uuid label tag_payload
        child_uuid=$(jq -r '.uuid' <<< "$child")
        label=$(iso_from_epoch "$created_epoch")
        tag_payload=$(jq -c --arg t "image-created:$label" \
            '{active:true, tags:(((.tags // []) | map(select(.name|startswith("image-created:")|not))) + [{name:$t}])}' <<< "$child")
        dt_api PATCH "/project/$child_uuid" -H "Content-Type: application/json" -d "$tag_payload"
        [[ "$DT_STATUS" != "200" ]] && echo "  ⚠ Failed to tag version $tag (HTTP $DT_STATUS)" >&2
        # Reflect the new tag locally so the newest-version calculation sees it
        siblings=$(jq -c --arg u "$child_uuid" --arg t "image-created:$label" \
            'map(if .uuid==$u then .tags = (((.tags // []) | map(select(.name|startswith("image-created:")|not))) + [{name:$t}]) else . end)' <<< "$siblings")
    fi

    # 7b. Only the newest image (by image-created tag) stays active
    local sib_count
    sib_count=$(jq 'length' <<< "$siblings")
    if [[ "$sib_count" -gt 1 ]]; then
        local max_e=0 newest_u="" row u raw_tag ep
        while IFS= read -r row; do
            u=$(jq -r '.uuid' <<< "$row")
            raw_tag=$(jq -r '[.tags[]? | select(.name|startswith("image-created:")) | .name][0] // empty' <<< "$row")
            ep=0
            [[ -n "$raw_tag" ]] && ep=$(epoch_from_tag "${raw_tag#image-created:}")
            [[ "$ep" =~ ^[0-9]+$ ]] || ep=0
            if [[ $ep -gt $max_e ]]; then
                max_e=$ep
                newest_u="$u"
            fi
        done < <(jq -c '.[]' <<< "$siblings")

        if [[ -n "$newest_u" ]]; then
            local v want cur_act
            while IFS= read -r row; do
                u=$(jq -r '.uuid' <<< "$row")
                v=$(jq -r '.version' <<< "$row")
                cur_act=$(jq -r '.active' <<< "$row")
                want=false
                [[ "$u" == "$newest_u" ]] && want=true
                if [[ "$cur_act" != "$want" ]]; then
                    dt_api PATCH "/project/$u" -H "Content-Type: application/json" \
                        -d "{\"active\":$want}"
                    echo "  State update: $parent_name/$project_name version $v -> active: $want (HTTP $DT_STATUS)"
                fi
            done < <(jq -c '.[]' <<< "$siblings")
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
    if scan_and_ingest_image "$TARGET_IMAGE" "${IMAGE_CREATED:-}"; then
        echo "✓ Scan completed: $TARGET_IMAGE"
    else
        echo "✗ Scan FAILED: $TARGET_IMAGE" >&2
        exit 1
    fi
else
    # --------------------------------------------------------------------------
    # MODE 2: Scoped Auto-Discovery Scan (All Permitted Namespaces)
    # --------------------------------------------------------------------------
    echo "[+] Mode: SCOPED AUTO-DISCOVERY SCAN"
    if ! command -v oc &>/dev/null; then
        echo "ERROR: oc CLI not available in container for Auto-Discovery mode." >&2
        exit 1
    fi

    echo "Querying accessible projects (Scoped RBAC)..."
    if ! PROJECTS=$(oc get projects -o jsonpath='{.items[*].metadata.name}' 2>/tmp/oc-err.log); then
        echo "ERROR: 'oc get projects' failed: $(cat /tmp/oc-err.log)" >&2
        echo "       Check RBAC onboarding and NetworkPolicy egress to the API server (6443)." >&2
        exit 1
    fi

    SCANNED_OK=0
    SCANNED_FAIL=0
    FAILED_IMAGES=()
    for ns in $PROJECTS; do
        if [[ "$ns" =~ $SKIP_NS_REGEX ]]; then
            continue
        fi

        echo ">>> Scanning Namespace: $ns"
        if ! IS_JSON=$(oc get is -n "$ns" -o json 2>/tmp/oc-err.log); then
            echo "    ⚠ Cannot list ImageStreams in $ns: $(cat /tmp/oc-err.log)" >&2
            continue
        fi

        if ! IMAGE_ENTRIES=$(jq -r '
                .items[]? |
                .status.dockerImageRepository as $repo |
                select($repo != null and $repo != "") |
                .status.tags[]? |
                "\($repo):\(.tag) \(.items[0].created // "")"
            ' <<< "$IS_JSON"); then
            echo "    ⚠ Failed to parse ImageStreams in $ns" >&2
            continue
        fi

        if [[ -z "$IMAGE_ENTRIES" ]]; then
            echo "    No ImageStream tags found in $ns"
            continue
        fi

        while IFS=' ' read -r full_img img_created; do
            [[ -z "$full_img" ]] && continue
            echo "[*] Auto-discovered image: $full_img (created: ${img_created:-unknown})"
            if scan_and_ingest_image "$full_img" "$img_created"; then
                SCANNED_OK=$((SCANNED_OK + 1))
            else
                echo "WARNING: Scan failed for $full_img" >&2
                SCANNED_FAIL=$((SCANNED_FAIL + 1))
                FAILED_IMAGES+=("$full_img")
            fi
        done <<< "$IMAGE_ENTRIES"
    done

    echo "================================================================="
    echo "✓ Scoped Auto-Discovery complete."
    echo "  Succeeded: $SCANNED_OK"
    echo "  Failed:    $SCANNED_FAIL"
    for img in "${FAILED_IMAGES[@]}"; do echo "    - $img"; done
    echo "================================================================="
    if [[ "$SCANNED_FAIL" -gt 0 && "$FAIL_ON_ERROR" == "true" ]]; then
        exit 1
    fi
fi
