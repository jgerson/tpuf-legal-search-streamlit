#!/usr/bin/env bash
# Removes everything setup.sh created, in reverse order, so you stop paying
# for the Vault cluster. Run ./scripts/setup.sh again to rebuild.
#
# The firms' turbopuffer namespaces are left in place: they hold a few
# hundred KB and cost almost nothing. To delete them first, remove every firm
# from terraform/terraform.tfvars, run setup.sh, and press "Sync with
# Terraform" in the app.
#
# Needs the same environment variables as setup.sh.

set -euo pipefail
cd "$(dirname "$0")/.."

for v in HCP_CLIENT_ID HCP_CLIENT_SECRET HCP_PROJECT_ID TFE_TOKEN TF_CLOUD_ORGANIZATION; do
  [ -n "${!v:-}" ] || { echo "Set $v first." >&2; exit 1; }
done
export TF_TOKEN_app_terraform_io="$TFE_TOKEN" TF_IN_AUTOMATION=1
for d in hcp bootstrap terraform; do
  ws=tpuf-demos-vault-cluster; [ "$d" = bootstrap ] && ws=legal-search-streamlit-bootstrap; [ "$d" = terraform ] && ws=legal-search-streamlit
  TF_WORKSPACE=$ws terraform -chdir=$d init -input=false >/dev/null
done

VAULT_ADDR="$(TF_WORKSPACE=tpuf-demos-vault-cluster terraform -chdir=hcp output -raw vault_addr)"; export VAULT_ADDR
VAULT_NAMESPACE="$(TF_WORKSPACE=tpuf-demos-vault-cluster terraform -chdir=hcp output -raw vault_namespace)"; export VAULT_NAMESPACE
VAULT_TOKEN="$(TF_WORKSPACE=tpuf-demos-vault-cluster terraform -chdir=hcp output -raw admin_token)"; export VAULT_TOKEN

echo "==> 1/3 Workspace resources (AppRole, policy, firm list)"
if [ -n "${VCS_REPO:-}" ]; then
  ./scripts/tfc-run.sh legal-search-streamlit "teardown.sh" destroy || echo "    skipped (workspace already gone?)"
else
  TF_WORKSPACE=legal-search-streamlit terraform -chdir=terraform destroy -input=false -auto-approve || \
    echo "    skipped (workspace already gone?)"
fi

echo "==> 2/3 Workspace, Vault trust and KV mount (this deletes the turbopuffer key from Vault)"
TF_WORKSPACE=legal-search-streamlit-bootstrap terraform -chdir=bootstrap destroy -input=false -auto-approve \
  -var "tfc_organization=$TF_CLOUD_ORGANIZATION" \
  -var "vault_addr=$VAULT_ADDR" \
  -var "vault_namespace=$VAULT_NAMESPACE" \
  -var "vcs_repo=${VCS_REPO:-}"

echo "==> 3/3 HCP Vault cluster and network"
TF_WORKSPACE=tpuf-demos-vault-cluster terraform -chdir=hcp destroy -input=false -auto-approve
rm -f .streamlit/secrets.toml
echo "Done. Nothing in HCP is billing now."
