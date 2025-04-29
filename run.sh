#!/bin/bash
set -e

# =====================================
# Configuration
# =====================================
CLUSTER_NAME="air-gapped-cluster"
REGISTRY_NAME="registry.localhost"
REGISTRY_SERVER="localhost"
REGISTRY_PORT="6060"
NETWORK_NAME="kind-network"
CERTS_DIR="$(pwd)/certs"
CA_CERT_PATH="/etc/ssl/certs/local-ca.crt"

# Registry URLs
REGISTRY_HOST="${REGISTRY_NAME}:${REGISTRY_PORT}"
LOCALHOST_REGISTRY="localhost:${REGISTRY_PORT}"

# Radius version
RADIUS_VERSION="0.45"

# Chart paths
CHARTS_DIR="$(pwd)/charts"
mkdir -p "${CHARTS_DIR}"

RADIUS_CHART="${CHARTS_DIR}/radius-${RADIUS_VERSION}.0.tgz"
# CONTOUR_CHART="${CHARTS_DIR}/contour-11.1.1.tgz"
# DAPR_CHART="${CHARTS_DIR}/dapr-1.14.4.tgz"

# =====================================
# Helper Functions
# =====================================
log() {
  local level=$1
  shift
  echo "$(date '+%Y-%m-%d %H:%M:%S') [${level}] $*"
}

info() {
  log "INFO" "$@"
}

warn() {
  log "WARN" "$@" >&2
}

error() {
  log "ERROR" "$@" >&2
  exit 1
}

check_prerequisites() {
  info "Checking prerequisites..."

  for cmd in docker kind kubectl helm mkcert; do
    if ! command -v "${cmd}" &>/dev/null; then
      error "${cmd} is required but not found. Please install it and try again."
    fi
  done

  # Optional but recommended
  if ! command -v oras &>/dev/null; then
    warn "ORAS tool not found. It's recommended for mirroring Radius recipes."
    warn "To install ORAS: https://oras.land/docs/installation"
  fi

  # Verify mkcert CA is installed
  if ! mkcert -CAROOT &>/dev/null; then
    error "mkcert CA not installed. Please run 'mkcert -install'"
  fi

  info "All prerequisites are installed."
}

# =====================================
# Cleanup Function
# =====================================
cleanup() {
  info "Cleaning up existing resources..."

  # Delete kind cluster if it exists
  if kind get clusters | grep -q "^${CLUSTER_NAME}\$"; then
    info "Deleting existing Kind cluster: ${CLUSTER_NAME}"
    kind delete cluster --name "${CLUSTER_NAME}"
  fi

  # Delete registry container if it exists
  if docker ps -a --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}\$"; then
    info "Deleting existing registry container: ${REGISTRY_NAME}"
    docker rm -f "${REGISTRY_NAME}" >/dev/null 2>&1 || true
  fi

  # Remove the network if it exists
  if docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}\$"; then
    info "Deleting existing Docker network: ${NETWORK_NAME}"
    docker network rm "${NETWORK_NAME}" >/dev/null 2>&1 || true
  fi

  # Remove certificate directory
  if [ -d "${CERTS_DIR}" ]; then
    info "Removing certificates directory: ${CERTS_DIR}"
    rm -rf "${CERTS_DIR}"
  fi

  info "Cleanup completed."
}

# =====================================
# Setup Certificate Authority
# =====================================
setup_certificates() {
  info "Setting up certificates..."

  mkdir -p "${CERTS_DIR}"

  # Generate certificates with mkcert for the registry
  info "Generating TLS certificates for registry"
  mkcert -cert-file "${CERTS_DIR}/tls.crt" -key-file "${CERTS_DIR}/tls.key" \
    "${REGISTRY_NAME}" "localhost" "127.0.0.1"

  # Copy the CA certificate for later use
  cp "$(mkcert -CAROOT)/rootCA.pem" "${CERTS_DIR}/ca.crt"

  info "Certificates generated successfully."
}

