#!/usr/bin/env bash
# Start a run in an HCP Terraform workspace through the API, confirm it, and
# wait for it to finish. Used by setup.sh and teardown.sh when the workspace is
# connected to GitHub, because such workspaces don't accept `terraform apply`
# from the command line.
#
#   scripts/tfc-run.sh <workspace> "<message>" [destroy]
#
# Needs TFE_TOKEN, TF_CLOUD_ORGANIZATION, curl and python3.

set -euo pipefail
WS="$1"; MSG="$2"; DESTROY="${3:-}"
API="https://app.terraform.io/api/v2"
AUTH=(-H "Authorization: Bearer $TFE_TOKEN" -H "Content-Type: application/vnd.api+json")
json() { python3 -c "import sys,json; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }

WS_ID=$(curl -sf "${AUTH[@]}" "$API/organizations/$TF_CLOUD_ORGANIZATION/workspaces/$WS" | json "d['data']['id']")
IS_DESTROY=false; [ "$DESTROY" = "destroy" ] && IS_DESTROY=true
BODY="{\"data\":{\"type\":\"runs\",\"attributes\":{\"message\":\"$MSG\",\"is-destroy\":$IS_DESTROY},\"relationships\":{\"workspace\":{\"data\":{\"type\":\"workspaces\",\"id\":\"$WS_ID\"}}}}}"

# A newly connected workspace needs a few seconds to fetch the code from GitHub.
RUN_ID=""
for _ in 1 2 3 4 5 6; do
  RUN_ID=$(curl -s "${AUTH[@]}" -X POST "$API/runs" -d "$BODY" | json "d.get('data',{}).get('id','')") || true
  [ -n "$RUN_ID" ] && break
  sleep 10
done
[ -n "$RUN_ID" ] || { echo "Couldn't start a run in $WS. Check the workspace in HCP Terraform." >&2; exit 1; }
URL="https://app.terraform.io/app/$TF_CLOUD_ORGANIZATION/workspaces/$WS/runs/$RUN_ID"
echo "    run started: $URL"

CONFIRMED=""
while true; do
  read -r STATUS CONFIRMABLE < <(curl -sf "${AUTH[@]}" "$API/runs/$RUN_ID" | json "d['data']['attributes']['status']+' '+str(d['data']['attributes']['actions']['is-confirmable'])")
  case "$STATUS" in
    applied|planned_and_finished) echo "    run finished: $STATUS"; exit 0 ;;
    errored|canceled|discarded|force_canceled) echo "Run ended as $STATUS. Details: $URL" >&2; exit 1 ;;
  esac
  if [ "$CONFIRMABLE" = "True" ] && [ -z "$CONFIRMED" ]; then
    curl -sf "${AUTH[@]}" -X POST "$API/runs/$RUN_ID/actions/apply" -d '{"comment":"Confirmed by scripts/tfc-run.sh"}' >/dev/null
    CONFIRMED=1; echo "    plan confirmed, applying"
  fi
  sleep 5
done
