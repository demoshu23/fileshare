#!/bin/bash
set -euo pipefail

# ==============================
# INPUTS (from pipeline variables)
# ==============================
ENVIRONMENT=${ENVIRONMENT:?}
RESOURCE_GROUP=${RESOURCE_GROUP:?}
VAULT_NAME=${VAULT_NAME:?}
STORAGE_ACCOUNTS=${STORAGE_ACCOUNTS:?}  # space-separated list

MAX_PARALLEL=${MAX_PARALLEL:-2}
POLL_INTERVAL=${POLL_INTERVAL:-30}

# Gmail SMTP/email configuration (pipeline secrets)
SMTP_SERVER="smtp.gmail.com"
SMTP_PORT=587
SMTP_USER=${SMTP_USER:?}         # Gmail address
SMTP_PASS=${SMTP_PASS:?}         # Gmail App Password
EMAIL_TO=${EMAIL_TO:?}           # comma-separated recipients
EMAIL_FROM=${EMAIL_FROM:-$SMTP_USER}

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$ENVIRONMENT] $1"; }

retry() {
  local n=0 max=3 delay=10
  until "$@"; do
    ((n++))
    if (( n >= max )); then
      log "Command failed after $n attempts: $*"
      return 1
    fi
    log "Retry $n/$max..."
    sleep $delay
  done
}

# ==============================
# STEP 1: Fetch file shares per storage account
# ==============================
declare -A SHARE_ACCOUNT_MAP
declare -A RESTORE_STATUS

log "Fetching Azure File Shares for all storage accounts..."

for SA in $STORAGE_ACCOUNTS; do
  ITEMS=$(az backup item list \
    --resource-group "$RESOURCE_GROUP" \
    --vault-name "$VAULT_NAME" \
    --backup-management-type AzureStorage \
    --workload-type AzureFileShare \
    --query "[].name" -o tsv)

  if [ -n "$ITEMS" ]; then
    for SHARE in $ITEMS; do
      SHARE_ACCOUNT_MAP["$SHARE"]="$SA"
    done
  fi
done

if [ ${#SHARE_ACCOUNT_MAP[@]} -eq 0 ]; then
  log "No file shares found for any storage account."
  exit 0
fi

# ==============================
# STEP 2: Define processing function
# ==============================
process_share() {
  local ITEM=$1
  local SA=$2

  log "Processing $ITEM (Storage Account: $SA)"
  CONTAINER_NAME="storagecontainer;storage;$RESOURCE_GROUP;$SA"

  # Get latest recovery point
  RP=$(az backup recoverypoint list \
    --resource-group "$RESOURCE_GROUP" \
    --vault-name "$VAULT_NAME" \
    --container-name "$CONTAINER_NAME" \
    --item-name "$ITEM" \
    --query "sort_by([], &properties.recoveryPointTime)[-1].name" -o tsv)

  if [ -z "$RP" ]; then
    log "No recovery point found for $ITEM"
    RESTORE_STATUS["$ITEM"]="NoRecoveryPoint"
    return 0
  fi

  log "Latest recovery point: $RP"

  # Trigger restore
  JOB_ID=$(retry az backup restore restore-azurefileshare \
    --resource-group "$RESOURCE_GROUP" \
    --vault-name "$VAULT_NAME" \
    --container-name "$CONTAINER_NAME" \
    --item-name "$ITEM" \
    --recovery-point-id "$RP" \
    --restore-mode OriginalLocation \
    --resolve-conflict Overwrite \
    --query "name" -o tsv)

  log "Restore job ID: $JOB_ID"

  STATUS="InProgress"
  while [[ "$STATUS" == "InProgress" || "$STATUS" == "Queued" ]]; do
    sleep "$POLL_INTERVAL"
    STATUS=$(az backup job show \
      --resource-group "$RESOURCE_GROUP" \
      --vault-name "$VAULT_NAME" \
      --name "$JOB_ID" \
      --query "status" -o tsv)
    log "$ITEM → $STATUS"
  done

  RESTORE_STATUS["$ITEM"]=$STATUS

  if [[ "$STATUS" == "Completed" ]]; then
    log "SUCCESS: $ITEM"
  else
    log "FAILED: $ITEM"
  fi
}

export -f process_share
export RESOURCE_GROUP VAULT_NAME POLL_INTERVAL log retry

# ==============================
# STEP 3: Parallel execution
# ==============================
log "Starting restore of all file shares (parallel=$MAX_PARALLEL)..."

for ITEM in "${!SHARE_ACCOUNT_MAP[@]}"; do
  echo "$ITEM ${SHARE_ACCOUNT_MAP[$ITEM]}"
done | xargs -n2 -P "$MAX_PARALLEL" bash -c 'process_share "$0" "$1"' 

# ==============================
# STEP 4: Summary & Gmail Email
# ==============================
SUMMARY=$(for ITEM in "${!RESTORE_STATUS[@]}"; do
  echo "$ITEM → ${RESTORE_STATUS[$ITEM]}"
done)

log "================ Summary ================"
log "$SUMMARY"

if [ -n "$EMAIL_TO" ]; then
  log "Sending Gmail email to $EMAIL_TO..."

  SUBJECT="Azure File Share Restore - $ENVIRONMENT - $(date '+%Y-%m-%d %H:%M:%S')"
  BODY="Restore Summary for environment $ENVIRONMENT:\n\n$SUMMARY"

  # Create temporary msmtp config
  TMP_MSmtp=$(mktemp)
  chmod 600 "$TMP_MSmtp"
  cat <<EOF > "$TMP_MSmtp"
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /tmp/msmtp.log

account gmail
host           smtp.gmail.com
port           587
from           $EMAIL_FROM
user           $SMTP_USER
passwordeval   "echo $SMTP_PASS"

account default : gmail
EOF

  printf "%b" "From: $EMAIL_FROM\nTo: $EMAIL_TO\nSubject: $SUBJECT\n\n$BODY" | msmtp --file="$TMP_MSmtp" $EMAIL_TO
  rm -f "$TMP_MSmtp"
fi

log "All restores completed and Gmail notifications sent."