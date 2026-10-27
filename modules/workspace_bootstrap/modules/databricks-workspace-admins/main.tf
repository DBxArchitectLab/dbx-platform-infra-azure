# Workspace admin for service principals, assigned through the account (the same way the workspace stack makes the
# platform admin group workspace admin). Adds the service principal to the workspace if it isn't there yet.
data "databricks_service_principal" "admin" {
  for_each = toset(var.service_principal_application_ids)

  provider       = databricks.account
  application_id = each.value
}

resource "databricks_mws_permission_assignment" "admin" {
  for_each = data.databricks_service_principal.admin

  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = each.value.id
  permissions  = ["ADMIN"]
}
