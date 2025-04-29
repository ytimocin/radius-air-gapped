extension radius

@description('The URL of the server hosting test Terraform modules')
param moduleServer string

@description('Username for Postgres DB')
param username string = 'postgres'

@description('Password for Postgres DB')
@secure()
param password string

resource env 'Applications.Core/environments@2023-10-01-preview' = {
  name: 'env-with-k8s-postgres'
  location: 'global'
  properties: {
    compute: {
      kind: 'kubernetes'
      resourceId: 'self'
      namespace: 'env-with-k8s-postgres'
    }
    recipeConfig: {
      terraform: {
        providers: {
          postgresql: [
            {
              alias: 'pgdb-test'
              sslmode: 'disable'
              secrets: {
                username: {
                  source: pgsecretstore.id
                  key: 'username'
                }
                password: {
                  source: pgsecretstore.id
                  key: 'password'
                }
              }
            }
          ]
        }
      }
      env: {
        PGPORT: '5432'
      }
      envSecrets: {
        PGHOST: {
          source: pgsecretstore.id
          key: 'host'
        }
      }
    }
    recipes: {
      'Applications.Core/extenders': {
        defaultpostgres: {
          templateKind: 'terraform'
          templatePath: '${moduleServer}/postgres.zip'
        }
      }
    }
  }
}

resource app 'Applications.Core/applications@2023-10-01-preview' = {
  name: 'app-with-k8s-postgres'
  location: 'global'
  properties: {
    environment: env.id
    extensions: [
      {
        kind: 'kubernetesNamespace'
        namespace: 'app-with-k8s-postgres'
      }
    ]
  }
}

resource pg 'Applications.Core/extenders@2023-10-01-preview' = {
  name: 'postgres'
  properties: {
    application: app.id
    environment: env.id
    recipe: {
      name: 'defaultpostgres'
      parameters: {
        password: password
      }
    }
  }
}

resource pgsecretstore 'Applications.Core/secretStores@2023-10-01-preview' = {
  name: 'pg-secretstore'
  properties: {
    resource: 'app-with-k8s-postgres/pg-secretstore'
    type: 'generic'
    data: {
      username: {
        value: username
      }
      password: {
        value: password
      }
      host: {
        value: 'postgres.app-with-k8s-postgres.svc.cluster.local'
      }
    }
  }
}
