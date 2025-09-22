#!/bin/bash
set -euo pipefail

IP_FILE="/tmp/current_ip.txt"
LOG_FILE="/var/log/route53_update.log"
EMAIL="michal@osmenda.com"
JSON_FILE="/home/bk86a/route53/hosts.json"
TMP_BATCH="/tmp/change-batch.json"

NEW_IP=$(curl -s http://checkip.amazonaws.com | tr -d '\n')
if [[ -z "$NEW_IP" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Could not determine public IP" | tee -a "$LOG_FILE"
  exit 1
fi

# Cache info text only - do not early-exit here; we will still fix mismatches in Route 53
if [[ -f "$IP_FILE" ]]; then
  STORED_IP=$(cat "$IP_FILE")
  if [[ "$NEW_IP" == "$STORED_IP" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - IP unchanged (${NEW_IP}). Checking Route 53 for mismatches..." >> "$LOG_FILE"
  else
    echo "$NEW_IP" > "$IP_FILE"
  fi
else
  echo "$NEW_IP" > "$IP_FILE"
fi

if ! jq -e . "$JSON_FILE" >/dev/null 2>&1; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Invalid JSON in $JSON_FILE" | tee -a "$LOG_FILE"
  exit 1
fi

COUNT=$(jq '.records | length' "$JSON_FILE")
if [[ "$COUNT" -eq 0 ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: No records in $JSON_FILE" >> "$LOG_FILE"
  exit 0
fi

UPDATED_LIST=()
for i in $(seq 0 $((COUNT-1))); do
  RECORD_NAME=$(jq -r ".records[$i].name" "$JSON_FILE")
  ZONE_ID=$(jq -r ".records[$i].zone_id" "$JSON_FILE")
  TYPE=$(jq -r ".records[$i].type // \"A\"" "$JSON_FILE")
  TTL=$(jq -r ".records[$i].ttl  // 300" "$JSON_FILE")

  if [[ "$TYPE" != "A" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: Skipping $RECORD_NAME type $TYPE (script updates A only)" >> "$LOG_FILE"
    continue
  fi

  # Read current Route 53 value for this record (first A)
  CURRENT_R53_IP=$(aws route53 list-resource-record-sets \
      --hosted-zone-id "$ZONE_ID" \
      --query "ResourceRecordSets[?Name=='${RECORD_NAME}.\' && Type=='A'].ResourceRecords[0].Value" \
      --output text 2>/dev/null || echo "NONE")

  if [[ "$CURRENT_R53_IP" == "None" || "$CURRENT_R53_IP" == "NONE" ]]; then
    CURRENT_R53_IP=""
  fi

  if [[ "$CURRENT_R53_IP" == "$NEW_IP" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - OK: $RECORD_NAME already $NEW_IP" >> "$LOG_FILE"
    continue
  fi

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
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Updated A ${RECORD_NAME}: ${CURRENT_R53_IP} -> ${NEW_IP} (zone ${ZONE_ID})" >> "$LOG_FILE"
    UPDATED_LIST+=("A ${RECORD_NAME}")
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - FAILED to update A ${RECORD_NAME} (zone ${ZONE_ID})" >> "$LOG_FILE"
  fi
done

if [[ ${#UPDATED_LIST[@]} -gt 0 ]]; then
  {
    echo "Subject: Route53 A-records updated to ${NEW_IP}"
    echo
    echo "Updated records:"
    printf '%s\n' "${UPDATED_LIST[@]}"
  } | msmtp --from=default "$EMAIL" || true
fi

rm -f "$TMP_BATCH"
