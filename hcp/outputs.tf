output "vault_addr" {
  description = "Public address of the cluster. Used as VAULT_ADDR everywhere."
  value       = hcp_vault_cluster.demo.vault_public_endpoint_url
}

output "vault_namespace" {
  value = hcp_vault_cluster.demo.namespace
}

output "admin_token" {
  description = "6-hour admin token for ../bootstrap. Read it with: terraform output -raw admin_token"
  value       = hcp_vault_cluster_admin_token.bootstrap.token
  sensitive   = true
}
