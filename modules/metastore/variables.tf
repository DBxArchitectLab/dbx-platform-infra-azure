variable "subscription_id" {
  type = string
}

variable "databricks_account_id" {
  type = string
}

variable "metastore_name" {
  type = string
}

variable "region" {
  type        = string
  description = "Cloud region for the metastore (e.g. eastus)."
}

variable "storage_root" {
  type        = string
  default     = null
  description = "Optional ADLS Gen2 abfss:// URI used as the metastore root. Null for a metastore without metastore-level storage (each catalog then brings its own). Changing it replaces the metastore."
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Allow Terraform to delete the metastore even if it is not empty."
}

variable "owner" {
  type        = string
  default     = null
  description = "Optional Unity Catalog owner for the metastore."
}

variable "delta_sharing_scope" {
  type        = string
  default     = null
  description = "Delta Sharing scope: INTERNAL or INTERNAL_AND_EXTERNAL. Set together with the token lifetime, or neither."
}

variable "delta_sharing_recipient_token_lifetime_in_seconds" {
  type        = number
  default     = null
  description = "Delta Sharing recipient token lifetime. 0 means tokens never expire. Set together with the scope, or neither."

  validation {
    condition     = (var.delta_sharing_recipient_token_lifetime_in_seconds == null) == (var.delta_sharing_scope == null)
    error_message = "Set delta_sharing_scope and delta_sharing_recipient_token_lifetime_in_seconds together, or neither."
  }
}

variable "metastore_data_access_name" {
  type        = string
  default     = "default"
  description = "Name for the default metastore data access configuration when using an access connector."
}

variable "access_connector_resource_id" {
  type        = string
  default     = null
  description = "Azure Databricks Access Connector Azure resource ID for default managed identity data access. Leave null to skip databricks_metastore_data_access."
}
