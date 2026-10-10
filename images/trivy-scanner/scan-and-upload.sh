#!/usr/bin/env bash
# ==============================================================================
# Script: scan-and-upload.sh
# Description: Generates CycloneDX SBOM with Trivy, ingests to Dependency-Track,
#              and polls until processing and indexing are complete.
# ==============================================================================

set -euo pipefail

TARGET_IMAGE="${1:-${TARGET_IMAGE:-}}"
DTRACK_URL="${DTRACK_URL:-${DTRACK_API_URL:-http://dtrack-apiserver:8080}}"
DTRACK_API_KEY="${DTRACK_API_KEY:-}"
PARENT_VERSION="${PARENT_VERSION:-main}"
MAX_POLL_RETRIES="${MAX_POLL_RETRIES:-40}"
POLL_DELAY_SEC="${POLL_DELAY_SEC:-3}"
BOM_OUTPUT_FILE="/tmp/cyclonedx-bom.json"

echo "================================================================="
echo "        EPHEMERAL TRIVY SCANNER & SBOM INGESTION WORKER         "
echo "================================================================="

if [[ -z "$TARGET_IMAGE" ]]; then
    echo "ERROR: TARGET_IMAGE is required as first argument or environment variable." >&2
    echo "Usage: $0 <image-name>" >&2
    exit 1
fi

if [[ -z "$DTRACK_API_KEY" ]]; then
    echo "ERROR: DTRACK_API_KEY environment variable is not set." >&2
    exit 1
fi

echo "Target Image:       $TARGET_IMAGE"
echo "Dependency-Track:   $DTRACK_URL"

# ------------------------------------------------------------------------------
# 1. Parse Image Name to Portfolio Hierarchy
# ------------------------------------------------------------------------------
image_without_tag="${TARGET_IMAGE%:*}"
tag="${TARGET_IMAGE##*:}"
if [[ "$image_without_tag" == "$tag" ]]; then
    tag="latest"
fi

first_part="${image_without_tag%%/*}"
if [[ "$image_without_tag" == *"/"* ]] && [[ "$first_part" == *"."* || "$first_part" == *":"* || "$first_part" == "localhost" ]]; then
    path_part="${image_without_tag#*/}"
else
    path_part="$image_without_tag"
fi

slash_count=$(awk -F"/" '{print NF-1}' <<< "$path_part")
if [[ "$slash_count" -ge 1 ]]; then
    parent_name="${path_part%%/*}"
    project_name="${path_part#*/}"
    project_name="${project_name//\//-}"
else
    parent_name="default-portfolio"
    project_name="$path_part"
fi

echo "Portfolio Mapping:"
echo "  Parent App (Portfolio): $parent_name ($PARENT_VERSION)"
echo "  Child Project (Image):  $project_name ($tag)"

# ------------------------------------------------------------------------------
# 2. Execute Trivy Scan (Pure Layer Inspection -> CycloneDX JSON)
# ------------------------------------------------------------------------------
echo "-----------------------------------------------------------------"
echo "Generating CycloneDX SBOM with Trivy..."
START_TIME=$(date +%s)

# Ensure cache directory is writable in tmp
export TRIVY_CACHE_DIR="/tmp/trivy-cache"
mkdir -p "$TRIVY_CACHE_DIR"

# Generate complete CycloneDX SBOM (pure inventory, ultra-fast)
trivy image \
    --format cyclonedx \
    --output "$BOM_OUTPUT_FILE" \
    "$TARGET_IMAGE"

# Image creation date (normalised to UTC+7 for project tag: image-created:<ISO>)
TZ_OFFSET_SEC=25200   # UTC+7
TZ_LABEL="+07:00"
iso_from_epoch() { jq -rn --argjson e "$1" --argjson o "$TZ_OFFSET_SEC" --arg l "$TZ_LABEL" \
    '(($e + $o) | strftime("%Y-%m-%dT%H:%M:%S")) + $l'; }
