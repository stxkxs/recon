#!/usr/bin/env bash
#
# test_dirs.sh - Unit tests for Directory Discovery module
#

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Force colors for test output
export RECON_COLOR=always

# Source required libraries
source "${PROJECT_ROOT}/lib/core/common.sh"
source "${PROJECT_ROOT}/lib/core/config.sh"
source "${PROJECT_ROOT}/lib/core/input.sh"
source "${PROJECT_ROOT}/lib/core/output.sh"
source "${PROJECT_ROOT}/lib/core/state.sh"
source "${PROJECT_ROOT}/lib/modules/dirs.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
assert_equals() {
    local expected=$1
    local actual=$2
    local message=${3:-""}

    ((TESTS_RUN++)) || true

    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $message"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
    fi
}

assert_json_valid() {
    local json=$1
    local message=${2:-""}

    ((TESTS_RUN++)) || true

    if echo "$json" | jq . >/dev/null 2>&1; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $message"
        echo "  Invalid JSON: ${json:0:100}..."
    fi
}

assert_json_has_key() {
    local json=$1
    local key=$2
    local message=${3:-""}

    ((TESTS_RUN++)) || true

    if echo "$json" | jq "has(\"$key\")" 2>/dev/null | grep -q 'true'; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $message"
        echo "  Key '$key' not found in JSON"
    fi
}

assert_json_value() {
    local json=$1
    local key=$2
    local expected=$3
    local message=${4:-""}

    ((TESTS_RUN++)) || true

    local actual
    actual=$(echo "$json" | jq -r ".$key")

    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $message"
        echo "  Expected .$key = $expected"
        echo "  Actual .$key = $actual"
    fi
}

echo "================================================"
echo "Testing: Directory Discovery Module"
echo "================================================"
echo ""

# ─── Function Existence Tests ───

echo "--- function existence ---"

for func in dirs_run dirs_print dirs_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

echo ""

# ─── Dependency Check Tests ───

echo "--- dependency checks ---"

((TESTS_RUN++)) || true
if dirs_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} dirs_check passes (curl available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} dirs_check passes"
fi

echo ""

# ─── Module Info Tests ───

echo "--- module info ---"

assert_equals "dirs" "$MODULE_DIRS_NAME" "MODULE_DIRS_NAME is 'dirs'"
assert_equals "Directory and sensitive file discovery" "$MODULE_DIRS_DESCRIPTION" "MODULE_DIRS_DESCRIPTION is correct"

echo ""

# ─── Path Array Tests ───

echo "--- path arrays ---"

