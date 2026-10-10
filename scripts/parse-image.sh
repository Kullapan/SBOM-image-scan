#!/usr/bin/env bash
# ==============================================================================
# Script: parse-image.sh
# Description: Parses a container image name into portfolio hierarchy components
#
# Standard format: [<REGISTRY>/]<APP_NAME>/<SERVICE_NAME>:<TAG>
# Output variables:
#   IMAGE_REGISTRY
#   PARENT_NAME       (appName)
#   PARENT_VERSION    (default: main)
#   PROJECT_NAME      (serviceName)
#   PROJECT_VERSION   (tag)
# ==============================================================================

set -euo pipefail

parse_image_components() {
    local full_image="$1"
    local default_parent_version="${2:-main}"

    # Extract tag (anything after the last colon)
    local image_without_tag="${full_image%:*}"
    local tag="${full_image##*:}"

    if [[ "$image_without_tag" == "$tag" ]]; then
        # No tag specified, fallback to latest
        tag="latest"
    fi

    # Check if registry host exists (contains dot, colon, or localhost in first component)
    local registry=""
    local path_part=""
    local first_part="${image_without_tag%%/*}"

    if [[ "$image_without_tag" == *"/"* ]] && [[ "$first_part" == *"."* || "$first_part" == *":"* || "$first_part" == "localhost" ]]; then
        registry="$first_part"
        path_part="${image_without_tag#*/}"
    else
        path_part="$image_without_tag"
    fi

    local parent_name=""
    local project_name=""

    # Count slashes in path_part
    local slash_count
    slash_count=$(awk -F"/" '{print NF-1}' <<< "$path_part")

    if [[ "$slash_count" -ge 1 ]]; then
        # Format: appName/serviceName (or nested path)
        # parentName is the top-level app, serviceName is the leaf service
        parent_name="${path_part%%/*}"
        project_name="${path_part#*/}"
        # If deeply nested, replace slashes with dash for project_name
        project_name="${project_name//\//-}"
    else
        # Single name without slash (e.g. redis:alpine)
        parent_name="default-portfolio"
        project_name="$path_part"
    fi

    export IMAGE_REGISTRY="$registry"
    export PARENT_NAME="$parent_name"
    export PARENT_VERSION="$default_parent_version"
    export PROJECT_NAME="$project_name"
    export PROJECT_VERSION="$tag"

    echo "Parsed Image: $full_image"
    echo "  -> Registry:        ${IMAGE_REGISTRY:-[local/none]}"
    echo "  -> Parent App:      $PARENT_NAME"
    echo "  -> Parent Version:  $PARENT_VERSION"
    echo "  -> Project (Child): $PROJECT_NAME"
    echo "  -> Project Version: $PROJECT_VERSION"
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <image-name> [parent-version]"
        echo "Example: $0 image-registry.openshift.svc:5000/ecommerce/payment-api:1.0.0 main"
        exit 1
    fi
    parse_image_components "$1" "${2:-main}"
fi
