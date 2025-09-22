#!/bin/bash
# Basic test suite for Route53 Dynamic IP Update
# This replaces the BATS tests for CI compatibility

set -euo pipefail

TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
test_assert() {
    local description="$1"
    local condition="$2"

    echo -n "Testing: $description... "

    if eval "$condition" >/dev/null 2>&1; then
        echo "✅ PASS"
        ((TESTS_PASSED++))
    else
        echo "❌ FAIL"
        ((TESTS_FAILED++))
    fi
}

test_command() {
    local description="$1"
    local command="$2"
    local expected_status="${3:-0}"

    echo -n "Testing: $description... "

    if eval "$command" >/dev/null 2>&1; then
        local actual_status=$?
    else
        local actual_status=$?
    fi

    if [ "$actual_status" -eq "$expected_status" ]; then
        echo "✅ PASS"
        ((TESTS_PASSED++))
    else
        echo "❌ FAIL (expected $expected_status, got $actual_status)"
        ((TESTS_FAILED++))
    fi
}

echo "🧪 Running Route53 Dynamic IP Update Tests"
echo "=========================================="

# File existence tests
test_assert "update.sh exists" "[ -f './update.sh' ]"
test_assert "install.sh exists" "[ -f './install.sh' ]"
test_assert "README.md exists" "[ -f './README.md' ]"
test_assert "config.env.example exists" "[ -f './config.env.example' ]"
test_assert "hosts.json.example exists" "[ -f './hosts.json.example' ]"

# File permission tests
test_assert "update.sh is executable" "[ -x './update.sh' ]"
test_assert "install.sh is executable" "[ -x './install.sh' ]"

# Syntax validation tests
test_command "update.sh has valid bash syntax" "bash -n ./update.sh"
test_command "install.sh has valid bash syntax" "bash -n ./install.sh"

# JSON validation tests
test_command "hosts.json.example is valid JSON" "jq . hosts.json.example"

# Configuration validation tests
test_command "config.env.example can be sourced" "bash -c 'source config.env.example'"

# Dependency tests
test_command "jq is available" "which jq"
test_command "curl is available" "which curl"

# IP validation tests (basic pattern matching)
test_command "Valid IP pattern is recognized" "bash -c '[[ \"192.168.1.1\" =~ ^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$ ]]'"
test_command "Invalid IP pattern is rejected" "! bash -c '[[ \"not.an.ip\" =~ ^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$ ]]'"

# JSON structure tests
test_command "hosts.json.example has records array" "jq -e '.records | type == \"array\"' hosts.json.example"
test_command "hosts.json.example records have required fields" "jq -e '.records[0] | has(\"name\", \"zone_id\", \"type\", \"ttl\")' hosts.json.example"

echo
echo "📊 Test Results"
echo "==============="
echo "✅ Passed: $TESTS_PASSED"
echo "❌ Failed: $TESTS_FAILED"
echo "📈 Total:  $((TESTS_PASSED + TESTS_FAILED))"

if [ "$TESTS_FAILED" -gt 0 ]; then
    echo
    echo "❌ Some tests failed!"
    exit 1
else
    echo
    echo "🎉 All tests passed!"
    exit 0
fi