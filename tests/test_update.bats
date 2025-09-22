#!/usr/bin/env bats

# Route53 Dynamic IP Update - Test Suite
# Run with: bats tests/test_update.bats

setup() {
    # Set up test environment
    export TEST_DIR="$(mktemp -d)"
    export CONFIG_FILE="$TEST_DIR/config.env"
    export HOSTS_JSON_FILE="$TEST_DIR/hosts.json"
    export IP_CACHE_FILE="$TEST_DIR/current_ip.txt"
    export LOG_FILE="$TEST_DIR/test.log"

    # Create test config
    cat > "$CONFIG_FILE" <<EOF
EMAIL="test@example.com"
ENABLE_EMAIL_NOTIFICATIONS="false"
HOSTS_JSON_FILE="$HOSTS_JSON_FILE"
IP_CACHE_FILE="$IP_CACHE_FILE"
LOG_FILE="$LOG_FILE"
LOG_LEVEL="DEBUG"
MAX_RETRIES="1"
RETRY_DELAY="1"
EOF

    # Create test hosts file
    cat > "$HOSTS_JSON_FILE" <<EOF
{
  "records": [
    {
      "name": "test.example.com",
      "zone_id": "Z1234567890TEST",
      "type": "A",
      "ttl": 300
    }
  ]
}
EOF
}

teardown() {
    # Clean up test environment
    rm -rf "$TEST_DIR"
}

# Source the script functions for testing
source_script() {
    # Extract functions from update.sh for testing
    sed -n '/^validate_ip()/,/^}/p' update.sh > "$TEST_DIR/functions.sh"
    sed -n '/^check_dependencies()/,/^}/p' update.sh >> "$TEST_DIR/functions.sh"
    source "$TEST_DIR/functions.sh"
}

@test "validate_ip function accepts valid IPv4 addresses" {
    source_script
    run validate_ip "192.168.1.1"
    [ "$status" -eq 0 ]

    run validate_ip "10.0.0.1"
    [ "$status" -eq 0 ]

    run validate_ip "203.0.113.42"
    [ "$status" -eq 0 ]
}

@test "validate_ip function rejects invalid IPv4 addresses" {
    source_script
    run validate_ip "256.1.1.1"
    [ "$status" -eq 1 ]

    run validate_ip "192.168.1"
    [ "$status" -eq 1 ]

    run validate_ip "not.an.ip.address"
    [ "$status" -eq 1 ]

    run validate_ip ""
    [ "$status" -eq 1 ]
}

@test "script handles missing config file gracefully" {
    rm -f "$CONFIG_FILE"
    run timeout 10 ./update.sh
    # Should not crash due to missing config
}

@test "script validates JSON configuration" {
    # Create invalid JSON
    echo "invalid json" > "$HOSTS_JSON_FILE"

    run timeout 10 ./update.sh
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid JSON" ]]
}

@test "script handles empty records array" {
    cat > "$HOSTS_JSON_FILE" <<EOF
{
  "records": []
}
EOF

    run timeout 10 ./update.sh
    [ "$status" -eq 0 ]
}

@test "script creates log file" {
    # Remove log file if it exists
    rm -f "$LOG_FILE"

    run timeout 10 ./update.sh
    [ -f "$LOG_FILE" ]
}

@test "script handles missing dependencies" {
    # This test would need to mock missing commands
    skip "Requires mocking system commands"
}

@test "IP cache file is created and updated" {
    rm -f "$IP_CACHE_FILE"

    # Mock successful IP detection
    export PRIMARY_IP_SERVICE="echo '192.168.1.100'"

    run timeout 10 ./update.sh
    [ -f "$IP_CACHE_FILE" ]
    [ "$(cat "$IP_CACHE_FILE")" = "192.168.1.100" ]
}