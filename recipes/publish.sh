#!/bin/bash
# Script to zip Terraform recipes and publish them to GHCR

set -e

# Default values
RECIPE_DIR="./recipes"
IMAGE_NAME=""
IMAGE_TAG="latest"
TEMP_DIR=""

print_usage() {
  echo "Usage: $0 -d <recipe_directory> -n <image_name> [-t <image_tag>]"
  echo ""
  echo "Options:"
  echo "  -d    Directory containing Terraform recipe folders"
  echo "  -n    Image name (e.g., ghcr.io/username/terraform-recipes)"
  echo "  -t    Image tag (default: latest)"
  echo "  -h    Show this help message"
}

# Parse command-line arguments
while getopts ":d:n:t:h" opt; do
  case $opt in
  d) RECIPE_DIR="${OPTARG}" ;;
  n) IMAGE_NAME="${OPTARG}" ;;
  t) IMAGE_TAG="${OPTARG}" ;;
  h)
    print_usage
    exit 0
    ;;
  \?)
    echo "Invalid option: -${OPTARG}" >&2
    print_usage
    exit 1
    ;;
  :)
    echo "Option -${OPTARG} requires an argument." >&2
    print_usage
    exit 1
    ;;
  esac
done

# Validate required parameters
if [ -z "$IMAGE_NAME" ]; then
  echo "Error: Image name is required."
  print_usage
  exit 1
fi

if [ ! -d "$RECIPE_DIR" ]; then
  echo "Error: Recipe directory '$RECIPE_DIR' does not exist."
  exit 1
fi

# Create temporary directory for building the container
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

# Create directory structure for recipes
mkdir -p "$TEMP_DIR/recipes"

# Create a temporary file to track processed directories (compatible with Bash 3.x on macOS)
PROCESSED_DIRS_FILE="${TEMP_DIR}/processed_dirs.txt"
touch "$PROCESSED_DIRS_FILE"

# Find all directories containing Terraform files
echo "Processing recipes from: $RECIPE_DIR"

# First find all directories containing .tf files
while IFS= read -r tf_file; do
  recipe_dir=$(dirname "$tf_file")

  # Check if we've already processed this directory by looking up in the temp file
  if grep -q "^${recipe_dir}$" "$PROCESSED_DIRS_FILE"; then
    continue
  fi

  # Mark as processed by appending to the file
  echo "$recipe_dir" >>"$PROCESSED_DIRS_FILE"

  # Get the relative path from the RECIPE_DIR
  rel_path="${recipe_dir#"$RECIPE_DIR"/}"

  # Create flattened name (replace / with -)
  flattened_name=$(echo "$rel_path" | tr '/' '-')

  echo "Zipping recipe: $rel_path as $flattened_name"

  # Create zip archive
  (cd "$recipe_dir" && zip -r "$TEMP_DIR/recipes/$flattened_name.zip" . -x "*.git*" "*.DS_Store")

  echo "✅ Created $flattened_name.zip"
done < <(find "$RECIPE_DIR" -type f -name "*.tf")

# Check if we found any recipe
if [ ! "$(ls -A "$TEMP_DIR/recipes")" ]; then
  echo "Error: No Terraform recipes found in '$RECIPE_DIR' or its subdirectories."
  rm -rf "$TEMP_DIR"
  exit 1
fi

# Create Dockerfile with Azure best practices
cat >"$TEMP_DIR/Dockerfile" <<EOF
FROM alpine:3.18

LABEL org.opencontainers.image.source=https://github.com/$(echo "$IMAGE_NAME" | cut -d'/' -f2-3)
LABEL org.opencontainers.image.description="Terraform recipes container for air-gapped environments"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.vendor="$(echo "$IMAGE_NAME" | cut -d'/' -f2)"
LABEL org.opencontainers.image.created="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
LABEL org.opencontainers.image.version="${IMAGE_TAG}"

# Add security labels
LABEL security.provider="User Managed"
LABEL security.compliance="User Responsibility"

# Ensure the image has minimal attack surface
RUN apk upgrade --no-cache && \\
    addgroup -S recipes && \\
    adduser -S recipes -G recipes

WORKDIR /recipes
COPY recipes/*.zip /recipes/
RUN chown -R recipes:recipes /recipes && \\
    chmod -R 755 /recipes

USER recipes

CMD ["sh", "-c", "echo 'This image contains Terraform recipes. Mount /recipes to access them.'"]
EOF

echo "Created Dockerfile with Azure best practices"

# Build container image
echo "Building container image: $IMAGE_NAME:$IMAGE_TAG"
docker build -t "$IMAGE_NAME:$IMAGE_TAG" "$TEMP_DIR"

# Check if user is logged in to GitHub Container Registry
if ! docker login ghcr.io -u "$(echo "$IMAGE_NAME" | cut -d'/' -f2)" >/dev/null 2>&1; then
  echo "⚠️ Not logged in to ghcr.io. Please login first with:"
  echo "export GITHUB_CR_PAT=<your-github-personal-access-token>"
  echo "echo \$GITHUB_CR_PAT | docker login ghcr.io -u <your-github-username> --password-stdin"

  # Clean up
  rm -rf "$TEMP_DIR"
  exit 1
fi

# Push container image
echo "Pushing container image to GHCR: $IMAGE_NAME:$IMAGE_TAG"
docker push "$IMAGE_NAME:$IMAGE_TAG"

# Clean up
rm -rf "$TEMP_DIR"
echo "✅ Successfully published Terraform recipes to $IMAGE_NAME:$IMAGE_TAG"
echo ""
echo "To use this in an air-gapped environment:"
echo "1. Pull the image: docker pull $IMAGE_NAME:$IMAGE_TAG"
echo "2. Extract the recipes: docker run --rm -v /path/to/output:/output $IMAGE_NAME:$IMAGE_TAG sh -c 'cp /recipes/*.zip /output/'"
echo ""
echo "Azure best practices applied:"
echo "- Non-root user for container security"
echo "- Minimal base image with reduced attack surface"
echo "- Proper OCI labels for image metadata"
echo "- Permissions secured for sensitive files"