epoch_from_tag() { jq -rn --arg v "$1" --argjson o "$TZ_OFFSET_SEC" \
    'if ($v|test("^[0-9]+$")) then ($v|tonumber)
     else ($v | ascii_upcase | .[0:19] | strptime("%Y-%m-%dT%H:%M:%S") | mktime) - $o end' 2>/dev/null || echo 0; }

# Priority: Environment variable -> CycloneDX metadata timestamp
IMAGE_CREATED="${IMAGE_CREATED:-}"
if [[ -z "$IMAGE_CREATED" ]]; then
    IMAGE_CREATED=$(jq -r '.metadata.timestamp // empty' "$BOM_OUTPUT_FILE" 2>/dev/null || true)
fi

IMAGE_CREATED_EPOCH=0
if [[ -n "$IMAGE_CREATED" ]]; then
    IMAGE_CREATED_EPOCH=$(jq -rn --arg d "$IMAGE_CREATED" '
        ($d | .[0:19] | strptime("%Y-%m-%dT%H:%M:%S") | mktime) as $t
        | ($d | capture("(?<s>[+-])(?<h>[0-9]{2}):(?<m>[0-9]{2})$") // null) as $z
        | if $z == null then $t
          else $t - (($z.s + "1" | tonumber) * (($z.h|tonumber)*3600 + ($z.m|tonumber)*60)) end' 2>/dev/null || echo 0)
fi
IMAGE_CREATED_LOCAL="unknown"
[[ "$IMAGE_CREATED_EPOCH" -gt 0 ]] && IMAGE_CREATED_LOCAL=$(iso_from_epoch "$IMAGE_CREATED_EPOCH")
echo "Image created:      ${IMAGE_CREATED:-unknown} -> $IMAGE_CREATED_LOCAL (UTC+7)"

SCAN_DURATION=$(( $(date +%s) - START_TIME ))
echo "✓ SBOM generated successfully in ${SCAN_DURATION}s -> $BOM_OUTPUT_FILE"

if [[ ! -s "$BOM_OUTPUT_FILE" ]]; then
    echo "ERROR: Output BOM file is empty or missing: $BOM_OUTPUT_FILE" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 3. Ensure Parent Project Exists & Upload CycloneDX BOM
# ------------------------------------------------------------------------------
echo "-----------------------------------------------------------------"
echo "Ensuring Parent Project exists: $parent_name ($PARENT_VERSION)..."
PARENT_RESP=$(curl -s -X PUT "${DTRACK_URL%/}/api/v1/project" \
    -H "X-Api-Key: $DTRACK_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$parent_name\",\"version\":\"$PARENT_VERSION\",\"classifier\":\"APPLICATION\",\"active\":true}" || true)

PARENT_UUID=$(echo "$PARENT_RESP" | jq -r '.uuid // empty' 2>/dev/null || true)
if [[ -z "$PARENT_UUID" ]]; then
    PARENT_RESP=$(curl -s -X GET "${DTRACK_URL%/}/api/v1/project/lookup?name=${parent_name}&version=${PARENT_VERSION}" \
        -H "X-Api-Key: $DTRACK_API_KEY" || true)
    PARENT_UUID=$(echo "$PARENT_RESP" | jq -r '.uuid // empty' 2>/dev/null || true)
fi

echo "  Parent UUID: ${PARENT_UUID:-[auto-detect]}"
echo "Uploading BOM to Dependency-Track API (/api/v1/bom)..."
UPLOAD_ENDPOINT="${DTRACK_URL%/}/api/v1/bom"

EXTRA_PARENT_ARGS=()
if [[ -n "$PARENT_UUID" ]]; then
    EXTRA_PARENT_ARGS+=(-F "parentUUID=$PARENT_UUID")
fi

HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$UPLOAD_ENDPOINT" \
    -H "X-Api-Key: $DTRACK_API_KEY" \
    -H "Content-Type: multipart/form-data" \
    -F "autoCreate=true" \
    -F "projectName=$project_name" \
    -F "projectVersion=$tag" \
    -F "parentName=$parent_name" \
    -F "parentVersion=$PARENT_VERSION" \
    "${EXTRA_PARENT_ARGS[@]}" \
    -F "bom=@$BOM_OUTPUT_FILE")

HTTP_STATUS=$(tail -n1 <<< "$HTTP_RESPONSE")
HTTP_BODY=$(sed '$d' <<< "$HTTP_RESPONSE")

if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "201" ]]; then
    echo "ERROR: Failed to upload BOM (HTTP $HTTP_STATUS): $HTTP_BODY" >&2
    exit 1
fi

TOKEN=$(echo "$HTTP_BODY" | jq -r '.token // empty')
if [[ -z "$TOKEN" ]]; then
    TOKEN=$(grep -o '"token":"[^"]*' <<< "$HTTP_BODY" | cut -d'"' -f4 || true)
fi

if [[ -z "$TOKEN" ]]; then
    echo "ERROR: Could not parse processing token from response: $HTTP_BODY" >&2
    exit 1
fi

echo "✓ BOM accepted for processing. Token: $TOKEN"

# ------------------------------------------------------------------------------
# 4. Ingestion Status Tracking (Poll Token)
# ------------------------------------------------------------------------------
echo "-----------------------------------------------------------------"
echo "Tracking Ingestion Status via GET /api/v1/bom/token/$TOKEN..."

TOKEN_ENDPOINT="${DTRACK_URL%/}/api/v1/bom/token/$TOKEN"
ATTEMPT=1
IS_DONE=0

while [[ $ATTEMPT -le $MAX_POLL_RETRIES ]]; do
    POLL_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "$TOKEN_ENDPOINT" \
        -H "X-Api-Key: $DTRACK_API_KEY" \
        -H "Accept: application/json")

    POLL_STATUS=$(tail -n1 <<< "$POLL_RESPONSE")
    POLL_BODY=$(sed '$d' <<< "$POLL_RESPONSE")

    if [[ "$POLL_STATUS" == "200" ]]; then
        IS_PROCESSING=$(echo "$POLL_BODY" | jq -r '.processing // empty')
        if [[ "$IS_PROCESSING" == "false" ]]; then
            echo "✓ Dependency-Track has finished indexing and analysis!"
            IS_DONE=1
            break
        else
            echo "  [$ATTEMPT/$MAX_POLL_RETRIES] Ingestion in progress... (waiting ${POLL_DELAY_SEC}s)"
            sleep "$POLL_DELAY_SEC"
        fi
    else
        echo "  WARNING: Token check returned HTTP $POLL_STATUS: $POLL_BODY"
        sleep "$POLL_DELAY_SEC"
    fi
    ATTEMPT=$((ATTEMPT + 1))
