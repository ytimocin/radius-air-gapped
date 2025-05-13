extension radius

// Parameter for the Terraform registry mirror URL
param terraformRegistryMirror string = 'http://localhost:8081/repository/terraform'

@secure()
param username string

@secure()
param password string

// Create a secret store to hold the Terraform registry token
resource tokenSecretStore 'Applications.Core/secretStores@2023-10-01-preview' = {
  name: 'terraform-registry-token-store'
  properties: {
    resource: 'redis-app/terraform-registry-token-store'
    type: 'generic'
    data: {
      username: {
        value: username
      }
      password: {
        value: password
      }
    }
  }
}

// Create an environment with Terraform registry configuration
resource env 'Applications.Core/environments@2023-10-01-preview' = {
  name: 'terraform-registry-example'
  properties: {
    compute: {
      kind: 'kubernetes'
      resourceId: 'self'
      namespace: 'terraform-registry-example'
    }
    recipeConfig: {
      terraform: {
        // Registry configuration with mirror and token authentication
        registry: {
          mirror: terraformRegistryMirror
          // // Provider mappings example (optional)
          // providerMappings: {
          //   'hashicorp/azurerm': 'mycompany/azurerm'
          // }
          // Token-based authentication using the secret store
          authentication: {
            token: {
              source: tokenSecretStore.id
              key: 'registryToken'
            }
          }
        }
      }
    }
    // Add recipe definitions to the environment
    recipes: {
      'Applications.Core/extenders': {
        // Redis recipe definition using Helm chart
        redis: {
          templateKind: 'terraform'
          // Use Helm provider module for Kubernetes
          templatePath: 'registry.terraform.io/squareops/redis/kubernetes'
          templateVersion: '2.1.0'
        }
      }
    }
  }
}

// Create application that will use Redis
resource app 'Applications.Core/applications@2023-10-01-preview' = {
  name: 'redis-app'
  properties: {
    environment: env.id
    extensions: [
      {
        kind: 'kubernetesNamespace'
        namespace: 'redis-app'
      }
    ]
  }
}

// Deploy Redis using Helm chart
resource redisExtender 'Applications.Core/extenders@2023-10-01-preview' = {
  name: 'redis'
  properties: {
    application: app.id
    environment: env.id
    recipe: {
      name: 'redis'
    }
  }
}
