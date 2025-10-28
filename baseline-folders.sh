#!/usr/bin/env bash
# baseline-folders.sh
# Create folder structure for a given subscription:
#   baselines/YYYY-MM-DD/subs/<SUB_ID>/rgs/<RG_NAME>/resources/
#
# Optional: INCLUDE_RESOURCES=true to also create:
#   .../resources/<PROVIDER>/<TYPE>/<NAME>/
#
# Deps: Azure CLI (az), jq
set -euo pipefail

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI 'az' not found in PATH" >&2; exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "'jq' not found in PATH" >&2; exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <SUBSCRIPTION_ID> [OUTPUT_DIR]"
  echo "  SUBSCRIPTION_ID: the subscription (GUID) to baseline"
  echo "  OUTPUT_DIR     : optional; default baselines/\$(date +%F)"
  echo "Env:"
  echo "  INCLUDE_RESOURCES=true  # also create per-resource folders"
  exit 2
fi

SUB_ID="$1"
BASE_DIR="${2:-baselines/$(date +%F)}"
INCLUDE_RESOURCES="${INCLUDE_RESOURCES:-false}"

# Sanitize names for filesystem (keeps slashes used for nesting)
sanitize_path() {
  # Allow A–Z a–z 0–9 . _ / - ; collapse other chars to '-'
  sed -E 's#[^A-Za-z0-9._/\-]+#-#g' | sed -E 's#-+#-#g' | sed -E 's#/$##'
}

# Ensure we can read the subscription
echo ">> Using subscription: $SUB_ID"
az account show --subscription "$SUB_ID" >/dev/null

# Base folders
SUB_ROOT="$BASE_DIR/subs/$SUB_ID"
mkdir -p "$SUB_ROOT"
az role assignment list --assignee "$SUB_ROOT" --all -o json \
| jq -c '.[] | {scope, roleDefinitionName, roleDefinitionId, principalId, principalType}'

# Enumerate resource groups
echo ">> Listing resource groups..."
mapfile -t RGS < <(az group list --subscription "$SUB_ID" --query '[].name' -o tsv)

echo ">> Creating folder tree..."
for RG in "${RGS[@]}"; do
  RG_SAFE="$(printf '%s' "$RG" | sanitize_path)"
  RG_DIR="$SUB_ROOT/rgs/$RG_SAFE"
  RES_DIR="$RG_DIR/resources"

  mkdir -p "$RES_DIR"
  touch "$RG_DIR/.gitkeep" "$RES_DIR/.gitkeep"

  if [[ "$INCLUDE_RESOURCES" == "true" ]]; then
    echo "   - $RG: creating resource folders"
    # Pull resource id/type/name and create nested folders
    az resource list --subscription "$SUB_ID" --resource-group "$RG" -o json \
    | jq -r '.[] | [.type, .name] | @tsv' \
    | while IFS=$'\t' read -r RES_TYPE RES_NAME; do
        # RES_TYPE looks like: Microsoft.Web/sites
        PROV="$(printf '%s' "$RES_TYPE" | cut -d'/' -f1 | sanitize_path)"
        TYPE="$(printf '%s' "$RES_TYPE" | cut -d'/' -f2- | sanitize_path)"
        NAME="$(printf '%s' "$RES_NAME" | sanitize_path)"
        RES_PATH="$RES_DIR/$PROV/$TYPE/$NAME"
        mkdir -p "$RES_PATH"
        touch "$RES_PATH/.gitkeep"
      done
  fi
done

# Manifest stub (optional breadcrumb)
MANIFEST="$BASE_DIR/manifest.txt"
{
  echo "baselinePath=$BASE_DIR"
  echo "subscription=$SUB_ID"
  echo "capturedAt=$(date -Is)"
  echo "rgCount=${#RGS[@]}"
  echo "includeResources=$INCLUDE_RESOURCES"
} > "$MANIFEST"

echo ">> Done. Folder structure at: $BASE_DIR"
