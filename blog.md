# Installing Radius in an Air-Gapped Environment

## What is Radius?

[Radius](https://radapp.io/) is an open-source application platform designed to simplify cloud-native development. It provides a unified experience for deploying and managing applications across different environments and infrastructure. Radius empowers developers to define their entire application environment—including compute resources, infrastructure dependencies, and application configurations—using a simple, declarative approach.

Key features of Radius include:

- **Application-centric**: Radius focuses on the application rather than underlying infrastructure
- **Multi-cloud compatibility**: Deploy applications across different cloud providers or on-premises
- **Infrastructure as Code**: Define and provision resources using familiar IaC tools
- **GitOps-friendly**: Align with modern CI/CD practices
- **Kubernetes-native**: Extends Kubernetes with application-level abstractions

## The Challenge of Air-Gapped Environments

Air-gapped environments are isolated networks that don't have direct internet access. These environments are common in:

- Highly regulated industries like financial services
- Government and defense sectors
- Critical infrastructure organizations
- Environments with strict security requirements

Installing software in these environments presents unique challenges since you can't directly download containers, charts, or other dependencies from the internet. Instead, you need to prepare all required artifacts in advance and transfer them to the isolated environment.

## Our Approach to Air-Gapped Radius Installation

To install Radius in an air-gapped environment, we'll follow these high-level steps:

1. Download all necessary components on a connected machine
2. Set up a local container registry
3. Mirror required container images to the local registry
4. Create a Kubernetes cluster configured to use the local registry
5. Install Radius using local resources

Let's walk through a script that automates this process.

## Understanding the Air-Gapped Setup Script

The provided run.sh script automates the entire setup process. Let's break down the key sections:

### Configuration and Prerequisites

```bash
CLUSTER_NAME="air-gapped-cluster"
REGISTRY_NAME="registry.localhost"
REGISTRY_PORT="6060"
RADIUS_VERSION="0.45"
```

The script begins by defining configuration variables and checking for required tools:

- Docker, Kind, kubectl, Helm, and mkcert
- Creates a dedicated local registry and Kubernetes cluster

### Setting Up Certificates for Secure Communication

```bash
setup_certificates() {
  info "Setting up certificates..."
  mkdir -p "${CERTS_DIR}"
  mkcert -cert-file "${CERTS_DIR}/tls.crt" -key-file "${CERTS_DIR}/tls.key" \
    "${REGISTRY_NAME}" "localhost" "127.0.0.1"
  cp "$(mkcert -CAROOT)/rootCA.pem" "${CERTS_DIR}/ca.crt"
}
```

The script uses `mkcert` to generate TLS certificates, ensuring secure communication with the local registry.

### Creating a Local Container Registry

```bash
setup_registry() {
  info "Setting up secure registry..."
  docker network create "${NETWORK_NAME}" || true

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
}
```

This section creates a TLS-secured Docker registry running locally that will store all necessary container images.

### Downloading Required Helm Charts

```bash
download_charts() {
  info "Downloading required Helm charts..."
  helm pull oci://ghcr.io/radius-project/helm-chart/radius --version "${RADIUS_VERSION}.0" -d "${CHARTS_DIR}"
  helm pull oci://registry-1.docker.io/bitnamicharts/contour --version 11.1.1 -d "${CHARTS_DIR}"
  # Additional charts...
}
```

The script downloads all necessary Helm charts, including Radius itself, Contour (for ingress), and Dapr.

### Mirroring Container Images

```bash
mirror_images() {
  info "Mirroring container images to local registry..."

  # List of images to mirror
  declare -a IMAGES=(
    # Radius images
    "ghcr.io/radius-project/ucpd:${RADIUS_VERSION}"
    "ghcr.io/radius-project/dynamic-rp:${RADIUS_VERSION}"
    # ...and many more
  )

  # Pull and push each image
  for image in "${IMAGES[@]}"; do
    # Pull, tag and push to local registry
    # ...
  done
}
```

This critical function downloads all required container images from public registries and pushes them to our local secure registry, making them available in the air-gapped environment.

### Creating a Kind Cluster with Registry Access

```bash
create_cluster() {
  info "Creating Kind cluster with secure registry..."

  # Create Kind cluster with CA cert mounted
  # Configure containerd to trust our registry
  # Connect registry network to Kind network
  # Add registry hostname to /etc/hosts in Kind nodes
}
```

This section creates a Kubernetes cluster using Kind, configures it to trust our local registry certificates, and ensures connectivity between the cluster and registry.

### Generating the Installation Script

```bash
generate_install_script() {
  info "Generating Radius installation script..."

  cat >install-radius-airgapped.sh <<EOF
#!/bin/bash
set -e

echo "Installing Radius in air-gapped environment..."

# Install Radius with local charts and registry
rad install kubernetes \
  --chart ${RADIUS_CHART} \
  --contour-chart ${CONTOUR_CHART} \
  --set rp.image=${REGISTRY_HOST}/radius-project/applications-rp,rp.tag=${RADIUS_VERSION} \
  # ...additional configuration
EOF

  chmod +x install-radius-airgapped.sh
}
```

Finally, the script generates an installation script that uses the `rad` CLI to install Radius using our local charts and container images.

## Running the Installation

Once the setup script completes, you can install Radius by running the generated script:

```bash
./install-radius-airgapped.sh
```

This script will:

1. Verify you're in an air-gapped environment (optional)
2. Install Radius using local resources
3. Configure it to use the local registry for all images

## Conclusion

With this approach, you can successfully deploy Radius in air-gapped environments where internet connectivity is restricted or unavailable. The automated script handles all the complexity of:

- Creating a secure local registry
- Downloading and mirroring all required container images
- Setting up proper networking and trust between components
- Configuring Kubernetes to work with local resources

This solution enables organizations with strict security requirements to still benefit from Radius's application platform capabilities without compromising their network isolation policies.

For more information about Radius, visit [radapp.io](https://radapp.io/).
