Bicep File                   │ Terraform Recipe                     │ PostgreSQL Container
────────────────────────────┐│┌─────────────────────────────────────│┌────────────────────────
                            ││                                     ││
pgsecretstore ──┐           ││                                     ││
                │           ││                                     ││
                ▼           ││                                     ││
recipeConfig.terraform      ││  terraform {                        ││
  .providers.postgresql     ││    required_providers {             ││
    .secrets ───────────────┼┼────► postgresql.pgdb-test           ││
                            ││    }                                ││
                            ││  }                                  ││
                            ││                                     ││
                            ││  resource "postgresql_database"     ││
                            ││    provider = postgresql.pgdb-test  ││
                            ││                 │                   ││
                            ││                 └───────────────────┼┼─► Authentication
                            ││                                     ││