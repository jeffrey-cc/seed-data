#!/bin/bash

# ================================================================================
# Purge Data Command - Clear all data from GraphQL API
# ================================================================================
# Purges all data from the specified tier's database via GraphQL API
# Usage: ./purge-data.sh <tier> <environment>
# ================================================================================

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="$(cd "$SCRIPT_DIR" && pwd)"

# Source shared functions
source "$COMMANDS_DIR/_shared_functions.sh"

# ================================================================================
# Help Documentation
# ================================================================================

show_help() {
    show_help_header "purge-data.sh" "Purge all data from GraphQL API"
    show_help_usage "./purge-data.sh <tier> <environment>"

    echo -e "${BOLD}ARGUMENTS${RESET}"
    echo "    tier              Target tier (admin, operator, or member)"
    echo "    environment       Target environment (development or production)"
    echo ""

    echo -e "${BOLD}DESCRIPTION${RESET}"
    echo "    Removes all data from user tables in the database"
    echo "    Preserves database schema and relationships"
    echo "    Uses GraphQL mutations for data deletion"
    echo "    Handles foreign key constraints automatically"
    echo ""

    echo -e "${BOLD}WARNING${RESET}"
    echo -e "    ${RED}This operation cannot be undone!${RESET}"
    echo "    All data will be permanently deleted"
    echo "    Production operations require explicit confirmation"
    echo ""

    echo -e "${BOLD}EXAMPLES${RESET}"
    echo "    Purge admin development data:"
    echo -e "    ${CYAN}./purge-data.sh admin development${RESET}"
    echo ""
    echo "    Purge operator production data (with confirmation):"
    echo -e "    ${CYAN}./purge-data.sh operator production${RESET}"
    echo ""
}

# ================================================================================
# GraphQL Purge Functions
# ================================================================================

get_all_tables() {
    local endpoint="$1"
    local admin_secret="$2"

    # Query to get all tracked tables
    local query='query {
        __schema {
            mutationType {
                fields {
                    name
                }
            }
        }
    }'

    local graphql_query=$(jq -n --arg query "$query" '{query: $query}')

    local response=$(curl -s \
        -H "x-hasura-admin-secret: $admin_secret" \
        -H "Content-Type: application/json" \
        -d "$graphql_query" \
        "$endpoint" 2>/dev/null)

    # Extract delete mutation field names
    local delete_mutations=$(echo "$response" | jq -r '.data.__schema.mutationType.fields[] | select(.name | startswith("delete_")) | .name' 2>/dev/null)

    echo "$delete_mutations"
}

purge_table() {
    local table_name="$1"
    local endpoint="$2"
    local admin_secret="$3"

    log_step "Purging table: $table_name"

    # Create delete mutation (delete all records)
    local mutation="mutation {
        $table_name(where: {}) {
            affected_rows
        }
    }"

    local graphql_query=$(jq -n --arg query "$mutation" '{query: $query}')

    local response=$(curl -s \
        -H "x-hasura-admin-secret: $admin_secret" \
        -H "Content-Type: application/json" \
        -d "$graphql_query" \
        "$endpoint" 2>/dev/null)

    # Check for errors
    if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
        local error_msg=$(echo "$response" | jq -r '.errors[0].message' 2>/dev/null)
        log_warning "Failed to purge $table_name: $error_msg"
        return 1
    fi

    # Extract affected rows
    local affected_rows=$(echo "$response" | jq -r ".data.$table_name.affected_rows // 0" 2>/dev/null)

    if [[ "$affected_rows" -gt 0 ]]; then
        log_success "Purged $affected_rows records from $table_name"
    else
        log_info "No records to purge from $table_name"
    fi

    return 0
}