((TESTS_RUN++)) || true
if [[ ${#DIRS_VERSION_CONTROL[@]} -ge 5 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} DIRS_VERSION_CONTROL has ${#DIRS_VERSION_CONTROL[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} DIRS_VERSION_CONTROL should have at least 5 entries (got ${#DIRS_VERSION_CONTROL[@]})"
fi

((TESTS_RUN++)) || true
if [[ ${#DIRS_CONFIG_FILES[@]} -ge 10 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} DIRS_CONFIG_FILES has ${#DIRS_CONFIG_FILES[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} DIRS_CONFIG_FILES should have at least 10 entries (got ${#DIRS_CONFIG_FILES[@]})"
fi

((TESTS_RUN++)) || true
if [[ ${#DIRS_ADMIN_PANELS[@]} -ge 5 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} DIRS_ADMIN_PANELS has ${#DIRS_ADMIN_PANELS[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} DIRS_ADMIN_PANELS should have at least 5 entries (got ${#DIRS_ADMIN_PANELS[@]})"
fi

((TESTS_RUN++)) || true
if [[ ${#DIRS_API_DOCS[@]} -ge 5 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} DIRS_API_DOCS has ${#DIRS_API_DOCS[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} DIRS_API_DOCS should have at least 5 entries (got ${#DIRS_API_DOCS[@]})"
fi

((TESTS_RUN++)) || true
if [[ ${#DIRS_DEBUG_DEV[@]} -ge 5 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} DIRS_DEBUG_DEV has ${#DIRS_DEBUG_DEV[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} DIRS_DEBUG_DEV should have at least 5 entries (got ${#DIRS_DEBUG_DEV[@]})"
fi

((TESTS_RUN++)) || true
if [[ ${#DIRS_BACKUP[@]} -ge 5 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} DIRS_BACKUP has ${#DIRS_BACKUP[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} DIRS_BACKUP should have at least 5 entries (got ${#DIRS_BACKUP[@]})"
fi

((TESTS_RUN++)) || true
if [[ ${#DIRS_ACTUATOR[@]} -ge 5 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} DIRS_ACTUATOR has ${#DIRS_ACTUATOR[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} DIRS_ACTUATOR should have at least 5 entries (got ${#DIRS_ACTUATOR[@]})"
fi

((TESTS_RUN++)) || true
if [[ ${#DIRS_SECURITY[@]} -ge 4 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} DIRS_SECURITY has ${#DIRS_SECURITY[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} DIRS_SECURITY should have at least 4 entries (got ${#DIRS_SECURITY[@]})"
fi

# Verify known paths are present
for path in "/.git/config" "/.env" "/admin" "/swagger.json" "/phpinfo.php" "/backup.zip" "/actuator" "/robots.txt"; do
    ((TESTS_RUN++)) || true
    found=false
    for arr in DIRS_VERSION_CONTROL DIRS_CONFIG_FILES DIRS_ADMIN_PANELS DIRS_API_DOCS DIRS_DEBUG_DEV DIRS_BACKUP DIRS_ACTUATOR DIRS_SECURITY; do
        eval 'for p in "${'"$arr"'[@]}"; do
            if [[ "$p" == "'"$path"'" ]]; then
                found=true
                break 2
            fi
        done'
    done
    if $found; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} Path arrays include: $path"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} Path arrays missing: $path"
    fi
done

echo ""

# ─── Category Detection Tests ───

echo "--- category detection ---"

cat_result=$(_dirs_get_category "/.git/config")
assert_equals "version_control" "$cat_result" "_dirs_get_category detects version_control"

cat_result=$(_dirs_get_category "/.env")
assert_equals "config_file" "$cat_result" "_dirs_get_category detects config_file"

cat_result=$(_dirs_get_category "/admin")
assert_equals "admin_panel" "$cat_result" "_dirs_get_category detects admin_panel"

cat_result=$(_dirs_get_category "/swagger.json")
assert_equals "api_docs" "$cat_result" "_dirs_get_category detects api_docs"

cat_result=$(_dirs_get_category "/phpinfo.php")
assert_equals "debug_dev" "$cat_result" "_dirs_get_category detects debug_dev"

cat_result=$(_dirs_get_category "/backup.zip")
assert_equals "backup" "$cat_result" "_dirs_get_category detects backup"

cat_result=$(_dirs_get_category "/actuator")
assert_equals "actuator" "$cat_result" "_dirs_get_category detects actuator"

cat_result=$(_dirs_get_category "/robots.txt")
assert_equals "security" "$cat_result" "_dirs_get_category detects security"

cat_result=$(_dirs_get_category "/unknown/path")
assert_equals "custom" "$cat_result" "_dirs_get_category returns custom for unknown paths"

echo ""

# ─── Severity Detection Tests ───

echo "--- severity detection ---"

sev_result=$(_dirs_get_severity "version_control" "/.git/config" 200)
assert_equals "critical" "$sev_result" "version_control + 200 = critical"

sev_result=$(_dirs_get_severity "config_file" "/.env" 200)
assert_equals "critical" "$sev_result" ".env + 200 = critical"

sev_result=$(_dirs_get_severity "config_file" "/.htpasswd" 200)
assert_equals "critical" "$sev_result" ".htpasswd + 200 = critical"

sev_result=$(_dirs_get_severity "admin_panel" "/admin" 200)
assert_equals "high" "$sev_result" "admin_panel + 200 = high"

sev_result=$(_dirs_get_severity "debug_dev" "/phpinfo.php" 200)
assert_equals "high" "$sev_result" "debug_dev + 200 = high"

sev_result=$(_dirs_get_severity "api_docs" "/swagger.json" 200)
assert_equals "medium" "$sev_result" "api_docs + 200 = medium"

sev_result=$(_dirs_get_severity "actuator" "/actuator/env" 200)
assert_equals "medium" "$sev_result" "actuator + 200 = medium"

sev_result=$(_dirs_get_severity "backup" "/backup.zip" 200)
assert_equals "critical" "$sev_result" "backup + 200 = critical"

sev_result=$(_dirs_get_severity "security" "/robots.txt" 200)
assert_equals "low" "$sev_result" "security + 200 = low"

sev_result=$(_dirs_get_severity "version_control" "/.git/config" 403)
assert_equals "low" "$sev_result" "any category + 403 = low"

sev_result=$(_dirs_get_severity "admin_panel" "/admin" 401)
assert_equals "medium" "$sev_result" "any category + 401 = medium"

sev_result=$(_dirs_get_severity "admin_panel" "/admin" 301)
assert_equals "low" "$sev_result" "any category + 301 = low"

echo ""

# ─── Overall Risk Tests ───

echo "--- overall risk ---"

risk=$(_dirs_overall_risk '[]')
assert_equals "none" "$risk" "Empty findings = none risk"

risk=$(_dirs_overall_risk '[{"severity":"critical"}]')
assert_equals "critical" "$risk" "Critical finding = critical risk"

risk=$(_dirs_overall_risk '[{"severity":"high"}]')
assert_equals "high" "$risk" "High finding = high risk"

risk=$(_dirs_overall_risk '[{"severity":"medium"}]')
assert_equals "medium" "$risk" "Medium finding = medium risk"

risk=$(_dirs_overall_risk '[{"severity":"low"}]')
assert_equals "low" "$risk" "Low finding = low risk"

risk=$(_dirs_overall_risk '[{"severity":"low"},{"severity":"high"}]')
assert_equals "high" "$risk" "Mixed low+high = high risk"

echo ""

# ─── JSON Output Structure Tests ───

echo "--- JSON output structure ---"

# Mock result with findings
mock_result=$(jq -n '{
    total_checked: 77,
    found: [
        {"path": "/.git/config", "status": 200, "category": "version_control", "severity": "critical"},
        {"path": "/.env", "status": 200, "category": "config_file", "severity": "critical"},
        {"path": "/admin", "status": 403, "category": "admin_panel", "severity": "low"},
        {"path": "/swagger.json", "status": 200, "category": "api_docs", "severity": "medium"}
    ],
    risk: "critical",
    categories: {
        "version_control": 1,
        "config_file": 1,
        "admin_panel": 1,
        "api_docs": 1
    }
}')

assert_json_valid "$mock_result" "Mock result JSON is valid"
assert_json_has_key "$mock_result" "total_checked" "Has 'total_checked' key"
assert_json_has_key "$mock_result" "found" "Has 'found' key"
assert_json_has_key "$mock_result" "risk" "Has 'risk' key"
assert_json_has_key "$mock_result" "categories" "Has 'categories' key"
assert_json_value "$mock_result" "total_checked" "77" "total_checked is 77"
assert_json_value "$mock_result" "risk" "critical" "risk is critical"

found_count=$(echo "$mock_result" | jq '.found | length')
assert_equals "4" "$found_count" "found array has 4 entries"

# Verify finding structure
assert_json_value "$mock_result" "found[0].path" "/.git/config" "First finding path is /.git/config"
assert_json_value "$mock_result" "found[0].status" "200" "First finding status is 200"
assert_json_value "$mock_result" "found[0].category" "version_control" "First finding category is version_control"
assert_json_value "$mock_result" "found[0].severity" "critical" "First finding severity is critical"

# Mock result with no findings
no_findings=$(jq -n '{
    total_checked: 77,
    found: [],
    risk: "none",
    categories: {}
}')

assert_json_valid "$no_findings" "No-findings JSON is valid"
assert_json_value "$no_findings" "risk" "none" "risk is none when no findings"

no_found_count=$(echo "$no_findings" | jq '.found | length')
assert_equals "0" "$no_found_count" "found array is empty"

echo ""

# ─── Print Function Tests ───

echo "--- print function ---"

# Test that dirs_print handles findings
((TESTS_RUN++)) || true
print_output=$(dirs_print "$mock_result" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} dirs_print produces output for findings"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} dirs_print produces output for findings"
fi

# Test that dirs_print handles no findings
((TESTS_RUN++)) || true
print_output=$(dirs_print "$no_findings" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} dirs_print produces output for no findings"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} dirs_print produces output for no findings"
fi

echo ""

# ─── Source Guard Tests ───

echo "--- source guard ---"

((TESTS_RUN++)) || true
if [[ "$_RECON_MODULE_DIRS_LOADED" == "1" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Source guard variable is set"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Source guard variable is set"
fi

echo ""

# Summary
echo ""
echo "================================================"
echo "Test Summary"
echo "================================================"
echo -e "Total:  $TESTS_RUN"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
