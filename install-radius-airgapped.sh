#!/bin/bash
set -e

echo "Installing Radius in air-gapped environment..."

# Optional: Verify internet is disabled for truly air-gapped testing
# if ping -c 1 google.com &> /dev/null; then
#   echo "Warning: Internet connection detected. For a true air-gapped test, disconnect your network."
#   read -p "Continue anyway? (y/n) " -n 1 -r
#   echo
#   if [[ ! $REPLY =~ ^[Yy]$ ]]; then
#     exit 1
#   fi
# fi

# Install Radius with local charts and registry
rad install kubernetes   --chart /Users/yetkintimocin/dev/my-radius-samples/air-gapped-env/charts/radius-0.45.0.tgz   --set rp.image=registry.localhost:6060/radius-project/applications-rp,rp.tag=0.45   --set dynamicrp.image=registry.localhost:6060/radius-project/dynamic-rp,dynamicrp.tag=0.45   --set controller.image=registry.localhost:6060/radius-project/controller,controller.tag=0.45   --set ucp.image=registry.localhost:6060/radius-project/ucpd,ucp.tag=0.45   --set bicep.image=registry.localhost:6060/radius-project/bicep,bicep.tag=0.45   --set de.image=registry.localhost:6060/radius-project/deployment-engine,de.tag=0.45   --set dashboard.image=registry.localhost:6060/radius-project/dashboard,dashboard.tag=0.45   --set database.image=registry.localhost:6060/mirror/postgres,database.tag=latest 

echo "Radius installation complete."
