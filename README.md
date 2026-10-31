# Counsel Search on Streamlit: turbopuffer + HCP Vault + HCP Terraform

> **A personal hobby project.** Built to learn and demo how these products fit together. Not affiliated with or endorsed by turbopuffer or HashiCorp, not production code. Every law firm, contract and counterparty is invented.

The same multi-tenant contract search as [tpuf-legal-search-aws](../tpuf-legal-search-aws), built for Streamlit Community Cloud. Each law firm gets its own turbopuffer namespace; lawyers search clauses across that firm's contracts with hybrid search and filters.

The difference is identity. Streamlit Cloud gives the app no cloud identity to prove to Vault, so the app starts from one credential, an AppRole role ID and secret ID. Everything after that is short-lived and comes from Vault.

## How the pieces fit

```
   Streamlit Secrets: VAULT_ROLE_ID + VAULT_SECRET_ID   ← the only credential the app holds ("secret zero")
        │ AppRole login
        ▼
   Vault token (15 min) ──▶ legal-search-st/turbopuffer  {api_key, demo_password}   written by hand
                        └─▶ legal-search-st/config       {firms: {...}}             written by HCP Terraform
        │
        ▼
   turbopuffer  namespace "legal-search-st-<firm>"  (BM25 + native embedding, hybrid via RRF)

   HCP Terraform (Vault dynamic credentials) manages: AppRole + policy + the tenant list
   "Sync with Terraform" in the sidebar seeds or deletes namespaces to match the list
```

| Product | What it does here |
|---|---|
| **turbopuffer** | One namespace per firm, native embedding, hybrid search with RRF, filters on contract type, governing law and year. |
| **HCP Vault** | AppRole auth for the app; KV holds the turbopuffer key, the demo password and the tenant list. The app re-reads them every 2 minutes and on any 401, so key rotation needs no redeploy. |
| **HCP Terraform** | Runs with Vault dynamic credentials (JWT workload identity, no stored token). Manages the AppRole, its policy and the tenant list. |
| **Front end** | Streamlit: firm picker, filters, results, the exact SDK call, and a sidebar showing the Vault token, secret version and a tenant "plan". |

## Setup

You need: an HCP Vault cluster (public endpoint), an HCP Terraform org, a turbopuffer API key, a Streamlit Community Cloud account.

**1. Bootstrap (once, from your laptop)**

```bash
export VAULT_TOKEN=...   # HCP Vault admin token
export TFE_TOKEN=...     # HCP Terraform token
cd bootstrap && terraform init
terraform apply -var tfc_organization=your-org -var vault_addr=https://your-cluster...:8200
```

This creates the KV mount, the JWT auth trust for HCP Terraform (scoped to this one workspace), and the workspace with `TFC_VAULT_PROVIDER_AUTH=true`.

**2. Write the secret by hand** (so it never touches Terraform state)

```bash
export VAULT_ADDR=https://your-cluster...:8200 VAULT_NAMESPACE=admin
vault kv put -mount=legal-search-st turbopuffer api_key=tpuf_... demo_password=choose-one
```

**3. Run the workspace** (push to the connected repo, or `terraform apply` from `terraform/` with a `cloud {}` block). Then get the app's credentials:

```bash
terraform output role_id
vault write -f -field=secret_id auth/approle-legal-search/role/legal-search-st/secret-id
```

**4. Deploy on Streamlit Cloud** with `app.py` as the entry point, and paste `VAULT_ADDR`, `VAULT_NAMESPACE`, `VAULT_ROLE_ID` and `VAULT_SECRET_ID` into App settings → Secrets (see `.streamlit/secrets.toml.example`). Open the app and press **Sync with Terraform** once to seed the firms.

Running locally: `pip install -r requirements.txt`, copy the example to `.streamlit/secrets.toml`, `streamlit run app.py`.

## Demo script (about 10 minutes)

1. **The workspace.** Show HCP Terraform's variables: no Vault token, just `TFC_VAULT_*` settings. Each run logs into Vault with a short-lived workload identity token.
2. **Search.** Pick a firm, ask *"what's our liability cap and what's excluded?"*, switch Hybrid / Vector / BM25, add filters, open *SDK call*.
3. **Tenancy.** Switch firm: same question, different contracts, separate namespace.
4. **Onboard a firm.** Add one to `terraform/terraform.tfvars`, push. After the run, the sidebar shows the new firm as *to seed* and a plan ("seed 1, delete 0"). Press **Sync with Terraform**.
5. **Rotate the key.** Create a second turbopuffer key, `vault kv put` it, press **Re-read key now**. Version and key prefix change in the sidebar; search keeps working. Revoke the old key; the 401 handler covers anything still holding it.
6. **Talk about secret zero.** The secret ID in Streamlit is long-lived (30 days here) and can't be bound to an IP, because Streamlit Cloud's egress isn't stable. On AWS, GCP or Kubernetes the app proves its identity with its platform role instead. That's the AWS version of this demo.

## Trade-offs worth saying out loud

- **Secret zero.** The AppRole secret ID is the one long-lived credential. Mitigations here: it expires after 30 days, it can only read three paths, and every login shows in Vault's audit log. A platform with workload identity removes it.
- **The turbopuffer key is static and org-wide.** turbopuffer keys apply to every namespace in the org and there's no public key-management API, so Vault stores the key rather than minting short-lived ones. Tenant isolation is enforced by the app using the Terraform-managed firm list.
- **Sync is a button, not automatic.** Terraform can't call into Streamlit Cloud, so onboarding is "Terraform changes the desired state, the app reconciles". The AWS version does it inside the Terraform run.
- **One shared demo password**, stored in Vault, so a public app doesn't run up your bill. A real app would use SSO and map users to firms.

## Cleaning up

Remove all firms from `terraform.tfvars`, run, press **Sync with Terraform** (deletes the namespaces), then destroy the workspace and `terraform destroy` in `bootstrap/`.
