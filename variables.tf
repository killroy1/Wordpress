variable "database_mysql_admin_password" {
  description = "Database admin password"
  type        = string
  sensitive   = true
}
variable "azure_subscription_id" {
  description = "Azure Subscription ID"
}