# =====================================
# Create and Configure Secure Registry
# =====================================
setup_registry() {
  info "Setting up secure registry..."

  # Create a Docker network that the registry and Kind cluster will use
  info "Creating Docker network: ${NETWORK_NAME}"
  docker network create "${NETWORK_NAME}" || true

  # Start a secure Docker registry with TLS enabled
  info "Starting secure registry: ${REGISTRY_NAME}:${REGISTRY_PORT}"
  docker run -d \
    --name "${REGISTRY_NAME}" \
    --network "${NETWORK_NAME}" \
    --network-alias "${REGISTRY_NAME}" \
    -p "${REGISTRY_PORT}:6060" \
    -v "${CERTS_DIR}:/certs" \
    -e REGISTRY_HTTP_ADDR=0.0.0.0:6060 \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/tls.crt \
    -e REGISTRY_HTTP_TLS_KEY=/certs/tls.key \
    --restart always \
    registry:2

  # Wait for the registry to start
  info "Waiting for registry to initialize..."
  for _ in $(seq 1 10); do
    if curl -s --cacert "${CERTS_DIR}/ca.crt" "https://${LOCALHOST_REGISTRY}/v2/" >/dev/null; then
      info "Registry is ready."
      return 0
    fi
    sleep 2
  done

  error "Registry failed to initialize after 20 seconds."
}

# =====================================
# Download Required Helm Charts
# =====================================
download_charts() {
  info "Downloading required Helm charts..."

  mkdir -p "${CHARTS_DIR}"

  # Download Radius chart
  info "Downloading Radius chart..."
  helm pull oci://ghcr.io/radius-project/helm-chart/radius --version "${RADIUS_VERSION}.0" -d "${CHARTS_DIR}"

  # Download Contour chart
  info "Downloading Contour chart..."
  helm pull oci://registry-1.docker.io/bitnamicharts/contour --version 11.1.1 -d "${CHARTS_DIR}"

  # Dapr (classic repo)
  info "Adding Dapr Helm repo and pulling Dapr chart..."
  helm repo add dapr https://dapr.github.io/helm-charts/ &&
    helm repo update &&
    helm pull dapr/dapr --version 1.14.4 -d "${CHARTS_DIR}"

  info "Helm charts downloaded successfully."
}

