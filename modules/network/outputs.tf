output "subnet_id" {
  value = azurerm_subnet.subnet.id
}

output "nsg_id" {
    value = azurerm_network_security_group.nsg[0].id 
}

output "my_ip" {
    value = "${chomp(data.http.myip.body)}"
}