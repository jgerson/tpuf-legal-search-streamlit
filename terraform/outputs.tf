output "role_id" {
  description = "Paste into Streamlit Secrets as VAULT_ROLE_ID. Not a secret on its own."
  value       = vault_approle_auth_backend_role.app.role_id
}

output "new_secret_id_command" {
  description = "Run this yourself; the secret ID never goes through Terraform."
  value       = "vault write -f -field=secret_id auth/${vault_auth_backend.approle.path}/role/${vault_approle_auth_backend_role.app.role_name}/secret-id"
}

output "tenants" {
  value = keys(var.firms)
}
