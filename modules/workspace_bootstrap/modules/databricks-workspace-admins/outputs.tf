output "admin_service_principal_ids" {
  description = "Account IDs of the service principals assigned as workspace admin, by application ID"
  value       = { for app_id, sp in data.databricks_service_principal.admin : app_id => sp.id }
}
