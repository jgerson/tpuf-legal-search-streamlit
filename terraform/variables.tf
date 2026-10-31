variable "vault_addr" {
  description = "HCP Vault public address, including :8200."
  type        = string
}

variable "vault_namespace" {
  type    = string
  default = "admin"
}

variable "kv_mount" {
  description = "KV v2 mount created by ../bootstrap."
  type        = string
  default     = "legal-search-st"
}

variable "secret_id_ttl_seconds" {
  description = "How long an AppRole secret ID stays valid. 30 days by default."
  type        = number
  default     = 2592000
}

variable "firms" {
  description = "Tenants. Key = slug (used in the namespace name), name = what the UI shows."
  type        = map(object({ name = string }))

  validation {
    condition     = alltrue([for k in keys(var.firms) : can(regex("^[a-z0-9-]{3,40}$", k))])
    error_message = "Firm slugs must be 3-40 characters of lowercase letters, digits and dashes."
  }
}
