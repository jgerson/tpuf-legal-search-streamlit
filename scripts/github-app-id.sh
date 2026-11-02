#!/usr/bin/env bash
# Print the installation ID (ghain-...) of HCP Terraform's GitHub App for the
# owner of $VCS_REPO, or nothing if the GitHub App isn't set up (setup.sh then
# falls back to an OAuth VCS provider). Checks, in order:
#   1. VCS_GITHUB_APP_INSTALLATION_ID, if you set it
#   2. the workspace's current GitHub connection, if you connected it in the UI
#   3. your GitHub App installations, matched by account name
# Needs TFE_TOKEN, TF_CLOUD_ORGANIZATION, VCS_REPO, curl and python3.

set -uo pipefail
WS="${1:-legal-search-streamlit}"
API="https://app.terraform.io/api/v2"
[ -n "${VCS_GITHUB_APP_INSTALLATION_ID:-}" ] && { echo "$VCS_GITHUB_APP_INSTALLATION_ID"; exit 0; }

from_ws=$(curl -s -m 20 -H "Authorization: Bearer $TFE_TOKEN" "$API/organizations/$TF_CLOUD_ORGANIZATION/workspaces/$WS" |
  python3 -c "import sys,json
try: print((json.load(sys.stdin)['data']['attributes'].get('vcs-repo') or {}).get('github-app-installation-id') or '')
except Exception: print('')")
[ -n "$from_ws" ] && { echo "$from_ws"; exit 0; }

owner="${VCS_REPO%%/*}"
curl -s -m 20 -H "Authorization: Bearer $TFE_TOKEN" "$API/github-app/installations" |
  python3 -c "import sys,json
try:
  d=json.load(sys.stdin).get('data',[])
  print(next((i['id'] for i in d if (i['attributes'].get('name') or '').lower()==sys.argv[1].lower()), ''))
except Exception: print('')" "$owner"
