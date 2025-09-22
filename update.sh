#!/bin/bash
set -euo pipefail

# Route53 Dynamic IP Update Script
# Version: 2.0.0
# https://github.com/bk86a/Route53DynamicIPUpdate

# Default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Configuration with defaults
EMAIL="${EMAIL:-""}"
ENABLE_EMAIL_NOTIFICATIONS="${ENABLE_EMAIL_NOTIFICATIONS:-false}"
HOSTS_JSON_FILE="${HOSTS_JSON_FILE:-${SCRIPT_DIR}/hosts.json}"
IP_CACHE_FILE="${IP_CACHE_FILE:-/tmp/route53_current_ip.txt}"
LOG_FILE="${LOG_FILE:-/var/log/route53_update.log}"
PRIMARY_IP_SERVICE="${PRIMARY_IP_SERVICE:-http://checkip.amazonaws.com}"
FALLBACK_IP_SERVICES="${FALLBACK_IP_SERVICES:-https://ipinfo.io/ip https://api.ipify.org https://icanhazip.com}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
ENABLE_STRUCTURED_LOGGING="${ENABLE_STRUCTURED_LOGGING:-false}"
AWS_CLI_PROFILE="${AWS_CLI_PROFILE:-}"
AWS_REGION="${AWS_REGION:-}"

# Set AWS CLI options
AWS_OPTS=""
[[ -n "$AWS_CLI_PROFILE" ]] && AWS_OPTS="$AWS_OPTS --profile $AWS_CLI_PROFILE"
[[ -n "$AWS_REGION" ]] && AWS_OPTS="$AWS_OPTS --region $AWS_REGION"

# Logging functions
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ "$ENABLE_STRUCTURED_LOGGING" == "true" ]]; then
        echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\"}" | tee -a "$LOG_FILE"
    else
        echo "$timestamp - $level: $message" | tee -a "$LOG_FILE"
    fi
}

log_debug() { [[ "$LOG_LEVEL" == "DEBUG" ]] && log "DEBUG" "$1"; }
log_info() { [[ "$LOG_LEVEL" =~ ^(DEBUG|INFO)$ ]] && log "INFO" "$1"; }
log_warn() { [[ "$LOG_LEVEL" =~ ^(DEBUG|INFO|WARN)$ ]] && log "WARN" "$1"; }
log_error() { log "ERROR" "$1"; }

# Validation functions
validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

check_dependencies() {
    local missing_deps=()

    for cmd in curl jq aws; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install missing dependencies and try again"
        exit 1
    fi

    # Check AWS CLI configuration
    if ! aws sts get-caller-identity $AWS_OPTS &>/dev/null; then
        log_error "AWS CLI not configured or credentials invalid"
        exit 1
    fi

    log_debug "All dependencies satisfied"
}

# IP detection with fallback
get_public_ip() {
    local ip=""
    local services="$PRIMARY_IP_SERVICE $FALLBACK_IP_SERVICES"

    for service in $services; do
        log_debug "Trying IP service: $service"
        if ip=$(curl -s --max-time 10 "$service" 2>/dev/null | tr -d '\n\r '); then
            if validate_ip "$ip"; then
                log_debug "Got valid IP from $service: $ip"
                echo "$ip"
                return 0
            else
                log_warn "Invalid IP format from $service: $ip"
            fi
        else
            log_warn "Failed to get IP from $service"
        fi
    done

    log_error "Could not determine public IP from any service"
    return 1
}

# AWS operations with retry logic
aws_with_retry() {
    local attempt=1
    local max_attempts="$MAX_RETRIES"

    while [[ $attempt -le $max_attempts ]]; do
        if aws "$@" $AWS_OPTS; then
            return 0
        else
            log_warn "AWS command failed (attempt $attempt/$max_attempts)"
            if [[ $attempt -lt $max_attempts ]]; then
                log_info "Retrying in ${RETRY_DELAY}s..."
                sleep "$RETRY_DELAY"
            fi
            ((attempt++))
        fi
    done

    log_error "AWS command failed after $max_attempts attempts"
    return 1
}

# Secure temp file creation
create_temp_file() {
    local temp_file
    temp_file=$(mktemp)
    echo "$temp_file"
}

# Email notification
send_notification() {
    local subject="$1"
    local body="$2"

    if [[ "$ENABLE_EMAIL_NOTIFICATIONS" != "true" ]] || [[ -z "$EMAIL" ]]; then
        log_debug "Email notifications disabled or no email configured"
        return 0
    fi

    if command -v msmtp &> /dev/null; then
        {
            echo "Subject: $subject"
            echo
            echo "$body"
        } | msmtp --from=default "$EMAIL" || log_warn "Failed to send email notification"
    else
        log_warn "msmtp not found - email notifications disabled"
    fi
}

