#!/usr/bin/env bash
# filepath: /Users/yetkintimocin/dev/msft/radius-project/radius/nexus-repository.sh

# Setup Nexus Repository Manager for Terraform registry mirroring
# For use with Radius Terraform registry mirror configuration

# Fail on errors, undefined variables, and errors in piped commands
set -euo pipefail

# Configuration variables
CONTAINER_NAME="nexus"
NEXUS_PORT=8081
DATA_VOLUME="nexus-data"
IMAGE="sonatype/nexus3:latest"
MAX_WAIT_SECONDS=120

echo "===== Setting up Nexus Repository Manager for Terraform registry mirroring ====="

# Check if the container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Container '$CONTAINER_NAME' already exists. Removing it first..."
  docker rm -f "$CONTAINER_NAME"
fi

# Check if the volume already exists, create it if not
if ! docker volume ls --format '{{.Name}}' | grep -q "^${DATA_VOLUME}$"; then
  echo "Creating volume '$DATA_VOLUME'..."
  docker volume create "$DATA_VOLUME"
fi

# 1. Start Nexus Repository Manager
echo "Starting Nexus Repository container..."
docker run -d \
  --name "$CONTAINER_NAME" \
  -p "$NEXUS_PORT:8081" \
  -v "$DATA_VOLUME:/nexus-data" \
  "$IMAGE"

# 2. Wait for Nexus to start with timeout
echo "Waiting for Nexus to start (this may take several minutes)..."
start_time=$(date +%s)
while true; do
  if curl --output /dev/null --silent --head --fail "http://localhost:$NEXUS_PORT"; then
    echo -e "\nNexus is up and running!"
    break
  fi

  current_time=$(date +%s)
  elapsed=$((current_time - start_time))

  if [ $elapsed -gt $MAX_WAIT_SECONDS ]; then
    echo -e "\nTimeout waiting for Nexus to start. Please check the container logs:"
    echo "docker logs $CONTAINER_NAME"
    exit 1
  fi

  printf '.'
  sleep 5
done

# 3. Get the initial admin password (without -it for non-interactive environments)
echo "Retrieving initial admin password..."
# Wait a bit more to ensure the password file is created
sleep 10
ADMIN_PASSWORD=$(docker exec "$CONTAINER_NAME" cat /nexus-data/admin.password 2>/dev/null || echo "Password not available yet")

if [[ "$ADMIN_PASSWORD" == "Password not available yet" ]]; then
  echo "Admin password not available yet. Please wait a bit longer and run:"
  echo "docker exec $CONTAINER_NAME cat /nexus-data/admin.password"
else
  echo "Initial admin password: $ADMIN_PASSWORD"
fi

# 4. Output configuration instructions
cat <<EOF

===== Nexus Repository Manager Setup Complete =====

Please visit http://localhost:$NEXUS_PORT to complete setup:

1. Sign in with admin/$ADMIN_PASSWORD
2. Follow the setup wizard and change the password
3. Create a 'terraform-proxy' repository of type 'raw proxy'
   - Set remote URL to https://registry.terraform.io
4. Create a 'terraform-releases' repository of type 'raw hosted'
5. Create a 'terraform' repository of type 'raw group' including both repositories
6. Create a user role with nx-repository-view-raw-terraform-* permissions
7. Create a user with that role and generate a token in user settings

To use this mirror with Radius:
- Set registry mirror URL to: http://localhost:$NEXUS_PORT/repository/terraform
- Configure authentication with your generated token

Container management:
- View logs: docker logs $CONTAINER_NAME
- Stop Nexus: docker stop $CONTAINER_NAME
- Start Nexus: docker start $CONTAINER_NAME
- Remove Nexus: docker rm -f $CONTAINER_NAME
EOF

exit 0
