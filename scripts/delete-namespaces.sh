#!/usr/bin/env bash
# Delete every turbopuffer namespace the app created (prefix legal-search-st-).
# teardown.sh runs this first, while Vault still holds the turbopuffer key.
#
# The key comes from TURBOPUFFER_API_KEY if set, otherwise from Vault
# (VAULT_ADDR, VAULT_NAMESPACE and VAULT_TOKEN must be set). It's never printed.
#
#   scripts/delete-namespaces.sh            # delete them
#   scripts/delete-namespaces.sh --dry-run  # only list them
#
# Optional: TURBOPUFFER_REGION (default aws-us-east-1), NAMESPACE_PREFIX
# (default legal-search-st, the app's default). Needs curl and python3.

set -euo pipefail
DRY_RUN=""; [ "${1:-}" = "--dry-run" ] && DRY_RUN=1
REGION="${TURBOPUFFER_REGION:-aws-us-east-1}"
PREFIX="${NAMESPACE_PREFIX:-legal-search-st}-"
API="${TURBOPUFFER_BASE_URL:-https://$REGION.turbopuffer.com}"

KEY="${TURBOPUFFER_API_KEY:-}"
if [ -z "$KEY" ]; then
  KEY=$(curl -s -m 20 -H "X-Vault-Token: ${VAULT_TOKEN:?set VAULT_TOKEN or TURBOPUFFER_API_KEY}" \
    -H "X-Vault-Namespace: ${VAULT_NAMESPACE:-}" "${VAULT_ADDR:?set VAULT_ADDR}/v1/legal-search-st/data/turbopuffer" |
    python3 -c "import sys,json
try: print(json.load(sys.stdin)['data']['data']['api_key'])
except Exception: print('')")
fi
[ -n "$KEY" ] || { echo "    no turbopuffer key found in Vault or TURBOPUFFER_API_KEY; skipping namespaces"; exit 0; }

NAMESPACES=$(curl -sf -m 30 -H "Authorization: Bearer $KEY" "$API/v1/namespaces?prefix=$PREFIX&page_size=1000" |
  python3 -c "import sys,json; print(' '.join(n['id'] for n in json.load(sys.stdin).get('namespaces',[])))") ||
  { echo "    couldn't list turbopuffer namespaces in $REGION; skipping" >&2; exit 0; }

if [ -z "$NAMESPACES" ]; then
  echo "    no namespaces starting with $PREFIX"; exit 0
fi
for ns in $NAMESPACES; do
  if [ -n "$DRY_RUN" ]; then
    echo "    would delete $ns"
  else
    curl -sf -m 30 -o /dev/null -X DELETE -H "Authorization: Bearer $KEY" "$API/v2/namespaces/$ns" &&
      echo "    deleted $ns" || echo "    couldn't delete $ns" >&2
  fi
done
