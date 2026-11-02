#!/usr/bin/env bash
# One command from nothing to a configured demo. Safe to re-run: every step
# is a Terraform apply, so a second run only fixes what's missing.
#
#   export HCP_CLIENT_ID=...  HCP_CLIENT_SECRET=...  HCP_PROJECT_ID=...   # project-scoped service principal
#   export TFE_TOKEN=...                                                   # HCP Terraform token (set an expiry)
#   export TF_CLOUD_ORGANIZATION=your-hcp-terraform-org
#   ./scripts/setup.sh
#
# Optional: VCS_REPO (e.g. jgerson/tpuf-legal-search-streamlit) connects the
# workspace to GitHub, so a commit that adds a firm starts a run. Add GitHub
# under HCP Terraform Organization settings -> Version Control -> Providers first.
#
# Optional: TURBOPUFFER_API_KEY and DEMO_PASSWORD to write the app secret in
# step 3. Leave them unset if someone else runs this script for you, and
# write the secret yourself (the script tells you how).
#
# Needs: terraform, vault, curl and python3 on your PATH.

set -euo pipefail
cd "$(dirname "$0")/.."

need() { [ -n "${!1:-}" ] || { echo "Set $1 first (see the top of this script)." >&2; exit 1; }; }
for v in HCP_CLIENT_ID HCP_CLIENT_SECRET HCP_PROJECT_ID TFE_TOKEN TF_CLOUD_ORGANIZATION; do need "$v"; done
for c in terraform vault curl python3; do command -v "$c" >/dev/null || { echo "Install $c first." >&2; exit 1; }; done

WORKSPACE=legal-search-streamlit
KV_MOUNT=legal-search-st
export TF_TOKEN_app_terraform_io="$TFE_TOKEN"   # what the terraform CLI reads for HCP Terraform
export TF_IN_AUTOMATION=1
TFC_API="https://app.terraform.io/api/v2"

# State for steps 1 and 2 lives in HCP Terraform, in workspaces that run
# locally (your credentials stay on this machine). Create them if missing.
ensure_local_workspace() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TFE_TOKEN" \
    "$TFC_API/organizations/$TF_CLOUD_ORGANIZATION/workspaces/$1")
  if [ "$code" = "404" ]; then
    curl -sf -o /dev/null -X POST -H "Authorization: Bearer $TFE_TOKEN" -H "Content-Type: application/vnd.api+json" \
      "$TFC_API/organizations/$TF_CLOUD_ORGANIZATION/workspaces" \
      -d "{\"data\":{\"type\":\"workspaces\",\"attributes\":{\"name\":\"$1\",\"execution-mode\":\"local\",\"description\":\"State only, for the turbopuffer legal search demo\"}}}"
    echo "    created HCP Terraform workspace $1 (state only)"
  elif [ "$code" != "200" ]; then
    echo "HCP Terraform returned $code for workspace $1. Check TFE_TOKEN and TF_CLOUD_ORGANIZATION." >&2; exit 1
  fi
}
ensure_local_workspace tpuf-demos-vault-cluster
ensure_local_workspace legal-search-streamlit-bootstrap

echo "==> 1/5 HCP Vault cluster (first run takes about 10 minutes)"
TF_WORKSPACE=tpuf-demos-vault-cluster terraform -chdir=hcp init -input=false -upgrade >/dev/null
TF_WORKSPACE=tpuf-demos-vault-cluster terraform -chdir=hcp apply -input=false -auto-approve
VAULT_ADDR="$(TF_WORKSPACE=tpuf-demos-vault-cluster terraform -chdir=hcp output -raw vault_addr)"; export VAULT_ADDR
VAULT_NAMESPACE="$(TF_WORKSPACE=tpuf-demos-vault-cluster terraform -chdir=hcp output -raw vault_namespace)"; export VAULT_NAMESPACE
VAULT_TOKEN="$(TF_WORKSPACE=tpuf-demos-vault-cluster terraform -chdir=hcp output -raw admin_token)"; export VAULT_TOKEN     # 6-hour admin token, never printed