# Main execution
main() {
    log_info "Starting Route53 Dynamic IP Update"

    # Check dependencies
    check_dependencies

    # Get current public IP
    if ! NEW_IP=$(get_public_ip); then
        exit 1
    fi

    log_info "Current public IP: $NEW_IP"

    # Check cached IP
    FORCE_UPDATE=false
    if [[ -f "$IP_CACHE_FILE" ]]; then
        STORED_IP=$(cat "$IP_CACHE_FILE")
        if [[ "$NEW_IP" == "$STORED_IP" ]]; then
            log_info "IP unchanged ($NEW_IP). Checking Route 53 for mismatches..."
        else
            log_info "IP changed: $STORED_IP -> $NEW_IP"
            FORCE_UPDATE=true
        fi
    else
        log_info "No cached IP found. Will update all records."
        FORCE_UPDATE=true
    fi

    # Update cache
    echo "$NEW_IP" > "$IP_CACHE_FILE"

    # Validate JSON configuration
    if [[ ! -f "$HOSTS_JSON_FILE" ]]; then
        log_error "Configuration file not found: $HOSTS_JSON_FILE"
        log_error "Copy hosts.json.example to hosts.json and configure your domains"
        exit 1
    fi

    if ! jq -e . "$HOSTS_JSON_FILE" >/dev/null 2>&1; then
        log_error "Invalid JSON in $HOSTS_JSON_FILE"
        exit 1
    fi

    # Process records
    RECORD_COUNT=$(jq '.records | length' "$HOSTS_JSON_FILE")
    if [[ "$RECORD_COUNT" -eq 0 ]]; then
        log_warn "No records configured in $HOSTS_JSON_FILE"
        exit 0
    fi

    log_info "Processing $RECORD_COUNT record(s)"

    UPDATED_LIST=()
    FAILED_LIST=()

    for i in $(seq 0 $((RECORD_COUNT-1))); do
        RECORD_NAME=$(jq -r ".records[$i].name" "$HOSTS_JSON_FILE")
        ZONE_ID=$(jq -r ".records[$i].zone_id" "$HOSTS_JSON_FILE")
        TYPE=$(jq -r ".records[$i].type // \"A\"" "$HOSTS_JSON_FILE")
        TTL=$(jq -r ".records[$i].ttl // 300" "$HOSTS_JSON_FILE")

        log_debug "Processing record: $RECORD_NAME (type: $TYPE, zone: $ZONE_ID)"

        if [[ "$TYPE" != "A" ]]; then
            log_info "Skipping $RECORD_NAME type $TYPE (script updates A records only)"
            continue
        fi

        # Get current Route 53 value
        CURRENT_R53_IP=$(aws_with_retry route53 list-resource-record-sets \
            --hosted-zone-id "$ZONE_ID" \
            --query "ResourceRecordSets[?Name=='${RECORD_NAME}.' && Type=='A'].ResourceRecords[0].Value" \
            --output text 2>/dev/null || echo "NONE")

        if [[ "$CURRENT_R53_IP" == "None" || "$CURRENT_R53_IP" == "NONE" ]]; then
            CURRENT_R53_IP=""
            log_info "$RECORD_NAME: No existing A record found"
        else
            log_debug "$RECORD_NAME: Current Route53 IP: $CURRENT_R53_IP"
        fi

        # Check if update needed
        if [[ "$CURRENT_R53_IP" == "$NEW_IP" && "$FORCE_UPDATE" != "true" ]]; then
            log_info "$RECORD_NAME: Already correct ($NEW_IP)"
            continue
        fi

        # Create change batch
        TMP_BATCH=$(create_temp_file)
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

        # Update Route 53 record
        if aws_with_retry route53 change-resource-record-sets \
            --hosted-zone-id "$ZONE_ID" \
            --change-batch "file://$TMP_BATCH" >/dev/null; then

            log_info "Updated $RECORD_NAME: ${CURRENT_R53_IP:-'(new)'} -> $NEW_IP"
            UPDATED_LIST+=("$RECORD_NAME")
        else
            log_error "Failed to update $RECORD_NAME"
            FAILED_LIST+=("$RECORD_NAME")
        fi

        # Cleanup
        rm -f "$TMP_BATCH"
    done

    # Summary and notifications
    if [[ ${#UPDATED_LIST[@]} -gt 0 ]]; then
        SUMMARY="Updated ${#UPDATED_LIST[@]} record(s) to $NEW_IP:"
        for record in "${UPDATED_LIST[@]}"; do
            SUMMARY="$SUMMARY\n- $record"
        done
        log_info "$SUMMARY"
        send_notification "Route53 A-records updated to $NEW_IP" "$SUMMARY"
    fi

    if [[ ${#FAILED_LIST[@]} -gt 0 ]]; then
        FAILURE_SUMMARY="Failed to update ${#FAILED_LIST[@]} record(s):"
        for record in "${FAILED_LIST[@]}"; do
            FAILURE_SUMMARY="$FAILURE_SUMMARY\n- $record"
        done
        log_error "$FAILURE_SUMMARY"
        send_notification "Route53 update failures" "$FAILURE_SUMMARY"
    fi

    if [[ ${#UPDATED_LIST[@]} -eq 0 && ${#FAILED_LIST[@]} -eq 0 ]]; then
        log_info "No updates required"
    fi

    log_info "Route53 Dynamic IP Update completed"
}

# Run main function
main "$@"