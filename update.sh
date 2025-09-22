#!/bin/bash
set -euo pipefail

# Route53 Dynamic IP Update Script - Hybrid Version
# Based on working v1 with v2 improvements

# Load configuration if available, otherwise use defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Configuration with defaults (backwards compatible)
IP_FILE="${IP_CACHE_FILE:-/tmp/current_ip.txt}"
LOG_FILE="${LOG_FILE:-/var/log/route53_update.log}"
EMAIL="${EMAIL:-michal@osmenda.com}"
JSON_FILE="${HOSTS_JSON_FILE:-/home/bk86a/route53/hosts.json}"
TMP_BATCH="/tmp/change-batch.json"
PRIMARY_IP_SERVICE="${PRIMARY_IP_SERVICE:-http://checkip.amazonaws.com}"
ENABLE_EMAIL_NOTIFICATIONS="${ENABLE_EMAIL_NOTIFICATIONS:-true}"

# Simple logging function
log_message() {
    local level="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $level: $message" | tee -a "$LOG_FILE"
}

# IP detection with basic fallback
get_current_ip() {
    local ip
    ip=$(curl -s --max-time 10 "$PRIMARY_IP_SERVICE" | tr -d '\n')
    if [[ -z "$ip" ]]; then
        # Try fallback
        ip=$(curl -s --max-time 10 "https://api.ipify.org" | tr -d '\n')
    fi
    echo "$ip"
}

log_message "INFO" "Starting Route53 Dynamic IP Update"

# Get current public IP
NEW_IP=$(get_current_ip)
if [[ -z "$NEW_IP" ]]; then
    log_message "ERROR" "Could not determine public IP"
    exit 1
fi

log_message "INFO" "Current public IP: $NEW_IP"

# Check cached IP
if [[ -f "$IP_FILE" ]]; then
    STORED_IP=$(cat "$IP_FILE")
    if [[ "$NEW_IP" == "$STORED_IP" ]]; then
        log_message "INFO" "IP unchanged ($NEW_IP). Checking Route 53 for mismatches..."
    else
        log_message "INFO" "IP changed: $STORED_IP -> $NEW_IP"
        echo "$NEW_IP" > "$IP_FILE"
    fi
else
    log_message "INFO" "No cached IP found. Will update all records."
    echo "$NEW_IP" > "$IP_FILE"
fi

# Validate JSON configuration
if [[ ! -f "$JSON_FILE" ]]; then
    log_message "ERROR" "Configuration file not found: $JSON_FILE"
    exit 1
fi

if ! jq -e . "$JSON_FILE" >/dev/null 2>&1; then
    log_message "ERROR" "Invalid JSON in $JSON_FILE"
    exit 1
fi

# Process records
COUNT=$(jq '.records | length' "$JSON_FILE")
if [[ "$COUNT" -eq 0 ]]; then
    log_message "WARN" "No records in $JSON_FILE"
    exit 0
fi

log_message "INFO" "Processing $COUNT record(s)"

UPDATED_LIST=()
for i in $(seq 0 $((COUNT-1))); do
    RECORD_NAME=$(jq -r ".records[$i].name" "$JSON_FILE")
    ZONE_ID=$(jq -r ".records[$i].zone_id" "$JSON_FILE")
    TYPE=$(jq -r ".records[$i].type // \"A\"" "$JSON_FILE")
    TTL=$(jq -r ".records[$i].ttl  // 300" "$JSON_FILE")

    if [[ "$TYPE" != "A" ]]; then
        log_message "INFO" "Skipping $RECORD_NAME type $TYPE (script updates A only)"
        continue
    fi

    # Read current Route 53 value for this record
    CURRENT_R53_IP=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$ZONE_ID" \
        --query "ResourceRecordSets[?Name=='${RECORD_NAME}.' && Type=='A'].ResourceRecords[0].Value" \
        --output text 2>/dev/null || echo "NONE")

    if [[ "$CURRENT_R53_IP" == "None" || "$CURRENT_R53_IP" == "NONE" ]]; then
        CURRENT_R53_IP=""
    fi

    if [[ "$CURRENT_R53_IP" == "$NEW_IP" ]]; then
        log_message "INFO" "$RECORD_NAME: Already correct ($NEW_IP)"
        continue
    fi

    # Create change batch
    cat > "$TMP_BATCH" <<JSON
{
  "Comment": "Dynamic IP update: ${RECORD_NAME} -> ${NEW_IP}",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${RECORD_NAME}.",
        "Type": "A",
        "TTL": ${TTL},
        "ResourceRecords": [ { "Value": "${NEW_IP}" } ]
      }
    }
  ]
}
JSON

    if aws route53 change-resource-record-sets \
        --hosted-zone-id "$ZONE_ID" \
        --change-batch "file://$TMP_BATCH" >/dev/null; then
        log_message "INFO" "Updated $RECORD_NAME: ${CURRENT_R53_IP:-'(new)'} -> $NEW_IP"
        UPDATED_LIST+=("$RECORD_NAME")
    else
        log_message "ERROR" "Failed to update $RECORD_NAME"
    fi
done

# Email notification
if [[ ${#UPDATED_LIST[@]} -gt 0 && "$ENABLE_EMAIL_NOTIFICATIONS" == "true" ]]; then
    SUMMARY="Updated ${#UPDATED_LIST[@]} record(s) to $NEW_IP:"
    for record in "${UPDATED_LIST[@]}"; do
        SUMMARY="$SUMMARY\n- $record"
    done

    if command -v msmtp &> /dev/null; then
        {
            echo "Subject: Route53 A-records updated to $NEW_IP"
            echo
            echo -e "$SUMMARY"
        } | msmtp --from=default "$EMAIL" || log_message "WARN" "Failed to send email notification"
    else
        log_message "WARN" "msmtp not found - email notifications disabled"
    fi
fi

# Cleanup
rm -f "$TMP_BATCH"

log_message "INFO" "Route53 Dynamic IP Update completed"