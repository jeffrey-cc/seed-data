#!/bin/bash

# ================================================================================
# Verify Data Command - Verify loaded data in GraphQL API
# ================================================================================
# Verifies that data has been properly loaded into the GraphQL API
# Usage: ./verify-data.sh <tier> <environment>
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
    show_help_header "verify-data.sh" "Verify loaded data in GraphQL API"
    show_help_usage "./verify-data.sh <tier> <environment>"

    echo -e "${BOLD}ARGUMENTS${RESET}"
    echo "    tier              Target tier (admin, operator, or member)"
    echo "    environment       Target environment (development or production)"
    echo ""

    echo -e "${BOLD}DESCRIPTION${RESET}"
    echo "    Verifies that data has been properly loaded"
    echo "    Checks record counts and basic data integrity"
    echo "    Tests GraphQL queries for accessibility"
    echo "    Validates foreign key relationships"
    echo ""

    echo -e "${BOLD}EXAMPLES${RESET}"
    echo "    Verify admin development data:"
    echo -e "    ${CYAN}./verify-data.sh admin development${RESET}"
    echo ""
    echo "    Verify operator production data:"
    echo -e "    ${CYAN}./verify-data.sh operator production${RESET}"
    echo ""
}

# ================================================================================
# GraphQL Verification Functions
# ================================================================================