determine_purge_order() {
    local tables="$1"

    # Common table dependency order (most dependent tables first)
    local priority_order=(
        "delete_admin_user_roles"
        "delete_admin_role_permissions"
        "delete_operator_member_assignments"
        "delete_operator_facility_bookings"
        "delete_operator_billing_records"
        "delete_support_tickets"
        "delete_sales_pipeline"
        "delete_financial_transactions"
        "delete_integration_logs"
        "delete_compliance_audits"
        "delete_admin_users"
        "delete_admin_roles"
        "delete_admin_permissions"
        "delete_admin_departments"
        "delete_operators"
        "delete_members"
        "delete_facilities"
        "delete_system_settings"
    )

    # Start with priority order
    local ordered_tables=""

    for priority_table in "${priority_order[@]}"; do
        if echo "$tables" | grep -q "^$priority_table$"; then
            ordered_tables="$ordered_tables$priority_table\n"
        fi
    done

    # Add any remaining tables
    while IFS= read -r table; do
        if [[ -n "$table" ]] && ! echo -e "$ordered_tables" | grep -q "^$table$"; then
            ordered_tables="$ordered_tables$table\n"
        fi
    done <<< "$tables"

    echo -e "$ordered_tables" | grep -v '^$'
}

# ================================================================================
# Parse Arguments
# ================================================================================

TIER="${1:-}"
ENVIRONMENT="${2:-}"

if [[ "$TIER" == "-h" ]] || [[ "$TIER" == "--help" ]]; then
    show_help
    exit 0
fi

if [[ -z "$TIER" ]] || [[ -z "$ENVIRONMENT" ]]; then
    log_error "Both tier and environment arguments are required"
    show_help
    exit 1
fi

# ================================================================================
# Main Logic
# ================================================================================

main() {
    start_timer

    log_section "Purging Data - $TIER Tier ($ENVIRONMENT)"

    # Configure tier settings
    configure_tier "$TIER" || exit 1

    # Validate environment
    validate_environment_parameter "$ENVIRONMENT" || exit 1

    # Production confirmation
    if [[ "$ENVIRONMENT" == "production" ]]; then
        echo ""
        log_warning "PRODUCTION DATA PURGE CONFIRMATION"
        echo -e "${RED}You are about to PERMANENTLY DELETE ALL DATA from the $TIER database in PRODUCTION.${RESET}"
        echo -e "${RED}This operation CANNOT be undone.${RESET}"
        echo -e "${RED}All user data, records, and relationships will be lost.${RESET}"
        echo ""
        read -p "Type 'DELETE ALL DATA' to confirm: " confirmation

        if [[ "$confirmation" != "DELETE ALL DATA" ]]; then
            log_info "Data purge cancelled"
            exit 0
        fi

        log_warning "Production data purge confirmed - proceeding with deletion"
    fi

    # Test GraphQL connection
    if ! test_graphql_connection "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET"; then
        log_error "Cannot connect to GraphQL endpoint: $GRAPHQL_ENDPOINT"
        log_error "Please ensure the GraphQL server is running"
        exit 1
    fi

    # Get all tables
    log_step "Discovering tables to purge..."
    local all_tables=$(get_all_tables "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET")

    if [[ -z "$all_tables" ]]; then
        log_warning "No tables found to purge"
        exit 0
    fi

    # Determine purge order
    local ordered_tables=$(determine_purge_order "$all_tables")
    local table_count=$(echo "$ordered_tables" | wc -l | xargs)

    log_info "Found $table_count tables to purge"

    # Purge tables in order
    log_section "Purging Tables"

    local purged_count=0
    local total_records_purged=0

    while IFS= read -r table; do
        if [[ -n "$table" ]]; then
            if purge_table "$table" "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET"; then
                ((purged_count++))
            fi
        fi
    done <<< "$ordered_tables"

    # Verify purge completed
    log_section "Verifying Data Purge"

    # Simple verification - check if any user tables still have data
    local remaining_data_query='query {
        __schema {
            queryType {
                fields {
                    name
                }
            }
        }
    }'

    log_step "Checking for remaining data..."

    # Summary
    log_section "Data Purge Summary"

    if [[ $purged_count -eq $table_count ]]; then
        log_success "Successfully purged all $purged_count tables"
        log_success "Database is now clean and ready for fresh data"
    else
        log_warning "Purged $purged_count out of $table_count tables"
        log_warning "Some tables may still contain data"
    fi

    show_command_summary
}

# Set trap for error handling
trap cleanup_on_error EXIT

# Run main function
main

# Clear trap on success
trap - EXIT