# The HCP Terraform project for the workspace: TFC_PROJECT if set, otherwise
# the org's only project, otherwise "Default Project".
if [ -z "${TFC_PROJECT:-}" ]; then
  TFC_PROJECT=$(curl -s -m 20 -H "Authorization: Bearer $TFE_TOKEN" \
    "https://app.terraform.io/api/v2/organizations/$TF_CLOUD_ORGANIZATION/projects" |
    python3 -c "import sys,json
try:
  n=[p['attributes']['name'] for p in json.load(sys.stdin)['data']]
  print(n[0] if len(n)==1 else ('Default Project' if 'Default Project' in n or not n else ''))
except Exception: print('Default Project')")
  [ -n "$TFC_PROJECT" ] || { echo "Your org has several HCP Terraform projects. Set TFC_PROJECT to the one to use." >&2; exit 1; }
fi

GH_APP_ID=""
[ -n "${VCS_REPO:-}" ] && GH_APP_ID="$(./scripts/github-app-id.sh)"

echo "==> 2/5 Vault trust for HCP Terraform, KV mount, and the workspace"
TF_WORKSPACE=legal-search-streamlit-bootstrap terraform -chdir=bootstrap init -input=false -upgrade >/dev/null
TF_WORKSPACE=legal-search-streamlit-bootstrap terraform -chdir=bootstrap apply -input=false -auto-approve \
  -var "tfc_organization=$TF_CLOUD_ORGANIZATION" \
  -var "vault_addr=$VAULT_ADDR" \
  -var "vault_namespace=$VAULT_NAMESPACE" \
  -var "tfc_project=$TFC_PROJECT" \
  -var "vcs_repo=${VCS_REPO:-}" \
  -var "vcs_github_app_installation_id=$GH_APP_ID"

echo "==> 3/5 turbopuffer key in Vault"
if [ -n "${TURBOPUFFER_API_KEY:-}" ]; then
  vault kv put -mount="$KV_MOUNT" turbopuffer api_key="$TURBOPUFFER_API_KEY" demo_password="${DEMO_PASSWORD:-}" >/dev/null
  echo "    written"
elif vault kv metadata get -mount="$KV_MOUNT" turbopuffer >/dev/null 2>&1; then
  echo "    already there"
else
  cat <<EOF

    The turbopuffer key isn't in Vault yet. Add it yourself, then re-run this script:

      HCP portal -> Vault -> tpuf-demos -> Launch web UI (sign in with a new admin token)
      -> Secrets engines -> $KV_MOUNT -> Create secret
         path: turbopuffer
         keys: api_key = tpuf_...    demo_password = <pick one>

    or from a terminal:
      export VAULT_ADDR=$VAULT_ADDR VAULT_NAMESPACE=$VAULT_NAMESPACE VAULT_TOKEN=<admin token>
      vault kv put -mount=$KV_MOUNT turbopuffer api_key=tpuf_... demo_password=<pick one>

EOF
  exit 2
fi

echo "==> 4/5 Run the HCP Terraform workspace ($WORKSPACE)"
export TF_WORKSPACE="$WORKSPACE"
terraform -chdir=terraform init -input=false >/dev/null
if [ -n "${VCS_REPO:-}" ]; then
  # Connected to GitHub: the run uses the code on the main branch. Push your
  # changes first if you edited anything under terraform/.
  ./scripts/tfc-run.sh "$WORKSPACE" "setup.sh"
else
  terraform -chdir=terraform apply -input=false -auto-approve
fi

echo "==> 5/5 Streamlit credentials"
ROLE_ID="$(terraform -chdir=terraform output -raw role_id)"
SECRET_ID="$(vault write -f -field=secret_id "auth/approle-legal-search/role/legal-search-st/secret-id")"
mkdir -p .streamlit
umask 077
cat > .streamlit/secrets.toml <<EOF
# Paste into Streamlit Community Cloud: App settings -> Secrets.
# The secret ID is the app's one long-lived credential; it expires in 30 days.
VAULT_ADDR = "$VAULT_ADDR"
VAULT_NAMESPACE = "$VAULT_NAMESPACE"
VAULT_ROLE_ID = "$ROLE_ID"
VAULT_SECRET_ID = "$SECRET_ID"
EOF
unset SECRET_ID

echo
echo "Done. Streamlit secrets are in .streamlit/secrets.toml (gitignored)."
echo "Deploy app.py on Streamlit Community Cloud, paste that file into Secrets, then press 'Sync with Terraform'."
echo "Vault costs about \$0.62/hour: run ./scripts/teardown.sh when you're finished."
