extension radius

@description('The URL of the server hosting test Terraform modules')
param moduleServer string = 'http://localhost:8999'

@description('Username for Postgres DB')
param username string = 'pgadmin'

@description('Password for Postgres DB')
@secure()
param password string

@description('Resource Group location')
param location string = 'East US'

@description('Environment for resources tagging')
param environment string = 'dev'

resource pgsecretstore 'Applications.Core/secretStores@2023-10-01-preview' = {
  name: 'azure-pg-secretstore'
  properties: {
    resource: 'app-with-azure-postgres-2/azure-pg-secretstore'
    type: 'generic'
    data: {
      administratorLogin: {
        value: username
      }
      administratorPassword: {
        value: password
      }
      location: {
        value: location
      }
      environment: {
        value: environment
      }
    }
  }
}

resource env 'Applications.Core/environments@2023-10-01-preview' = {
  name: 'env-with-azure-postgres'
  location: 'global'
  properties: {
    compute: {
      kind: 'kubernetes'
      resourceId: 'self'
      namespace: 'env-with-azure-postgres'
    }
    recipeConfig: {
      terraform: {
        providers: {
          azurerm: [
            {
              features: {}
              storage_use_azuread: true
              skip_provider_registration: false
            }
          ]
        }
      }
      env: {
        PGPORT: '5432'
        TF_LOG: 'INFO'
      }
      envSecrets: {
        POSTGRES_USERNAME: {
          source: pgsecretstore.id
          key: 'administratorLogin'
        }
        POSTGRES_PASSWORD: {
          source: pgsecretstore.id
          key: 'administratorPassword'
        }
        POSTGRES_LOCATION: {
          source: pgsecretstore.id
          key: 'location'
        }
        POSTGRES_ENV: {
          source: pgsecretstore.id
          key: 'environment'
        }
      }
    }
    recipes: {
      'Applications.Core/extenders': {
        azurepostgres: {
          templateKind: 'terraform'
          templatePath: '${moduleServer}/azure-postgres.zip'
        }
      }
    }
  }
}

resource app 'Applications.Core/applications@2023-10-01-preview' = {
  name: 'app-with-azure-postgres-2'
  location: 'global'
  properties: {
    environment: env.id
    extensions: [
      {
        kind: 'kubernetesNamespace'
        namespace: 'app-with-azure-postgres-2'
      }
    ]
  }
}

resource pg 'Applications.Core/extenders@2023-10-01-preview' = {
  name: 'azure-postgres'
  properties: {
    application: app.id
    environment: env.id
    recipe: {
      name: 'azurepostgres'
      parameters: {
        serverName: 'pg-${uniqueString(resourceGroup().id)}'
        administratorLogin: username
        administratorPassword: password
        skuName: 'B_Standard_B1ms'
        storageMB: 32768
        backupRetentionDays: 7
        geoRedundantBackup: false
        version: '13'
        tags: {
          environment: environment
          applicationName: 'app-with-azure-postgres-2'
          deployedBy: 'Radius'
          managedBy: 'DevOps'
        }
      }
    }
  }
}
