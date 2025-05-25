terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.70.0"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
  subscription_id = var.azure_subscription_id
}


locals {
  region = "australiaeast" 
  tags   = {}
  suffix = "wordpresskrod"
}

module "resource_group" {
  source = "./modules/resource_group"
  name   = "rgp-mywplab"
  region = local.region

}

module "network" {
  source         = "./modules/network"
  name           = local.suffix
  resource_group = module.resource_group.rg_name
  region         = local.region
  security_rules = [
    {
      name                       = "AllowHttp"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 80
      source_address_prefix      = "*"
      destination_address_prefix = "*"
      
    },
    {
      name                       = "AllowSSH"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = 22
      source_address_prefix      = module.network.my_ip
      destination_address_prefix = "*"
    }
  ]

}



module "storageaccount" {
  source = "./modules/storageaccount"

  resource_group            = module.resource_group.rg_name
  storage_account_name      = "sa${local.suffix}"
  region                    = local.region
  account_tier              = "Standard"
  account_replication_type  = "ZRS"
  account_kind              = "StorageV2"
  enable_https_traffic_only = false 
  is_hns_enabled            = true
  nfsv3_enabled             = true
  enable_lock               = true
  containers = [
    {
      name                  = "wordpress-content"
      container_access_type = "private"
    },
    {
      name                  = "wordpress-content-bkp-weekly"
      container_access_type = "private"
    },
    {
      name                  = "wordpress-content-bkp-monthly"
      container_access_type = "private"
    }
  ]
  network_rules = [
    {
      default_action = "Deny"
      ip_rules       = [module.network.my_ip]
      virtual_network_subnet_ids = [
        module.network.subnet_id
      ]
    }
  ]
  tags = local.tags
}

module "vmss" {
  source = "./modules/vmss"
  depends_on = [
    module.storageaccount
  ]
  vmss_name                 = "vmss-${local.suffix}"
  location                  = local.region
  resource_group_name       = module.resource_group.rg_name
  sku                       = "Standard_B2s"
  zones                     = ["1", "2", "3"]
  upgrade_mode              = "Rolling"
  automatic_instance_repair = true
  ssh_public_key            = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDGgbmwkQNC9cS6p5VadIgWmRRgOgBragVpuCRSiTt2YQ5fiMDeFwxGHsq8BtE9DhuYsGrwxrJSBWr6Y0ZFEBtJ/URU7elmKNpivCVM4ZA8Qze/eBFpFJhIy0eGVHIDCgilvCSb1anYMlTd99ZVgxKAzrjebrUrGzfvNrj6cFORZcqja/pwsau+ar1ytUlN84/8+4bVA73PaD3FaQKYiKCt81hDSQ54JYJ2uEaz7N+uJ7K9t+k8TaqKgqYnxXbds6rk0FMtxXEmu1Hh5HBSZQecR5eaVxvKsRVLKohaQVjVihl5Svqiyp3syiAmK5xSLlnBgNqh6bF1mKfVjfJWUHlpOQpXFZASmryJidbzRHuOngYT55VemwZRURQ8QgMZy+cdtnFDtRkuKO9DOKtVLTRyq8aNgC5j/3Ux3jUTFBYB5t/xIxClDf5Mob2sTF2hWLE+yFuVWw5GpMBRc+8Wno2jzqEdA5sWsZq57r52CTYH5GF6VB3xiKY8dYZTJIglXN/5qd1U9f8boqn1UFZxGMyuhOWR6APAjiAhawWWnjk5bEGuaO2w1YvPYYbjzwbN25DVfietjRjSA5X33d3M0B+Ydyjia62ycMzsjMe7288qmJp2dBZMQDCmMrA8mxbjA6/n7Ci/vQj0NjeIE9f2lkzGhmcfJLevjXMtmn9f3SNTOQ== gnb111@hotmail.com"
  custom_data               = filebase64("${path.root}/script.tpl")
  subnet_id                 = module.network.subnet_id
  network_security_group_id = module.network.nsg_id  
  autoscaling_enabled       = true
  capacity_default          = 3
  capacity_minimum          = 3
  capacity_maximum          = 4

  metrics_trigger = [
    {
      name                   = "Percentage CPU"
      time_grain             = "PT1M"
      statistic              = "Average"
      time_window            = "PT5M"
      time_aggregation       = "Average"
      operator               = "GreaterThan"
      threshold              = 75
      frequency              = "PT1M"
      scale_action_direction = "Increase"
      scale_action_type      = "ChangeCount"
      scale_action_value     = "1"
      scale_action_cooldown  = "PT15M"
    },
    {
      name                   = "Percentage CPU"
      time_grain             = "PT1M"
      statistic              = "Average"
      time_window            = "PT20M"
      time_aggregation       = "Average"
      operator               = "LessThan"
      threshold              = 30
      frequency              = "PT1M"
      scale_action_direction = "Decrease"
      scale_action_type      = "ChangeCount"
      scale_action_value     = "1"
      scale_action_cooldown  = "PT15M"
    }
  ]

  tags = local.tags
}


module "azure-mysql" {
  source                        = "./modules/mysql"
  resource_group                = module.resource_group.rg_name
  region                        = local.region
  resource_mysql_name           = "mysqlf-${local.suffix}"
  database_name                 = "wordpress"
  database_sku                  = "GP_Standard_D2ds_v4"
  database_mysql_version        = "8.0.21"
  size_gb                       = "20"
  auto_grow                     = true
  backup_retention_days         = 20
  geo_redundant_backup          = false
  high_availability_enabled     = true
  database_mysql_admin_username = "adminsiteswordpress"
  database_mysql_admin_password = var.database_mysql_admin_password
  tags                          = local.tags
  vm_nsg_whitelist_ips_ports = [{
    "name"      = "vmss_ip"
    "source_ip" = module.vmss.lb_ip

  }]
  server_parameters = [
    {
      name  = "require_secure_transport"
      value = "OFF" 
    }
  ]
}
