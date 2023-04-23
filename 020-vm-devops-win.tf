# Azure Automation account

resource "random_id" "automation_account_01_name" {
  byte_length = 8
}

resource "azurerm_automation_account" "automation_account_01" {
  name                = "auto-${random_id.automation_account_01_name.hex}-01"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Basic"
  tags                = var.tags

  # Bootstrap automation account
  # Note: To view provisioner output, use the Terraform nonsensitive() function when referencing key vault secrets or variables marked 'sensitive'
  provisioner "local-exec" {
    command     = <<EOT
        $params = @{
          TenantId = "${var.aad_tenant_id}"
          SubscriptionId = "${var.subscription_id}"
          ResourceGroupName = "${var.resource_group_name}"
          AutomationAccountName = "${azurerm_automation_account.automation_account_01.name}"
          Domain = "${var.adds_domain_name}"
          VmAddsName = "${var.vm_adds_name}"
          AdminUserName = "${nonsensitive(data.azurerm_key_vault_secret.adminuser.value)}"
          AdminPwd = "${nonsensitive(data.azurerm_key_vault_secret.adminpassword.value)}"
          AppId = "${var.arm_client_id}"
          AppSecret = "${nonsensitive(var.arm_client_secret)}"
        }
        ${path.root}/configure-automation.ps1 @params 
   EOT
    interpreter = ["pwsh", "-Command"]
  }
}

output "automation_account_name" {
  value = azurerm_automation_account.automation_account_01.name
}

locals {
  vm_devops_win_names = formatlist("${var.vm_devops_win_name}%s", range(1, var.vm_devops_win_instances + 1))
}

resource "azurerm_windows_virtual_machine" "vm_devops_win" {
  for_each                 = toset(local.vm_devops_win_names)
  name                     = each.key
  resource_group_name      = var.resource_group_name
  location                 = var.location
  size                     = var.vm_devops_win_size
  admin_username           = data.azurerm_key_vault_secret.adminuser.value
  admin_password           = data.azurerm_key_vault_secret.adminpassword.value
  network_interface_ids    = [azurerm_network_interface.vm_devops_win_nic[each.key].id]
  enable_automatic_updates = true
  patch_mode               = "AutomaticByPlatform"
  tags                     = var.tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.vm_devops_win_storage_account_type
  }

  source_image_reference {
    publisher = var.vm_devops_win_image_publisher
    offer     = var.vm_devops_win_image_offer
    sku       = var.vm_devops_win_image_sku
    version   = var.vm_devops_win_image_version
  }

  # Note: To view provisioner output, use the Terraform nonsensitive() function when referencing key vault secrets or variables marked 'sensitive'
  provisioner "local-exec" {
    command     = <<EOT
        $params = @{
          TenantId                = "${var.aad_tenant_id}"
          SubscriptionId          = "${var.subscription_id}"
          ResourceGroupName       = "${var.resource_group_name}"
          Location                = "${var.location}"
          AutomationAccountName   = "${azurerm_automation_account.automation_account_01.name}"
          VirtualMachineName      = "${each.key}"
          AppId                   = "${var.arm_client_id}"
          AppSecret               = "${nonsensitive(var.arm_client_secret)}"
          DscConfigurationName    = "DevOpsAgentConfig"
        }
        ${path.root}/aadsc-register-node.ps1 @params 
   EOT
    interpreter = ["pwsh", "-Command"]
  }
}

data "azurerm_subnet" "subnet" {
  name = "default"
  virtual_network_name = "AKS-VNET-PROD"
  resource_group_name  = "POC01"
}
# Nic
resource "azurerm_network_interface" "vm_devops_win_nic" {
  for_each            = toset(local.vm_devops_win_names)
  name                = "nic-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipc-${each.key}"
    subnet_id                     = data.azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}
