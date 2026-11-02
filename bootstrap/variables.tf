variable "tfc_organization" {
  description = "Your HCP Terraform organization name."
  type        = string
}

variable "tfc_project" {
  type    = string
  default = "Default Project"
}

variable "tfc_hostname" {
  type    = string
  default = "app.terraform.io"
}

variable "workspace_name" {
  type    = string
  default = "legal-search-streamlit"
}

variable "vault_addr" {
  description = "HCP Vault public address, including :8200."
  type        = string
}

variable "vault_namespace" {
  type    = string
  default = "admin"
}

variable "vcs_repo" {
  description = "GitHub repo that drives the workspace, e.g. \"jgerson/tpuf-legal-search-streamlit\". Empty means runs are started from the CLI instead."
  type        = string
  default     = ""
}

variable "vcs_github_app_installation_id" {
  description = "Installation ID (ghain-...) of HCP Terraform's GitHub App on your GitHub account. scripts/setup.sh looks it up; leave empty to use an OAuth VCS provider instead."
  type        = string
  default     = ""
}

variable "vcs_oauth_token_id" {
  description = "OAuth token ID (ot-...) of your HCP Terraform GitHub connection. Leave empty to find it automatically."
  type        = string
  default     = ""
}
