variable "workspace_id" {
  description = "Workspace to assign the admins to"
  type        = number
}

variable "service_principal_application_ids" {
  description = "Application IDs of the service principals to make workspace admin"
  type        = list(string)
  default     = []
}
