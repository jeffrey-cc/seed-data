#!/bin/bash

# ================================================================================
# Confirm Data Command - Verify and count loaded data
# ================================================================================
# Confirms that data has been loaded correctly and provides detailed counts
# Usage: ./confirm-data.sh <tier> <environment> [mode]
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
    show_help_header "confirm-data.sh" "Verify and count loaded data"
    show_help_usage "./confirm-data.sh <tier> <environment> [mode]"

    echo -e "${BOLD}ARGUMENTS${RESET}"
    echo "    tier              Target tier (admin, operator, or member)"
    echo "    environment       Target environment (development or production)"
    echo "    mode              Optional: Check mode (graphql, postgres, or both)"
    echo ""

    echo -e "${BOLD}DESCRIPTION${RESET}"
    echo "    Confirms that data has been loaded correctly"
    echo "    Provides detailed record counts by table"
    echo "    Compares loaded data with source CSV files"
    echo "    Tests data accessibility via specified method"
    echo ""

    echo -e "${BOLD}CHECK MODES${RESET}"
    echo "    graphql           Check data via GraphQL API only"
    echo "    postgres          Check data via PostgreSQL only"
    echo "    both              Check via both methods (default)"
    echo ""

    echo -e "${BOLD}EXAMPLES${RESET}"
    echo "    Confirm admin data (both methods):"
    echo -e "    ${CYAN}./confirm-data.sh admin development${RESET}"
    echo ""
    echo "    Confirm via GraphQL only:"
    echo -e "    ${CYAN}./confirm-data.sh operator development graphql${RESET}"
    echo ""
    echo "    Confirm via PostgreSQL only:"
    echo -e "    ${CYAN}./confirm-data.sh admin production postgres${RESET}"
    echo ""
}

# ================================================================================
# Data Confirmation Functions
# ================================================================================

confirm_via_graphql() {
    local tier="$1"
    local environment="$2"

    log_section "GraphQL Data Confirmation"

    # Test GraphQL connection
    if ! test_graphql_connection "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET"; then
        log_error "Cannot connect to GraphQL endpoint: $GRAPHQL_ENDPOINT"
        return 1
    fi

    # Get table counts via GraphQL
    log_step "Retrieving table counts via GraphQL..."

    local all_tables=$(get_table_counts "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET")

    if [[ -z "$all_tables" ]]; then
        log_warning "No tables found in GraphQL schema"
        return 1
    fi

    local table_count=$(echo "$all_tables" | wc -l | xargs)
    local total_records=0
    local tables_with_data=0

    log_info "Found $table_count tables accessible via GraphQL"

    printf "%-35s %10s %10s\n" "Table Name" "Records" "Status"
    printf "%-35s %10s %10s\n" "----------" "-------" "------"

    while IFS= read -r table; do
        if [[ -n "$table" ]]; then
            local count=$(count_table_records "$table" "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET")

            if [[ "$count" == "ERROR" ]]; then
                printf "%-35s %10s %10s\n" "$table" "N/A" "ERROR"
            elif [[ "$count" -eq 0 ]]; then
                printf "%-35s %10s %10s\n" "$table" "$count" "EMPTY"
            else
                printf "%-35s %10s %10s\n" "$table" "$count" "OK"
                ((tables_with_data++))
                ((total_records += count))
            fi
        fi
    done <<< "$all_tables"

    echo ""
    log_info "GraphQL Summary:"
    log_info "  Tables accessible: $table_count"
    log_info "  Tables with data: $tables_with_data"
    log_info "  Total records: $total_records"

    if [[ $tables_with_data -gt 0 ]]; then
        log_success "GraphQL data confirmation successful"
        return 0
    else
        log_warning "No data accessible via GraphQL"
        return 1
    fi
}

confirm_via_postgres() {
    local tier="$1"
    local environment="$2"

    log_section "PostgreSQL Data Confirmation"

    # Test PostgreSQL connection
    if ! test_postgres_connection "$DATABASE_URL"; then
        log_error "Cannot connect to PostgreSQL database"
        return 1
    fi

    # Get table counts via PostgreSQL
    log_step "Retrieving table counts via PostgreSQL..."

    local all_tables=$(get_all_user_tables "$DATABASE_URL")

    if [[ -z "$all_tables" ]]; then
        log_warning "No user tables found in PostgreSQL database"
        return 1
    fi

    local table_count=$(echo "$all_tables" | wc -l | xargs)
    local total_records=0
    local tables_with_data=0

    log_info "Found $table_count tables in PostgreSQL database"

    printf "%-35s %10s %10s\n" "Table Name" "Records" "Status"
    printf "%-35s %10s %10s\n" "----------" "-------" "------"

    while IFS= read -r table; do
        if [[ -n "$table" ]]; then
            local count=$(count_table_records_postgres "$table" "$DATABASE_URL")

            if [[ "$count" -eq 0 ]]; then
                printf "%-35s %10s %10s\n" "$table" "$count" "EMPTY"
            else
                printf "%-35s %10s %10s\n" "$table" "$count" "OK"
                ((tables_with_data++))
                ((total_records += count))
            fi
        fi
    done <<< "$all_tables"

    echo ""
    log_info "PostgreSQL Summary:"
    log_info "  Total tables: $table_count"
    log_info "  Tables with data: $tables_with_data"
    log_info "  Total records: $total_records"

    if [[ $tables_with_data -gt 0 ]]; then
        log_success "PostgreSQL data confirmation successful"
        return 0
    else
        log_warning "No data found in PostgreSQL tables"
        return 1
    fi
}