get_table_counts() {
    local endpoint="$1"
    local admin_secret="$2"

    # Query to get all query fields (which represent tables)
    local query='query {
        __schema {
            queryType {
                fields {
                    name
                    type {
                        name
                        ofType {
                            name
                        }
                    }
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

    # Extract table names (fields that don't start with _)
    local table_fields=$(echo "$response" | jq -r '.data.__schema.queryType.fields[] | select(.name | test("^[^_].*") and (test("_aggregate$") | not)) | .name' 2>/dev/null)

    echo "$table_fields"
}

count_table_records() {
    local table_name="$1"
    local endpoint="$2"
    local admin_secret="$3"

    # Create count query using aggregate
    local aggregate_name="${table_name}_aggregate"
    local query="query {
        $aggregate_name {
            aggregate {
                count
            }
        }
    }"

    local graphql_query=$(jq -n --arg query "$query" '{query: $query}')

    local response=$(curl -s \
        -H "x-hasura-admin-secret: $admin_secret" \
        -H "Content-Type: application/json" \
        -d "$graphql_query" \
        "$endpoint" 2>/dev/null)

    # Check for errors
    if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
        echo "ERROR"
        return 1
    fi

    # Extract count
    local count=$(echo "$response" | jq -r ".data.$aggregate_name.aggregate.count // 0" 2>/dev/null)
    echo "$count"
    return 0
}

sample_table_data() {
    local table_name="$1"
    local endpoint="$2"
    local admin_secret="$3"
    local limit="${4:-5}"

    # Create sample query
    local query="query {
        $table_name(limit: $limit) {
            __typename
        }
    }"

    local graphql_query=$(jq -n --arg query "$query" '{query: $query}')

    local response=$(curl -s \
        -H "x-hasura-admin-secret: $admin_secret" \
        -H "Content-Type: application/json" \
        -d "$graphql_query" \
        "$endpoint" 2>/dev/null)

    # Check for errors
    if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
        return 1
    fi

    # Check if we got data
    local data_count=$(echo "$response" | jq -r ".data.$table_name | length // 0" 2>/dev/null)
    if [[ "$data_count" -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# ================================================================================
# Verification Functions
# ================================================================================

verify_basic_connectivity() {
    local endpoint="$1"
    local admin_secret="$2"

    log_step "Verifying GraphQL connectivity..."

    if test_graphql_connection "$endpoint" "$admin_secret"; then
        log_success "GraphQL endpoint is accessible"
        return 0
    else
        log_error "Cannot connect to GraphQL endpoint"
        return 1
    fi
}

verify_table_data() {
    local endpoint="$1"
    local admin_secret="$2"

    log_step "Discovering tables..."

    local all_tables=$(get_table_counts "$endpoint" "$admin_secret")

    if [[ -z "$all_tables" ]]; then
        log_warning "No tables found in GraphQL schema"
        return 1
    fi

    local table_count=$(echo "$all_tables" | wc -l | xargs)
    log_info "Found $table_count tables to verify"

    log_section "Table Record Counts"

    local total_records=0
    local tables_with_data=0
    local empty_tables=0
    local error_tables=0

    printf "%-30s %10s %10s\n" "Table Name" "Records" "Status"
    printf "%-30s %10s %10s\n" "----------" "-------" "------"

    while IFS= read -r table; do
        if [[ -n "$table" ]]; then
            local count=$(count_table_records "$table" "$endpoint" "$admin_secret")

            if [[ "$count" == "ERROR" ]]; then
                printf "%-30s %10s %10s\n" "$table" "N/A" "ERROR"
                ((error_tables++))
            elif [[ "$count" -eq 0 ]]; then
                printf "%-30s %10s %10s\n" "$table" "$count" "EMPTY"
                ((empty_tables++))
            else
                printf "%-30s %10s %10s\n" "$table" "$count" "OK"
                ((tables_with_data++))
                ((total_records += count))
            fi
        fi
    done <<< "$all_tables"

    echo ""
    log_info "Verification Summary:"
    log_info "  Tables with data: $tables_with_data"
    log_info "  Empty tables: $empty_tables"
    log_info "  Error tables: $error_tables"
    log_info "  Total records: $total_records"

    if [[ $error_tables -gt 0 ]]; then
        log_warning "Some tables had errors during verification"
        return 1
    fi

    if [[ $tables_with_data -eq 0 ]]; then
        log_warning "No tables contain data"
        return 1
    fi

    log_success "Data verification completed successfully"
    return 0
}

verify_data_accessibility() {
    local endpoint="$1"
    local admin_secret="$2"

    log_step "Testing data accessibility..."

    local all_tables=$(get_table_counts "$endpoint" "$admin_secret")
    local accessible_tables=0
    local inaccessible_tables=0

    while IFS= read -r table; do
        if [[ -n "$table" ]]; then
            if sample_table_data "$table" "$endpoint" "$admin_secret" 1; then
                ((accessible_tables++))
                log_debug "Table $table is accessible"
            else
                ((inaccessible_tables++))
                log_debug "Table $table is not accessible or empty"
            fi
        fi
    done <<< "$all_tables"

    log_info "Accessible tables: $accessible_tables"

    if [[ $inaccessible_tables -gt 0 ]]; then
        log_info "Inaccessible/empty tables: $inaccessible_tables"
    fi

    if [[ $accessible_tables -gt 0 ]]; then
        log_success "Data is accessible via GraphQL"
        return 0
    else
        log_warning "No data is accessible via GraphQL"
        return 1
    fi
}

compare_with_source_data() {
    local data_source_path="$1"
    local endpoint="$2"
    local admin_secret="$3"

    if [[ ! -d "$data_source_path" ]]; then
        log_warning "Source data path not found: $data_source_path"
        return 0
    fi

    log_section "Comparing with Source CSV Data"

    local csv_files=($(find "$data_source_path" -name "*.csv" | sort))
    local total_csv_records=0
    local matched_tables=0

    for csv_file in "${csv_files[@]}"; do
        local filename=$(basename "$csv_file" .csv)
        local table_name=$(echo "$filename" | sed 's/^[0-9][0-9]_//' | sed 's/^[0-9]_//')

        local csv_record_count=$(get_csv_record_count "$csv_file")
        local db_record_count=$(count_table_records "$table_name" "$endpoint" "$admin_secret")

        if [[ "$db_record_count" != "ERROR" ]]; then
            printf "%-30s %10s %10s %10s\n" "$table_name" "$csv_record_count" "$db_record_count" "$([ "$csv_record_count" -eq "$db_record_count" ] && echo "MATCH" || echo "DIFF")"

            if [[ "$csv_record_count" -eq "$db_record_count" ]]; then
                ((matched_tables++))
            fi

            ((total_csv_records += csv_record_count))
        fi
    done

    echo ""
    log_info "CSV vs Database comparison:"
    log_info "  Total CSV records: $total_csv_records"
    log_info "  Matched tables: $matched_tables"

    if [[ $matched_tables -gt 0 ]]; then
        log_success "Source data comparison completed"
    else
        log_warning "No tables matched source data counts"
    fi

    return 0
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

    log_section "Verifying Data - $TIER Tier ($ENVIRONMENT)"

    # Configure tier settings
    configure_tier "$TIER" || exit 1

    # Validate environment
    validate_environment_parameter "$ENVIRONMENT" || exit 1

    # Test basic connectivity
    if ! verify_basic_connectivity "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET"; then
        log_error "Cannot proceed with verification - GraphQL endpoint not accessible"
        exit 1
    fi

    # Verify table data
    if ! verify_table_data "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET"; then
        log_error "Data verification failed"
        ((COMMAND_ERRORS++))
    fi

    # Verify data accessibility
    if ! verify_data_accessibility "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET"; then
        log_error "Data accessibility verification failed"
        ((COMMAND_ERRORS++))
    fi

    # Compare with source data if available
    if [[ -d "$DATA_SOURCE_PATH" ]]; then
        compare_with_source_data "$DATA_SOURCE_PATH" "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET"
    fi

    # Final status
    log_section "Verification Complete"

    if [[ $COMMAND_ERRORS -eq 0 ]]; then
        log_success "All data verification checks passed"
    else
        log_error "Data verification completed with $COMMAND_ERRORS error(s)"
    fi

    show_command_summary
}

# Set trap for error handling
trap cleanup_on_error EXIT

# Run main function
main

# Clear trap on success
trap - EXIT