done

if [[ $IS_DONE -eq 0 ]]; then
    echo "WARNING: Reached max poll retries. Ingestion is still processing in background."
fi

# ------------------------------------------------------------------------------
# 5. Latest-Version Reconciliation (by image creation date)
#    - Store image created time as project tag "image-created:<ISO datetime, UTC+7>"
#      e.g. image-created:2026-10-10T14:55:13+07:00 (legacy epoch tags still read)
#    - Newest created image stays active; older versions become inactive
# ------------------------------------------------------------------------------
echo "-----------------------------------------------------------------"
echo "Reconciling latest version by image creation date..."
API="${DTRACK_URL%/}/api/v1"
AUTH=(-H "X-Api-Key: $DTRACK_API_KEY")

set_project_state() { # uuid epoch active
    local uuid="$1" epoch="$2" active="$3" cur body label="unknown"
    [[ "$epoch" -gt 0 ]] && label=$(iso_from_epoch "$epoch")
    cur=$(curl -s "${AUTH[@]}" "$API/project/$uuid")
    body=$(echo "$cur" | jq -c --arg t "image-created:$label" --argjson a "$active" \
        '{active:$a, tags:(((.tags // []) | map(select(.name|startswith("image-created:")|not))) + [{name:$t}])}')
    curl -s -o /dev/null -X PATCH "${AUTH[@]}" -H "Content-Type: application/json" \
        -d "$body" "$API/project/$uuid"
}

row_epoch() { # project JSON -> epoch of its image-created tag (0 if none)
    local v
    v=$(echo "$1" | jq -r '[.tags[]?.name | select(startswith("image-created:")) | sub("image-created:";"")] | first // empty')
    if [[ -z "$v" ]]; then echo 0; else epoch_from_tag "$v"; fi
}

SELF_UUID=$(curl -s "${AUTH[@]}" "$API/project/lookup?name=${project_name}&version=${tag}" | jq -r '.uuid // empty')
if [[ -z "$SELF_UUID" ]]; then
    echo "  WARNING: cannot resolve project UUID; skipping reconciliation."
else
    # All versions of this project name under the same parent
    ALL=$(curl -s "${AUTH[@]}" "$API/project?name=${project_name}&excludeInactive=false&pageSize=500" \
        | jq -c --arg n "$project_name" --arg p "${PARENT_UUID:-}" \
          '[.[] | select(.name==$n and ((.parent.uuid // $p)==$p))]')

    NEWEST_EPOCH="$IMAGE_CREATED_EPOCH"
    while read -r row; do
        [[ -z "$row" ]] && continue
        u=$(echo "$row" | jq -r '.uuid')
        [[ "$u" == "$SELF_UUID" ]] && continue
        e=$(row_epoch "$row")
        (( e > NEWEST_EPOCH )) && NEWEST_EPOCH="$e"
    done < <(echo "$ALL" | jq -c '.[]')

    if (( IMAGE_CREATED_EPOCH >= NEWEST_EPOCH )); then
        echo "  ✓ $project_name:$tag is the newest image -> ACTIVE (older versions -> inactive)"
        set_project_state "$SELF_UUID" "$IMAGE_CREATED_EPOCH" true
        while read -r row; do
            [[ -z "$row" ]] && continue
            u=$(echo "$row" | jq -r '.uuid'); v=$(echo "$row" | jq -r '.version')
            [[ "$u" == "$SELF_UUID" ]] && continue
            e=$(row_epoch "$row")
            echo "    - deactivate $project_name:$v"
            set_project_state "$u" "$e" false
        done < <(echo "$ALL" | jq -c '.[]')
    else
        echo "  ! $project_name:$tag is OLDER than an existing version -> INACTIVE"
        set_project_state "$SELF_UUID" "$IMAGE_CREATED_EPOCH" false
    fi
fi

# Clean up temporary BOM file
rm -f "$BOM_OUTPUT_FILE"

TOTAL_DURATION=$(( $(date +%s) - START_TIME ))
echo "================================================================="
echo "✓ WORK COMPLETED IN ${TOTAL_DURATION}s"
echo "Project:   $project_name ($tag)"
echo "Parent:    $parent_name ($PARENT_VERSION)"
echo "================================================================="
exit 0
