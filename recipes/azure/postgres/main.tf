provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "example" {
  name     = "example-resources"
  location = "East US"
}

resource "azurerm_postgresql_flexible_server" "example" {
  name                   = "examplepgserver123"
  resource_group_name    = azurerm_resource_group.example.name
  location               = azurerm_resource_group.example.location
  version                = "13"
  administrator_login    = "pgadmin"
  administrator_password = "StrongPassword123!"

  storage_mb = 32768
  sku_name   = "B1ms"

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  zone                         = "1"

  high_availability {
    mode = "Disabled"
  }

  maintenance_window {
    day_of_week  = 0
    start_hour   = 2
    start_minute = 0
  }

  tags = {
    environment = "dev"
  }
}

resource "azurerm_postgresql_flexible_server_database" "example" {
  name      = "exampledb"
  server_id = azurerm_postgresql_flexible_server.example.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