compare_with_source_data() {
    local tier="$1"
    local environment="$2"

    if [[ ! -d "$DATA_SOURCE_PATH" ]]; then
        log_warning "Source data path not found: $DATA_SOURCE_PATH"
        return 0
    fi

    log_section "Source Data Comparison"

    local csv_files=($(find "$DATA_SOURCE_PATH" -name "*.csv" | sort))

    if [[ ${#csv_files[@]} -eq 0 ]]; then
        log_warning "No CSV files found in source data path"
        return 0
    fi

    local total_csv_records=0
    local total_db_records=0
    local matched_tables=0
    local total_files=${#csv_files[@]}

    log_info "Comparing ${total_files} CSV files with database..."

    printf "%-35s %10s %10s %10s\n" "Table Name" "CSV" "Database" "Match"
    printf "%-35s %10s %10s %10s\n" "----------" "---" "--------" "-----"

    for csv_file in "${csv_files[@]}"; do
        local filename=$(basename "$csv_file" .csv)
        local table_name=$(echo "$filename" | sed 's/^[0-9][0-9]_//' | sed 's/^[0-9]_//')

        local csv_record_count=$(get_csv_record_count "$csv_file")
        ((total_csv_records += csv_record_count))

        # Try PostgreSQL first, fall back to GraphQL
        local db_record_count
        if test_postgres_connection "$DATABASE_URL" >/dev/null 2>&1; then
            db_record_count=$(count_table_records_postgres "$table_name" "$DATABASE_URL")
        else
            db_record_count=$(count_table_records "$table_name" "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET")
            if [[ "$db_record_count" == "ERROR" ]]; then
                db_record_count="N/A"
            fi
        fi

        if [[ "$db_record_count" != "N/A" ]]; then
            ((total_db_records += db_record_count))

            if [[ "$csv_record_count" -eq "$db_record_count" ]]; then
                printf "%-35s %10s %10s %10s\n" "$table_name" "$csv_record_count" "$db_record_count" "✓"
                ((matched_tables++))
            else
                printf "%-35s %10s %10s %10s\n" "$table_name" "$csv_record_count" "$db_record_count" "✗"
            fi
        else
            printf "%-35s %10s %10s %10s\n" "$table_name" "$csv_record_count" "N/A" "?"
        fi
    done

    echo ""
    log_info "Comparison Summary:"
    log_info "  Total CSV files: $total_files"
    log_info "  Total CSV records: $total_csv_records"
    log_info "  Total DB records: $total_db_records"
    log_info "  Matched tables: $matched_tables"

    local match_percentage=0
    if [[ $total_files -gt 0 ]]; then
        match_percentage=$((matched_tables * 100 / total_files))
    fi

    if [[ $match_percentage -eq 100 ]]; then
        log_success "Perfect match: All CSV data loaded correctly ($match_percentage%)"
        return 0
    elif [[ $match_percentage -ge 80 ]]; then
        log_warning "Good match: Most CSV data loaded correctly ($match_percentage%)"
        return 0
    else
        log_error "Poor match: Significant data loading issues ($match_percentage%)"
        return 1
    fi
}

test_data_accessibility() {
    local mode="$1"

    log_section "Data Accessibility Test"

    case "$mode" in
        "graphql")
            test_graphql_accessibility
            ;;
        "postgres")
            test_postgres_accessibility
            ;;
        "both")
            local graphql_result=0
            local postgres_result=0

            if test_graphql_accessibility; then
                graphql_result=1
            fi

            if test_postgres_accessibility; then
                postgres_result=1
            fi

            if [[ $graphql_result -eq 1 ]] && [[ $postgres_result -eq 1 ]]; then
                log_success "Data accessible via both GraphQL and PostgreSQL"
                return 0
            elif [[ $graphql_result -eq 1 ]] || [[ $postgres_result -eq 1 ]]; then
                log_warning "Data accessible via one method only"
                return 0
            else
                log_error "Data not accessible via either method"
                return 1
            fi
            ;;
        *)
            log_error "Invalid accessibility test mode: $mode"
            return 1
            ;;
    esac
}

