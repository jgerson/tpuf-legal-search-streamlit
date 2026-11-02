# Step 2 of setup (scripts/setup.sh runs it). Needs:
#   - VAULT_TOKEN: an HCP Vault admin token (setup.sh takes it from ../hcp; by hand: HCP portal -> cluster -> "New admin token")
#   - TFE_TOKEN:   an HCP Terraform user or team token
#
# It lets HCP Terraform runs log into Vault with workload identity (JWT auth,
# HCP Terraform as the issuer), creates the KV mount, and creates the
# workspace with dynamic credentials switched on. After this, every change
# goes through HCP Terraform and the admin token can be thrown away.

terraform {
  required_version = ">= 1.6"

  # State lives in HCP Terraform (workspace "legal-search-streamlit-bootstrap", local execution: the
  # plan runs where you run it, with your credentials; only the state is
  # stored remotely). scripts/setup.sh creates the workspace and sets
  # TF_CLOUD_ORGANIZATION and TF_WORKSPACE.
  cloud {}
  required_providers {
    vault = { source = "hashicorp/vault", version = "~> 5.0" }
    tfe   = { source = "hashicorp/tfe", version = "~> 0.70" }
  }
}

provider "vault" {
  address   = var.vault_addr
  namespace = var.vault_namespace
}

provider "tfe" { organization = var.tfc_organization }

locals {
  auth_path = "approle-legal-search"
  kv_mount  = "legal-search-st"
  tfc_sub   = "organization:${var.tfc_organization}:project:${var.tfc_project}:workspace:${var.workspace_name}:run_phase:*"
}

resource "vault_mount" "kv" {
  path        = local.kv_mount
  type        = "kv"
  options     = { version = "2" }
  description = "Secrets and tenant config for the Streamlit legal search demo"
}

resource "vault_jwt_auth_backend" "tfc" {
  path               = "jwt-tfc-legal-st"
  description        = "HCP Terraform workload identity for ${var.workspace_name}"
  oidc_discovery_url = "https://${var.tfc_hostname}"
  bound_issuer       = "https://${var.tfc_hostname}"
}

# Exactly what ../terraform manages, nothing more.
resource "vault_policy" "tfc" {
  name   = "tfc-legal-search-st"
  policy = <<-EOT
    path "sys/auth" { capabilities = ["read"] }
    path "sys/auth/${local.auth_path}" { capabilities = ["create", "read", "update", "delete", "sudo"] }
    path "sys/mounts/auth/${local.auth_path}" { capabilities = ["read"] }
    path "sys/mounts/auth/${local.auth_path}/tune" { capabilities = ["read", "update", "sudo"] }
    path "auth/${local.auth_path}/*" { capabilities = ["create", "read", "update", "delete", "list"] }
    path "sys/policies/acl/legal-search-st-app" { capabilities = ["create", "read", "update", "delete"] }

    # The tenant list (not the turbopuffer key: Terraform can't read that)
    path "sys/mounts/${local.kv_mount}" { capabilities = ["read"] }
    path "${local.kv_mount}/data/config" { capabilities = ["create", "read", "update", "delete"] }
    path "${local.kv_mount}/metadata/config" { capabilities = ["read", "update", "delete"] }

    path "auth/token/create" { capabilities = ["update"] }
    path "auth/token/lookup-self" { capabilities = ["read"] }
  EOT
}

resource "vault_jwt_auth_backend_role" "tfc" {
  backend           = vault_jwt_auth_backend.tfc.path
  role_name         = "tfc-legal-search-st"
  role_type         = "jwt"
  bound_audiences   = ["vault.workload.identity"]
  bound_claims_type = "glob"
  bound_claims      = { sub = local.tfc_sub }
  user_claim        = "terraform_full_workspace"
  token_policies    = [vault_policy.tfc.name]
  token_ttl         = 1200
}

data "tfe_project" "p" {
  name = var.tfc_project
}

resource "tfe_workspace" "app" {
  name              = var.workspace_name
  project_id        = data.tfe_project.p.id
  working_directory = "terraform"
  description       = "Legal contract search on Streamlit: turbopuffer + Vault AppRole"
  queue_all_runs    = false

  dynamic "vcs_repo" {
    for_each = var.vcs_repo == "" ? [] : [1]
    content {
      identifier     = var.vcs_repo
      oauth_token_id = var.vcs_oauth_token_id
      branch         = "main"
    }
  }
}

locals {
  vars = {
    env = {
      TFC_VAULT_PROVIDER_AUTH = "true"
      TFC_VAULT_ADDR          = var.vault_addr
      TFC_VAULT_NAMESPACE     = var.vault_namespace
      TFC_VAULT_AUTH_PATH     = vault_jwt_auth_backend.tfc.path
      TFC_VAULT_RUN_ROLE      = vault_jwt_auth_backend_role.tfc.role_name
    }
    terraform = {
      vault_addr      = var.vault_addr
      vault_namespace = var.vault_namespace
      kv_mount        = vault_mount.kv.path
    }
  }
  flat = merge([for cat, kv in local.vars : { for k, v in kv : "${cat}/${k}" => { category = cat, key = k, value = v } }]...)
}

resource "tfe_variable" "v" {
  for_each     = local.flat
  workspace_id = tfe_workspace.app.id
  category     = each.value.category
  key          = each.value.key
  value        = each.value.value
}
