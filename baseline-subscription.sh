#!/usr/bin/env bash
# save as: baseline-sub-assignees.sh
# Usage: ./baseline-sub-assignees.sh <SUBSCRIPTION_ID> [OUTPUT_DIR]
# Example: ./baseline-sub-assignees.sh 00000000-1111-2222-3333-444444444444 baselines/2025-10-28
#
# Result: baselines/<date>/subs/<SUB_ID>/<principalId>.json
# Each <principalId>.json is an array of that principal's direct role assignments at the subscription scope.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <SUBSCRIPTION_ID> [OUTPUT_DIR]" >&2
  exit 2
fi

SUB_ID="$1"
BASE_DIR="${2:-baselines/$(date +%F)}"
SUB_ROOT="$BASE_DIR/subs/$SUB_ID"

# Optional: set ONLY_SP=true to keep only ServicePrincipal (includes managed identities)
ONLY_SP="${ONLY_SP:-false}"

command -v az >/dev/null || { echo "az not found in PATH" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found in PATH" >&2; exit 1; }

echo ">> Verifying subscription access..."
az account show --subscription "$SUB_ID" >/dev/null

mkdir -p "$SUB_ROOT"

echo ">> Fetching direct role assignments at subscription scope..."
ASSIGNMENTS_JSON="$(az role assignment list \
  --scope "/subscriptions/$SUB_ID" \
  -o json)"

# Optionally filter to service principals only
if [[ "$ONLY_SP" == "true" ]]; then
  ASSIGNMENTS_JSON="$(echo "$ASSIGNMENTS_JSON" | jq '[.[] | select(.principalType=="ServicePrincipal")]')"
fi

echo ">> Writing one JSON file per assignee (principalId)..."
# Unique principal IDs
mapfile -t PIDS < <(echo "$ASSIGNMENTS_JSON" | jq -r '.[].principalId' | sort -u)

for PID in "${PIDS[@]}"; do
  # Build a stable, minimal JSON array of this principal's assignments at the subscription scope
  echo "$ASSIGNMENTS_JSON" \
  | jq -S --arg pid "$PID" '
      [ .[]
        | select(.principalId == $pid)
        | {scope, roleDefinitionId, roleDefinitionName, principalId, principalType}
      ]
      | sort_by(.scope, .roleDefinitionId, .principalId)
    ' \
  > "$SUB_ROOT/$PID.json"
done

# Optional breadcrumb
cat > "$SUB_ROOT/manifest.json" <<EOF
{
  "subscriptionId": "$SUB_ID",
  "capturedAt": "$(date -Is)",
  "principalCount": ${#PIDS[@]},
  "onlyServicePrincipals": $([[ "$ONLY_SP" == "true" ]] && echo true || echo false)
}
EOF

echo ">> Done. Files in: $SUB_ROOT"