# =====================================
# Pull and Push Required Recipes
# =====================================
mirror_recipe_artifacts() {
  info "Mirroring Radius recipes using ORAS..."

  declare -a RECIPE_ARTIFACTS=(
    "ghcr.io/radius-project/recipes/local-dev/mongodatabases:${RADIUS_VERSION}.0"
    "ghcr.io/radius-project/recipes/local-dev/rediscaches:${RADIUS_VERSION}.0"
    "ghcr.io/radius-project/recipes/local-dev/sqldatabases:${RADIUS_VERSION}.0"
    "ghcr.io/radius-project/recipes/local-dev/rabbitmqqueues:${RADIUS_VERSION}.0"
    "ghcr.io/radius-project/recipes/local-dev/pubsubbrokers:${RADIUS_VERSION}.0"
    "ghcr.io/radius-project/recipes/local-dev/secretstores:${RADIUS_VERSION}.0"
    "ghcr.io/radius-project/recipes/local-dev/statestores:${RADIUS_VERSION}.0"
  )

  # Create a temp directory for artifacts
  local temp_dir
  temp_dir=$(mktemp -d)
  trap 'rm -rf "$temp_dir"' EXIT

  local recipe_count=0
  local total_recipes=${#RECIPE_ARTIFACTS[@]}

  # Check ORAS version to determine correct command format
  local oras_version
  oras_version=$(oras version 2>/dev/null | grep -o "Version:[[:space:]]*[0-9.]*" | awk '{print $2}' || echo "unknown")
  info "Detected ORAS version: ${oras_version}"

  for artifact in "${RECIPE_ARTIFACTS[@]}"; do
    info "Processing recipe artifact: ${artifact}"

    # Extract repository name and tag
    local artifact_repo
    artifact_repo=$(echo "${artifact}" | cut -d ':' -f1 | sed -e 's/^[^\/]*\///')
    local tag
    tag=$(echo "${artifact}" | cut -d ':' -f2)

    local local_artifact="${LOCALHOST_REGISTRY}/${artifact_repo}:${tag}"

    # Change to temp directory for artifact files
    cd "$temp_dir"
    rm -rf ./* 2>/dev/null || true

    # Pull the artifact based on ORAS version
    info "Pulling Bicep module from ${artifact}..."

    local pull_success=false

    # Try different pull methods based on version and available flags
    if oras pull "${artifact}" --to-oci-layout ./layout 2>/dev/null; then
      info "Successfully pulled artifact to OCI layout"
      pull_success=true

      # Extract manifest and config files for pushing
      info "Extracting Bicep module contents..."

      # Find and copy all artifact files to current directory
      find ./layout -type f -not -path "*/\.*" -exec cp {} . \; || true

    elif oras copy "${artifact}" --to-oci-layout ./layout 2>/dev/null; then
      info "Successfully copied artifact to OCI layout"
      pull_success=true

      # Extract files
      find ./layout -type f -not -path "*/\.*" -exec cp {} . \; || true

    elif oras pull "${artifact}" 2>/dev/null; then
      # Basic pull might work for some versions
      info "Successfully pulled artifact with basic command"
      pull_success=true
    else
      warn "All pull methods failed for recipe ${artifact}, skipping..."
      continue
    fi

    if $pull_success; then
      # Look for the Bicep module files
      local bicep_files
      bicep_files=$(find . -type f -name "*.json" 2>/dev/null | wc -l)
      info "Found ${bicep_files} files to push"

      if [ "$bicep_files" -gt 0 ]; then
        # Single push method with error logging
        info "Pushing ${artifact} to ${local_artifact}..."

        # Attempt the push with proper annotation
        if oras push --ca-file "${CERTS_DIR}/ca.crt" "${local_artifact}" ./*.json \
          --annotation "org.opencontainers.image.source=${artifact}" 2>push_error.log; then
          recipe_count=$((recipe_count + 1))
          info "Successfully mirrored recipe with CA cert: ${artifact} -> ${local_artifact}"
        else
          warn "Failed to push recipe ${local_artifact} to local registry"
          warn "Error details: $(cat push_error.log)"
          # For debugging, log the push command that failed
          info "Failed push command: oras push \"${local_artifact}\" ./*.json --annotation \"org.opencontainers.image.source=${artifact}\""
        fi
      else
        warn "No Bicep module files found for ${artifact}"
      fi
    fi
  done

  cd - >/dev/null

  info "Successfully mirrored ${recipe_count}/${total_recipes} recipes."

  if [[ "${recipe_count}" -eq 0 ]]; then
    warn "No recipes were mirrored. Radius may have limited functionality."
  fi
}

# =====================================
# Pull and Push Required Images
# =====================================
mirror_images() {
  info "Mirroring container images to local registry..."

  # List of images to mirror
  declare -a IMAGES=(
    # Radius images
    "ghcr.io/radius-project/ucpd:${RADIUS_VERSION}"
    "ghcr.io/radius-project/dynamic-rp:${RADIUS_VERSION}"
    "ghcr.io/radius-project/mirror/postgres:latest"
    "ghcr.io/radius-project/dashboard:${RADIUS_VERSION}"
    "ghcr.io/radius-project/controller:${RADIUS_VERSION}"
    "ghcr.io/radius-project/deployment-engine:${RADIUS_VERSION}"
    "ghcr.io/radius-project/applications-rp:${RADIUS_VERSION}"
    "ghcr.io/radius-project/bicep:${RADIUS_VERSION}"
    # Contour images
    "docker.io/bitnami/contour:1.24.2-debian-11-r1"
    "docker.io/bitnami/envoy:1.24.3-debian-11-r4"
    # Dapr images
    "ghcr.io/dapr/operator:1.14.4"
    "ghcr.io/dapr/placement:1.14.4"
    "ghcr.io/dapr/scheduler:1.14.4"
    "ghcr.io/dapr/sentry:1.14.4"
    "ghcr.io/dapr/injector:1.14.4"
    # Other images
    "docker.io/rancher/mirrored-pause:3.6"
  )

  # Pull and push each image
  local success_count=0
  local total_images=${#IMAGES[@]}

  for image in "${IMAGES[@]}"; do
    info "Processing image: ${image}"

    # Extract repository name and tag properly
    local image_repo
    image_repo=$(echo "${image}" | cut -d ':' -f1 | sed -e 's/^[^\/]*\///')
    local tag
    tag=$(echo "${image}" | cut -d ':' -f2)
    if [[ -z "${tag}" ]]; then
      tag="latest"
    fi

    # Special case for mirror/postgres
    if [[ "${image}" == *"mirror/postgres"* ]]; then
      image_repo="mirror/postgres"
    fi

    # Pull the image
    if ! docker pull "${image}"; then
      warn "Failed to pull ${image}, skipping..."
      continue
    fi

    # Tag for local registry (preserving proper tag structure)
    local local_image="${LOCALHOST_REGISTRY}/${image_repo}:${tag}"
    docker tag "${image}" "${local_image}"

    # Push to local registry
    info "Pushing to local registry: ${local_image}"
    if docker push "${local_image}"; then
      success_count=$((success_count + 1))
    else
      warn "Failed to push ${local_image} to local registry."
    fi
  done

  info "Successfully mirrored ${success_count}/${total_images} regular images."

  if [[ "${success_count}" -eq 0 ]]; then
    error "No images were mirrored. Cannot continue."
  fi
}

# =====================================
# Create Kind Cluster with Registry
# =====================================
create_cluster() {
  info "Creating Kind cluster with secure registry..."

  cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
- role: control-plane
  extraMounts:
    - containerPath: "${CA_CERT_PATH}"
      hostPath: "${CERTS_DIR}/ca.crt"
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"
EOF

  # Get the kind network name (usually kind-${CLUSTER_NAME})
  KIND_NETWORK="kind"
  if docker network ls | grep -q "kind-${CLUSTER_NAME}"; then
    KIND_NETWORK="kind-${CLUSTER_NAME}"
    info "Using Kind network: ${KIND_NETWORK}"
  fi

  # Connect registry container to the kind network
  info "Connecting registry to the Kind network: ${KIND_NETWORK}"
  if docker network connect "${KIND_NETWORK}" "${REGISTRY_NAME}" 2>/dev/null; then
    info "Registry connected to Kind network: ${KIND_NETWORK}"
  else
    info "Registry was already connected to the network or connection failed"
  fi

  # Get the IP address of the registry in the kind network - Fixed command with proper quoting
  REGISTRY_IP=$(docker inspect --format="{{range .NetworkSettings.Networks}}{{if eq .NetworkID \"$(docker network inspect ${KIND_NETWORK} --format='{{.Id}}')\"}}{{.IPAddress}}{{end}}{{end}}" "${REGISTRY_NAME}")

  if [ -z "${REGISTRY_IP}" ]; then
    # Fallback method to get IP if the first approach fails
    REGISTRY_IP=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{if eq .NetworkName \"${KIND_NETWORK}\"}}{{.IPAddress}}{{end}}{{end}}" "${REGISTRY_NAME}")

    if [ -z "${REGISTRY_IP}" ]; then
      # Last resort - just get any IP address
      REGISTRY_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${REGISTRY_NAME}" | head -n1)

      if [ -z "${REGISTRY_IP}" ]; then
        error "Failed to get registry IP address in any network"
      fi
    fi
  fi

  info "Registry IP in ${KIND_NETWORK} network: ${REGISTRY_IP}"

  # Create the directory for the certificates and add the certificate to the system trust store
  LOCALHOST_DIR="/etc/containerd/certs.d/${REGISTRY_SERVER}:${REGISTRY_PORT}"
  REGISTRY_DIR="/etc/containerd/certs.d/${REGISTRY_NAME}:${REGISTRY_PORT}"

  for node in $(kind get nodes --name "${CLUSTER_NAME}"); do
    # Add registry hostname to /etc/hosts in the Kind node
    info "Adding ${REGISTRY_NAME} -> ${REGISTRY_IP} to /etc/hosts in ${node}"
    docker exec "${node}" sh -c "echo '${REGISTRY_IP} ${REGISTRY_NAME}' >> /etc/hosts"
    docker exec "${node}" sh -c "cat /etc/hosts | grep ${REGISTRY_NAME}" || true

    # Configure containerd for localhost:PORT
    docker exec "${node}" mkdir -p "${LOCALHOST_DIR}"
    cat <<EOF | docker exec -i "${node}" sh -c "cat > ${LOCALHOST_DIR}/hosts.toml"
[host."https://${REGISTRY_SERVER}:${REGISTRY_PORT}"]
  capabilities = ["pull", "resolve", "push"]
  ca = "${CA_CERT_PATH}"
EOF

    # Configure containerd for registry.localhost:PORT
    docker exec "${node}" mkdir -p "${REGISTRY_DIR}"
    cat <<EOF | docker exec -i "${node}" sh -c "cat > ${REGISTRY_DIR}/hosts.toml"
[host."https://${REGISTRY_NAME}:${REGISTRY_PORT}"]
  capabilities = ["pull", "resolve", "push"]
  ca = "${CA_CERT_PATH}"
EOF

    # Restart containerd for changes to take effect
    info "Restarting containerd on ${node}"
    docker exec "${node}" sh -c "if command -v systemctl > /dev/null; then systemctl restart containerd; else killall -SIGHUP containerd; fi"
  done

  # Document the local registry
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "${REGISTRY_NAME}:${REGISTRY_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
    secure: true
EOF

  info "Kind cluster created successfully."

  # Wait to make sure everything is stable
  info "Waiting a moment for registry connection to stabilize..."
  sleep 15
}

# =====================================
# Verify Registry Connectivity
# =====================================
verify_registry() {
  info "Verifying connectivity to the registry from the cluster..."

  kubectl run registry-test \
    --image="${REGISTRY_HOST}/mirror/postgres:latest" \
    --restart=Never \
    --command -- echo "Registry connectivity test successful"

  # Wait for the pod to complete
  local retries=0
  local max_retries=30
  while [[ "${retries}" -lt "${max_retries}" ]]; do
    if kubectl get pod registry-test -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Succeeded"; then
      info "Registry connectivity test successful!"
      kubectl delete pod registry-test --wait=false
      return 0
    fi

    if kubectl get pod registry-test -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Failed"; then
      error "Registry connectivity test failed. Check pod logs: kubectl logs registry-test"
    fi

    retries=$((retries + 1))
    sleep 2
  done

  kubectl describe pod registry-test
  error "Registry connectivity test timed out after ${max_retries} tries"
}

# =====================================
# Generate Installation Script
# =====================================
generate_install_script() {
  info "Generating Radius installation script..."

  cat >install-radius-airgapped.sh <<EOF
#!/bin/bash
set -e

echo "Installing Radius in air-gapped environment..."

# Optional: Verify internet is disabled for truly air-gapped testing
# if ping -c 1 google.com &> /dev/null; then
#   echo "Warning: Internet connection detected. For a true air-gapped test, disconnect your network."
#   read -p "Continue anyway? (y/n) " -n 1 -r
#   echo
#   if [[ ! \$REPLY =~ ^[Yy]$ ]]; then
#     exit 1
#   fi
# fi

# Install Radius with local charts and registry
rad install kubernetes \
  --chart ${RADIUS_CHART} \
  --set rp.image=${REGISTRY_HOST}/radius-project/applications-rp,rp.tag=${RADIUS_VERSION} \
  --set dynamicrp.image=${REGISTRY_HOST}/radius-project/dynamic-rp,dynamicrp.tag=${RADIUS_VERSION} \
  --set controller.image=${REGISTRY_HOST}/radius-project/controller,controller.tag=${RADIUS_VERSION} \
  --set ucp.image=${REGISTRY_HOST}/radius-project/ucpd,ucp.tag=${RADIUS_VERSION} \
  --set bicep.image=${REGISTRY_HOST}/radius-project/bicep,bicep.tag=${RADIUS_VERSION} \
  --set de.image=${REGISTRY_HOST}/radius-project/deployment-engine,de.tag=${RADIUS_VERSION} \
  --set dashboard.image=${REGISTRY_HOST}/radius-project/dashboard,dashboard.tag=${RADIUS_VERSION} \
  --set database.image=${REGISTRY_HOST}/mirror/postgres,database.tag=latest 

echo "Radius installation complete."
EOF

  chmod +x install-radius-airgapped.sh

  info "Installation script generated: install-radius-airgapped.sh"
}

# =====================================
# Main Execution
# =====================================
main() {
  info "Starting Air-Gapped Radius Setup"

  # # Step 1: Check prerequisites
  # check_prerequisites

  # # Step 2: Clean up existing resources
  # cleanup

  # # Step 3: Setup certificates
  # setup_certificates

  # # Step 4: Create secure registry
  # setup_registry

  # # Step 5: Download Helm charts
  # download_charts

  # # Step 6: Mirror images to local registry
  # mirror_images

  # Step 7: Mirror recipe artifacts
  mirror_recipe_artifacts

  # # Step 8: Create Kind cluster with registry configuration
  # create_cluster

  # # Step 9: Verify registry connectivity
  # verify_registry

  # # Step 10: Generate installation script
  # generate_install_script

  info "==============================================="
  info "Air-Gapped Radius Environment Setup Complete!"
  info "==============================================="
  info "To install Radius:"
  info "1. Ensure no internet connection if desired for testing"
  info "2. Run: ./install-radius-airgapped.sh"
}

# Execute main function
main "$@"
