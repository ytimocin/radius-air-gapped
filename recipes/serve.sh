#!/bin/bash
# Script to serve Terraform recipes from a GHCR container via HTTP

set -e

# Default values
IMAGE_NAME=""
IMAGE_TAG="latest"
PORT="8080"
CONTAINER_NAME="recipe-server"

print_usage() {
  echo "Usage: $0 -n <image_name> [-t <image_tag>] [-p <port>] [-c <container_name>]"
  echo ""
  echo "Options:"
  echo "  -n    Image name (e.g., ghcr.io/username/terraform-recipes)"
  echo "  -t    Image tag (default: latest)"
  echo "  -p    Port to expose HTTP server on (default: 8080)"
  echo "  -c    Container name (default: recipe-server)"
  echo "  -h    Show this help message"
}

# Parse command-line arguments
while getopts ":n:t:p:c:h" opt; do
  case $opt in
  n) IMAGE_NAME="${OPTARG}" ;;
  t) IMAGE_TAG="${OPTARG}" ;;
  p) PORT="${OPTARG}" ;;
  c) CONTAINER_NAME="${OPTARG}" ;;
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

# Check if container already exists and remove it if needed
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Removing existing container: ${CONTAINER_NAME}"
  docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

# Pull the latest image
echo "Pulling image: ${IMAGE_NAME}:${IMAGE_TAG}"
docker pull "${IMAGE_NAME}:${IMAGE_TAG}"

# Create a Dockerfile for the web server
TEMP_DIR=$(mktemp -d)
echo "Setting up web server in: ${TEMP_DIR}"

# Fixed Dockerfile generation - avoiding nested heredocs
cat >"${TEMP_DIR}/Dockerfile" <<EOF
FROM ${IMAGE_NAME}:${IMAGE_TAG}

RUN apk add --no-cache nginx && \\
    mkdir -p /var/www/html && \\
    cp /recipes/*.zip /var/www/html/

# Generate recipe index
RUN echo "<html><head><title>Terraform Recipes</title></head><body>" > /var/www/html/index.html && \\
    echo "<h1>Available Terraform Recipes</h1><ul>" >> /var/www/html/index.html && \\
    for recipe in /var/www/html/*.zip; do \\
      filename=\$(basename \$recipe); \\
      echo "<li><a href=\"/\$filename\">\$filename</a></li>" >> /var/www/html/index.html; \\
    done && \\
    echo "</ul></body></html>" >> /var/www/html/index.html

# Setup nginx configuration
RUN mkdir -p /etc/nginx/http.d && \\
    echo 'server {' > /etc/nginx/http.d/default.conf && \\
    echo '    listen 80;' >> /etc/nginx/http.d/default.conf && \\
    echo '    server_name localhost;' >> /etc/nginx/http.d/default.conf && \\
    echo '    root /var/www/html;' >> /etc/nginx/http.d/default.conf && \\
    echo '' >> /etc/nginx/http.d/default.conf && \\
    echo '    location / {' >> /etc/nginx/http.d/default.conf && \\
    echo '        autoindex on;' >> /etc/nginx/http.d/default.conf && \\
    echo '        try_files \$uri \$uri/ =404;' >> /etc/nginx/http.d/default.conf && \\
    echo '        add_header Content-Disposition "attachment";' >> /etc/nginx/http.d/default.conf && \\
    echo '    }' >> /etc/nginx/http.d/default.conf && \\
    echo '}' >> /etc/nginx/http.d/default.conf

CMD ["nginx", "-g", "daemon off;"]
EOF

# Build and run the web server container
echo "Building web server container..."
WEB_SERVER_IMAGE="${CONTAINER_NAME}-image"
docker build -t "${WEB_SERVER_IMAGE}" "${TEMP_DIR}"

echo "Starting web server container on port ${PORT}..."
docker run -d --name "${CONTAINER_NAME}" -p "${PORT}:80" "${WEB_SERVER_IMAGE}"

# Clean up
rm -rf "${TEMP_DIR}"

# Verify the container is running
if docker ps | grep -q "${CONTAINER_NAME}"; then
  echo "✅ Recipe server is now running!"
  echo ""
  echo "Access your Terraform recipes at: http://localhost:${PORT}/"
  echo ""
  echo "Available recipes:"
  docker exec "${CONTAINER_NAME}" find /var/www/html -name "*.zip" -printf "  - http://localhost:${PORT}/%f\n" | sort
  echo ""
  echo "To stop the server: docker stop ${CONTAINER_NAME}"
  echo "To remove the container: docker rm ${CONTAINER_NAME}"
else
  echo "❌ Failed to start recipe server. Check docker logs for details:"
  echo "docker logs ${CONTAINER_NAME}"
  exit 1
fi
