output "workspace" {
  value = "https://${var.tfc_hostname}/app/${var.tfc_organization}/workspaces/${tfe_workspace.app.name}"
}

output "next_step" {
  value = "vault kv put -mount=${vault_mount.kv.path} turbopuffer api_key=tpuf_... demo_password=choose-one"
}
