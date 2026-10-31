# Runs in HCP Terraform with Vault dynamic credentials: each run gets a
# short-lived Vault token through workload identity, so the workspace holds
# no Vault token. The TFC_VAULT_* variables are set by ../bootstrap.
#
# What this manages:
#   - the AppRole the Streamlit app logs in with, and its read-only policy
#   - the tenant list (a non-secret config document in Vault the app reads)
# What it deliberately does NOT manage:
#   - the turbopuffer key (written once with `vault kv put`, never in state)
#   - the AppRole secret ID (generated with the CLI, pasted into Streamlit)

terraform {
  required_version = ">= 1.6"
  required_providers {
    vault = { source = "hashicorp/vault", version = "~> 5.0" }
  }
}

provider "vault" {
  address   = var.vault_addr
  namespace = var.vault_namespace
}

resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle-legal-search"
  description = "The Streamlit legal search app"
}

resource "vault_policy" "app" {
  name   = "legal-search-st-app"
  policy = <<-EOT
    # The turbopuffer key + demo password, and the tenant list. Read only.
    path "${var.kv_mount}/data/turbopuffer" { capabilities = ["read"] }
    path "${var.kv_mount}/data/config"      { capabilities = ["read"] }
  EOT
}

resource "vault_approle_auth_backend_role" "app" {
  backend        = vault_auth_backend.approle.path
  role_name      = "legal-search-st"
  token_policies = [vault_policy.app.name]
  token_ttl      = 900 # 15-minute tokens
  token_max_ttl  = 3600
  # The secret ID is the one long-lived credential (secret zero), so it
  # expires: generate a new one monthly and paste it into Streamlit Secrets.
  secret_id_ttl      = var.secret_id_ttl_seconds
  secret_id_num_uses = 0
}

# Tenant list. Not secret, so it's fine in Terraform state. The app reads it
# and the sidebar's "Sync with Terraform" seeds or deletes namespaces to match.
resource "vault_kv_secret_v2" "config" {
  mount = var.kv_mount
  name  = "config"
  data_json = jsonencode({
    firms = { for slug, f in var.firms : slug => f.name }
  })
}