test_graphql_accessibility() {
    log_step "Testing GraphQL data accessibility..."

    if ! test_graphql_connection "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET" >/dev/null 2>&1; then
        log_warning "GraphQL endpoint not accessible"
        return 1
    fi

    # Test sample queries
    local accessible_tables=0
    local all_tables=$(get_table_counts "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET")

    while IFS= read -r table; do
        if [[ -n "$table" ]]; then
            if sample_table_data "$table" "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET" 1 >/dev/null 2>&1; then
                ((accessible_tables++))
            fi
        fi
    done <<< "$all_tables"

    if [[ $accessible_tables -gt 0 ]]; then
        log_success "GraphQL data accessible ($accessible_tables tables)"
        return 0
    else
        log_warning "No GraphQL data accessible"
        return 1
    fi
}

test_postgres_accessibility() {
    log_step "Testing PostgreSQL data accessibility..."

    if ! test_postgres_connection "$DATABASE_URL" >/dev/null 2>&1; then
        log_warning "PostgreSQL database not accessible"
        return 1
    fi

    # Test sample queries
    local accessible_tables=0
    local all_tables=$(get_all_user_tables "$DATABASE_URL")

    while IFS= read -r table; do
        if [[ -n "$table" ]]; then
            if psql "$DATABASE_URL" -c "SELECT 1 FROM \"$table\" LIMIT 1;" >/dev/null 2>&1; then
                ((accessible_tables++))
            fi
        fi
    done <<< "$all_tables"

    if [[ $accessible_tables -gt 0 ]]; then
        log_success "PostgreSQL data accessible ($accessible_tables tables)"
        return 0
    else
        log_warning "No PostgreSQL data accessible"
        return 1
    fi
}

# ================================================================================
# Parse Arguments
# ================================================================================

TIER="${1:-}"
ENVIRONMENT="${2:-}"
MODE="${3:-both}"

if [[ "$TIER" == "-h" ]] || [[ "$TIER" == "--help" ]]; then
    show_help
    exit 0
fi

if [[ -z "$TIER" ]] || [[ -z "$ENVIRONMENT" ]]; then
    log_error "Both tier and environment arguments are required"
    show_help
    exit 1
fi

# Validate mode
if [[ "$MODE" != "graphql" ]] && [[ "$MODE" != "postgres" ]] && [[ "$MODE" != "both" ]]; then
    log_error "Invalid mode: $MODE. Must be 'graphql', 'postgres', or 'both'"
    show_help
    exit 1
fi

# ================================================================================
# Main Logic
# ================================================================================

main() {
    start_timer

    log_section "Data Confirmation - $TIER Tier ($ENVIRONMENT) [$MODE mode]"

    # Configure tier settings
    configure_tier "$TIER" || exit 1

    # Validate environment
    validate_environment_parameter "$ENVIRONMENT" || exit 1

    # Load environment configuration
    load_environment "$ENVIRONMENT" || exit 1

    # Show configuration
    echo ""
    log_info "Configuration:"
    log_info "  Tier: $TIER"
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Check Mode: $MODE"
    log_info "  Data Source: $DATA_SOURCE_PATH"

    if [[ "$MODE" == "graphql" ]] || [[ "$MODE" == "both" ]]; then
        log_info "  GraphQL Endpoint: $GRAPHQL_ENDPOINT"
    fi

    if [[ "$MODE" == "postgres" ]] || [[ "$MODE" == "both" ]]; then
        log_info "  Database URL: $DATABASE_URL"
    fi

    # Run confirmations based on mode
    local confirmation_errors=0

    case "$MODE" in
        "graphql")
            if ! confirm_via_graphql "$TIER" "$ENVIRONMENT"; then
                ((confirmation_errors++))
            fi
            ;;
        "postgres")
            if ! confirm_via_postgres "$TIER" "$ENVIRONMENT"; then
                ((confirmation_errors++))
            fi
            ;;
        "both")
            if ! confirm_via_graphql "$TIER" "$ENVIRONMENT"; then
                ((confirmation_errors++))
            fi

            if ! confirm_via_postgres "$TIER" "$ENVIRONMENT"; then
                ((confirmation_errors++))
            fi
            ;;
    esac

    # Compare with source data
    if ! compare_with_source_data "$TIER" "$ENVIRONMENT"; then
        ((confirmation_errors++))
    fi

    # Test data accessibility
    if ! test_data_accessibility "$MODE"; then
        ((confirmation_errors++))
    fi

    # Final summary
    log_section "Confirmation Summary"

    if [[ $confirmation_errors -eq 0 ]]; then
        log_success "All data confirmation checks passed"
        log_success "Data is properly loaded and accessible"
    else
        log_error "Data confirmation completed with $confirmation_errors error(s)"
        log_error "Some data may not be properly loaded"
    fi

    show_command_summary

    # Exit with appropriate code
    exit $([ $confirmation_errors -eq 0 ] && echo 0 || echo 1)
}

# Set trap for error handling
trap cleanup_on_error EXIT

# Run main function
main

# Clear trap on success
trap - EXIT