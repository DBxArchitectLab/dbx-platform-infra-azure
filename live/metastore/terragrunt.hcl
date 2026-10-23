include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env    = read_terragrunt_config("${get_terragrunt_dir()}/env.hcl")
  config = local.env.locals.config

  # Set metastore.import_id in config.yaml to adopt an existing metastore instead of creating one.
  import_id = try(local.config.metastore.import_id, null)
}

terraform {
  source = "../../modules/metastore"
}

# Adopts an existing metastore (for example the one Databricks creates automatically with the first workspace in a
# region) into this stack's state. Terraform imports it on the next plan/apply; once it is in state, the import block
# is a no-op. Not generated when import_id is unset.
generate "import" {
  path      = "import.generated.tf"
  if_exists = "overwrite"
  disable   = local.import_id == null
  contents  = <<EOF
import {
  to       = databricks_metastore.this
  id       = "${coalesce(local.import_id, "unset")}"
  provider = databricks.account
}
EOF
}

inputs = merge(
  local.env.inputs,
  {
    metastore_name               = local.config.metastore.name
    region                       = local.config.metastore.region
    storage_root                 = try(local.config.metastore.storage_root, null)
    force_destroy                = try(local.config.metastore.force_destroy, false)
    owner                        = try(local.config.metastore.owner, null)

    delta_sharing_recipient_token_lifetime_in_seconds = try(
      local.config.metastore.delta_sharing_recipient_token_lifetime_in_seconds, null)

    metastore_data_access_name   = try(local.config.metastore.data_access_name, "default")
    access_connector_resource_id = try(local.config.metastore.access_connector_resource_id, null)
  }
)
