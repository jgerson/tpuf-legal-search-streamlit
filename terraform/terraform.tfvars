# Tenants. Add or remove a firm and push; HCP Terraform updates the list in
# Vault, then "Sync with Terraform" in the app seeds or deletes namespaces.
# All firms are fictional. vault_addr is a workspace variable set by ../bootstrap.

firms = {
  "hartwell-ross" = { name = "Hartwell & Ross LLP" }
  "okafor-lind"   = { name = "Okafor Lind" }
  "bramble-quay"  = { name = "Bramble Quay Partners" }
  "cobalt-mercer" = { name = "Cobalt Mercer LLP" }
}
