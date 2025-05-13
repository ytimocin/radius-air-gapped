extension radius

// Parameter for the Terraform registry mirror URL
param terraformRegistryMirror string = 'http://localhost:8081/repository/terraform'

// Parameter for the registry token (secured)
@secure()
param registryToken string = '61611e4e-110e-35d3-b102-e4619686ea93'

// Create a secret store to hold the Terraform registry token
resource tokenSecretStore 'Applications.Core/secretStores@2023-10-01-preview' = {
  name: 'terraform-registry-token-store'
  properties: {
    type: 'generic'
    data: {
      registryToken: {
        value: registryToken
      }
    }
  }
}

// Create an environment with Terraform registry configuration
resource env 'Applications.Core/environments@2023-10-01-preview' = {
  name: 'terraform-registry-example'
  location: 'global'
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
        // Redis recipe definition
        redisCache: {
          templateKind: 'terraform'
          // Use module from Terraform Registry
          // For registry mirror: point to a module available in your Nexus registry
          templatePath: 'registry.terraform.io/Azure/redis/azurerm'
          templateVersion: '1.0.0' // Specify the version you want to use
        }
        // Alternative: use a module from a direct URL
        // redisCacheZip: {
        //   templateKind: 'terraform'
        //   templatePath: 'https://example.com/path/to/redis-module.zip'
        // }
      }
    }
  }
}
