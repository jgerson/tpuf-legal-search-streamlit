# Step 1 of setup: the HCP Vault cluster itself, as code.
#
# Authenticates with an HCP service principal that only has the Contributor
# role on one HCP project:
#   export HCP_CLIENT_ID=...  HCP_CLIENT_SECRET=...  HCP_PROJECT_ID=...
#
# Creates a HashiCorp Virtual Network (required by every HCP Vault cluster),
# a Development-tier Vault cluster with a public endpoint, and a 6-hour admin
# token that ../bootstrap uses once to configure Vault.
#
# Development tier costs about $0.62 an hour. Run ./scripts/teardown.sh when
# you're done for the day.

terraform {
  required_version = ">= 1.6"

  # State lives in HCP Terraform (workspace "tpuf-demos-vault-cluster", local execution: the
  # plan runs where you run it, with your credentials; only the state is
  # stored remotely). scripts/setup.sh creates the workspace and sets
  # TF_CLOUD_ORGANIZATION and TF_WORKSPACE.
  cloud {}
  required_providers {
    hcp = { source = "hashicorp/hcp", version = "~> 0.115" }
  }
}

provider "hcp" {
  project_id = var.hcp_project_id
}

resource "hcp_hvn" "demo" {
  hvn_id         = "tpuf-demos"
  cloud_provider = "aws"
  region         = var.region
  cidr_block     = "172.25.16.0/20"
}

resource "hcp_vault_cluster" "demo" {
  cluster_id      = "tpuf-demos"
  hvn_id          = hcp_hvn.demo.hvn_id
  tier            = "dev"
  public_endpoint = true # HCP Terraform, Streamlit Cloud and Lambda reach it over the internet
}

# Valid for 6 hours. Used only by ../bootstrap; nothing else holds an admin token.
resource "hcp_vault_cluster_admin_token" "bootstrap" {
  cluster_id = hcp_vault_cluster.demo.cluster_id
}
