provider "azurerm" {

}

resource "azurerm_resource_group" "sandbox" {
  name     = "sandbox"
  location = "West US"
}

//////////////////////////////////////
/// Virtual Network & Subnet ////////
////////////////////////////////////
resource "azurerm_network_security_group" "sandbox_sg" {
  name                = "public_sg"
  location            = "${azurerm_resource_group.sandbox.location}"
  resource_group_name = "${azurerm_resource_group.sandbox.name}"
}

resource "azurerm_virtual_network" "sandbox_vnet" {
  name                = "virtualNetwork"
  location            = "${azurerm_resource_group.sandbox.location}"
  resource_group_name = "${azurerm_resource_group.sandbox.name}"
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "sandbox_public_subnet" {
  name                 = "public_subnet"
  resource_group_name  = "${azurerm_resource_group.sandbox.name}"
  virtual_network_name = "${azurerm_virtual_network.sandbox_vnet.name}"
  address_prefix       = "10.0.1.0/24"
  network_security_group_id       = "${azurerm_network_security_group.sandbox_sg.id}"
}

resource "azurerm_subnet" "sandbox_private_subnet" {
  name                 = "private_subnet"
  resource_group_name  = "${azurerm_resource_group.sandbox.name}"
  virtual_network_name = "${azurerm_virtual_network.sandbox_vnet.name}"
  address_prefix       = "10.0.2.0/24"
  service_endpoints    = ["Microsoft.Sql"]
}

//////////////////////////////////////
/// PostgreSQL Database /////////////
////////////////////////////////////
/*resource "azurerm_postgresql_server" "sandbox_db_server" {
  name                = "sandbox-db-server-149"
  location            = "${azurerm_resource_group.sandbox.location}"
  resource_group_name = "${azurerm_resource_group.sandbox.name}"

  sku {
    name = "B_Gen4_2"
    capacity = 2
    tier = "Basic"
    family = "Gen4"
  }

  storage_profile {
    storage_mb = 5120
    backup_retention_days = 7
    geo_redundant_backup = "Disabled"
  }

  administrator_login = "psqladminun"
  administrator_login_password = "H@Sh1CoR3!"
  version = "9.5"
  ssl_enforcement = "Enabled"
}

resource "azurerm_postgresql_database" "sandbox_db" {
  name                = "sandbox-db-149"
  resource_group_name = "${azurerm_resource_group.sandbox.name}"
  server_name         = "${azurerm_postgresql_server.sandbox_db_server.name}"
  charset             = "UTF8"
  collation           = "English_United States.1252"
}

resource "azurerm_postgresql_virtual_network_rule" "sandbox_vnet_rule" {
  name                = "postgresql-vnet-rule"
  resource_group_name = "${azurerm_resource_group.sandbox.name}"
  server_name         = "${azurerm_postgresql_server.sandbox_db_server.name}"
  subnet_id           = "${azurerm_subnet.sandbox_private_subnet.id}"
}*/

//////////////////////////////////////
/// Load balancer and VM Scale Set //
////////////////////////////////////
resource "azurerm_public_ip" "sandbox_pip" {
  name                         = "public_ip"
  location                     = "${azurerm_resource_group.sandbox.location}"
  resource_group_name          = "${azurerm_resource_group.sandbox.name}"
  public_ip_address_allocation = "static"
  domain_name_label            = "sandbox-2-dev"
}

resource "azurerm_lb" "sandbox_lb" {
  name                = "sandbox_lb"
  location            = "${azurerm_resource_group.sandbox.location}"
  resource_group_name = "${azurerm_resource_group.sandbox.name}"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = "${azurerm_public_ip.sandbox_pip.id}"
  }
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
  resource_group_name = "${azurerm_resource_group.sandbox.name}"
  loadbalancer_id     = "${azurerm_lb.sandbox_lb.id}"
  name                = "BackEndAddressPool"
}

resource "azurerm_lb_nat_pool" "lbnatpool" {
  count                          = 3
  resource_group_name            = "${azurerm_resource_group.sandbox.name}"
  name                           = "ssh"
  loadbalancer_id                = "${azurerm_lb.sandbox_lb.id}"
  protocol                       = "Tcp"
  frontend_port_start            = 50000
  frontend_port_end              = 50119
  backend_port                   = 22
  frontend_ip_configuration_name = "PublicIPAddress"
}

resource "azurerm_virtual_machine_scale_set" "sandbox_scaleset" {
  name                = "sandboxscaleset-1"
  location            = "${azurerm_resource_group.sandbox.location}"
  resource_group_name = "${azurerm_resource_group.sandbox.name}"
  upgrade_policy_mode = "Manual"

  sku {
    name     = "Standard_F2"
    tier     = "Standard"
    capacity = 2
  }

  storage_profile_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_profile_os_disk {
    name              = ""
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_profile_data_disk {
    lun            = 0
    caching        = "ReadWrite"
    create_option  = "Empty"
    disk_size_gb   = 10
  }

  os_profile {
    computer_name_prefix = "testvm"
    admin_username       = "myadmin"
    admin_password       = "Passwword1234"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/myadmin/.ssh/authorized_keys"
      key_data = "${file("~/.ssh/id_rsa.pub")}"
    }
  }

  network_profile {
    name    = "terraformnetworkprofile"
    primary = true

    ip_configuration {
      name                                   = "TestIPConfiguration"
      subnet_id                              = "${azurerm_subnet.sandbox_public_subnet.id}"
      load_balancer_backend_address_pool_ids = ["${azurerm_lb_backend_address_pool.bpepool.id}"]
      load_balancer_inbound_nat_rules_ids    = ["${element(azurerm_lb_nat_pool.lbnatpool.*.id, count.index)}"]
    }
  }
}
