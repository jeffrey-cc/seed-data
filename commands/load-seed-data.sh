#!/bin/bash

# ================================================================================
# Load Seed Data Command - Enhanced CSV data deployment with multiple modes
# ================================================================================
# Complete pipeline with GraphQL or PostgreSQL upload modes
# Usage: ./load-seed-data.sh <tier> <environment> <mode> [options]
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
    show_help_header "load-seed-data.sh" "Enhanced CSV data deployment pipeline"
    show_help_usage "./load-seed-data.sh <tier> <environment> <mode> [options]"

    echo -e "${BOLD}ARGUMENTS${RESET}"
    echo "    tier              Target tier (admin, operator, or member)"
    echo "    environment       Target environment (development or production)"
    echo "    mode              Upload mode (graphql or postgres)"
    echo ""

    echo -e "${BOLD}OPTIONS${RESET}"
    echo "    --skip-purge      Skip the data purge step"
    echo "    --purge-only      Only purge data, skip loading"
    echo "    --verify-only     Only verify existing data"
    echo "    --table TABLE     Load only specific table"
    echo ""

    echo -e "${BOLD}UPLOAD MODES${RESET}"
    echo "    graphql           Upload via GraphQL API (uses Hasura mutations)"
    echo "    postgres          Upload directly to PostgreSQL (uses SQL INSERT)"
    echo ""

    echo -e "${BOLD}PIPELINE PHASES${RESET}"
    echo "    1. Connection Test - Verify target system accessibility"
    echo "    2. Data Purge      - Remove existing data (optional)"
    echo "    3. Data Loading    - Upload CSV data using specified mode"
    echo "    4. Verification    - Confirm data loaded correctly"
    echo ""

    echo -e "${BOLD}EXAMPLES${RESET}"
    echo "    Load admin data via GraphQL:"
    echo -e "    ${CYAN}./load-seed-data.sh admin development graphql${RESET}"
    echo ""
    echo "    Load operator data via PostgreSQL:"
    echo -e "    ${CYAN}./load-seed-data.sh operator development postgres${RESET}"
    echo ""
    echo "    Load without purging:"
    echo -e "    ${CYAN}./load-seed-data.sh admin development postgres --skip-purge${RESET}"
    echo ""
    echo "    Load specific table only:"
    echo -e "    ${CYAN}./load-seed-data.sh admin development graphql --table admin_users${RESET}"
    echo ""
    echo "    Purge data only:"
    echo -e "    ${CYAN}./load-seed-data.sh admin development postgres --purge-only${RESET}"
    echo ""
}

# ================================================================================
# Mode-specific Functions
# ================================================================================

test_connection() {
    local mode="$1"
    local tier="$2"
    local environment="$3"

    log_section "Phase 1: Connection Testing"

    case "$mode" in
        "graphql")
            if ! test_graphql_connection "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET"; then
                log_error "GraphQL endpoint not accessible: $GRAPHQL_ENDPOINT"
                log_error "Please ensure the GraphQL server is running"
                return 1
            fi
            ;;
        "postgres")
            if ! test_postgres_connection "$DATABASE_URL"; then
                log_error "PostgreSQL database not accessible"
                log_error "Please ensure the database is running and accessible"
                return 1
            fi
            ;;
        *)
            log_error "Invalid mode: $mode"
            return 1
            ;;
    esac

    log_success "Connection test passed for $mode mode"
    return 0
}

purge_data() {
    local mode="$1"
    local tier="$2"
    local environment="$3"

    log_section "Phase 2: Data Purge"

    case "$mode" in
        "graphql")
            # Use existing GraphQL purge
            local purge_script="$COMMANDS_DIR/purge-data.sh"
            if [[ ! -x "$purge_script" ]]; then
                log_error "GraphQL purge script not found: $purge_script"
                return 1
            fi

            if "$purge_script" "$tier" "$environment"; then
                log_success "GraphQL data purge completed"
                return 0
            else
                log_error "GraphQL data purge failed"
                return 1
            fi
            ;;
        "postgres")
            if purge_all_tables_postgres "$DATABASE_URL"; then
                log_success "PostgreSQL data purge completed"
                return 0
            else
                log_error "PostgreSQL data purge failed"
                return 1
            fi
            ;;
        *)
            log_error "Invalid mode: $mode"
            return 1
            ;;
    esac
}

load_data() {
    local mode="$1"
    local tier="$2"
    local environment="$3"
    local specific_table="$4"

    log_section "Phase 3: Data Loading ($mode mode)"

    # Check if data source exists
    if [[ ! -d "$DATA_SOURCE_PATH" ]]; then
        log_error "Data source directory not found: $DATA_SOURCE_PATH"
        return 1
    fi

    case "$mode" in
        "graphql")
            if [[ -n "$specific_table" ]]; then
                load_specific_table_graphql "$specific_table"
            else
                load_all_data_graphql
            fi
            ;;
        "postgres")
            if [[ -n "$specific_table" ]]; then
                load_specific_table_postgres "$specific_table"
            else
                load_all_data_postgres
            fi
            ;;
        *)
            log_error "Invalid mode: $mode"
            return 1
            ;;
    esac
}

load_all_data_graphql() {
    log_step "Loading all CSV data via GraphQL..."

    local load_script="$COMMANDS_DIR/load-csv-data.sh"
    if [[ ! -x "$load_script" ]]; then
        log_error "GraphQL load script not found: $load_script"
        return 1
    fi

    if "$load_script" "$TIER" "$ENVIRONMENT"; then
        log_success "GraphQL data loading completed"
        return 0
    else
        log_error "GraphQL data loading failed"
        return 1
    fi
}

load_all_data_postgres() {
    log_step "Loading all CSV data via PostgreSQL..."

    local total_files=0
    local successful_files=0
    local total_records_loaded=0

    # Find all CSV files and load them
    for data_subdir in $(find "$DATA_SOURCE_PATH" -type d | sort); do
        if [[ -n "$(find "$data_subdir" -maxdepth 1 -name "*.csv" 2>/dev/null)" ]]; then
            local subdir_name=$(basename "$data_subdir")
            log_step "Processing directory: $subdir_name"

            for csv_file in $(find "$data_subdir" -maxdepth 1 -name "*.csv" | sort); do
                ((total_files++))

                # Extract table name from filename
                local filename=$(basename "$csv_file" .csv)
                local table_name=$(echo "$filename" | sed 's/^[0-9][0-9]_//' | sed 's/^[0-9]_//')

                # Get record count for tracking
                local record_count=$(get_csv_record_count "$csv_file")

                if load_csv_to_postgres "$csv_file" "$table_name" "$DATABASE_URL"; then
                    ((successful_files++))
                    ((total_records_loaded += record_count))
                fi
            done
        fi
    done

    log_info "PostgreSQL loading summary:"
    log_info "  Files processed: $total_files"
    log_info "  Successful loads: $successful_files"
    log_info "  Total records loaded: $total_records_loaded"

    if [[ $successful_files -eq $total_files ]]; then
        log_success "PostgreSQL data loading completed successfully"
        return 0
    else
        log_error "PostgreSQL data loading completed with errors ($((total_files - successful_files)) failures)"
        return 1
    fi
}

load_specific_table_graphql() {
    local table_name="$1"

    log_step "Loading specific table via GraphQL: $table_name"

    # Find CSV file for this table
    local csv_files=($(find "$DATA_SOURCE_PATH" -name "*${table_name}*.csv"))

    if [[ ${#csv_files[@]} -eq 0 ]]; then
        log_error "No CSV files found for table: $table_name"
        return 1
    fi

    # Use existing GraphQL load function for the specific table
    local load_script="$COMMANDS_DIR/load-csv-data.sh"
    if "$load_script" "$TIER" "$ENVIRONMENT" "$table_name"; then
        log_success "GraphQL table loading completed: $table_name"
        return 0
    else
        log_error "GraphQL table loading failed: $table_name"
        return 1
    fi
}

load_specific_table_postgres() {
    local table_name="$1"

    log_step "Loading specific table via PostgreSQL: $table_name"

    # Find CSV file for this table
    local csv_files=($(find "$DATA_SOURCE_PATH" -name "*${table_name}*.csv"))

    if [[ ${#csv_files[@]} -eq 0 ]]; then
        log_error "No CSV files found for table: $table_name"
        return 1
    fi

    local successful_loads=0

    for csv_file in "${csv_files[@]}"; do
        if load_csv_to_postgres "$csv_file" "$table_name" "$DATABASE_URL"; then
            ((successful_loads++))
        fi
    done

    if [[ $successful_loads -gt 0 ]]; then
        log_success "PostgreSQL table loading completed: $table_name"
        return 0
    else
        log_error "PostgreSQL table loading failed: $table_name"
        return 1
    fi
}

verify_data() {
    local mode="$1"
    local tier="$2"
    local environment="$3"

    log_section "Phase 4: Data Verification"

    case "$mode" in
        "graphql")
            # Use existing GraphQL verification
            local verify_script="$COMMANDS_DIR/verify-data.sh"
            if [[ ! -x "$verify_script" ]]; then
                log_error "GraphQL verify script not found: $verify_script"
                return 1
            fi

            if "$verify_script" "$tier" "$environment"; then
                log_success "GraphQL data verification completed"
                return 0
            else
                log_error "GraphQL data verification failed"
                return 1
            fi
            ;;
        "postgres")
            verify_data_postgres
            ;;
        *)
            log_error "Invalid mode: $mode"
            return 1
            ;;
    esac
}

verify_data_postgres() {
    log_step "Verifying PostgreSQL data..."

    local tables=$(get_all_user_tables "$DATABASE_URL")

    if [[ -z "$tables" ]]; then
        log_warning "No tables found in database"
        return 1
    fi

    local table_count=$(echo "$tables" | wc -l | xargs)
    local total_records=0
    local tables_with_data=0

    log_info "Found $table_count tables to verify"

    printf "%-30s %10s\n" "Table Name" "Records"
    printf "%-30s %10s\n" "----------" "-------"

    while IFS= read -r table; do
        if [[ -n "$table" ]]; then
            local count=$(count_table_records_postgres "$table" "$DATABASE_URL")
            printf "%-30s %10s\n" "$table" "$count"

            if [[ $count -gt 0 ]]; then
                ((tables_with_data++))
                ((total_records += count))
            fi
        fi
    done <<< "$tables"

    echo ""
    log_info "Verification summary:"
    log_info "  Tables with data: $tables_with_data/$table_count"
    log_info "  Total records: $total_records"

    if [[ $tables_with_data -gt 0 ]]; then
        log_success "PostgreSQL data verification completed"
        return 0
    else
        log_warning "No data found in any tables"
        return 1
    fi
}

# ================================================================================
# Parse Arguments
# ================================================================================

TIER="${1:-}"
ENVIRONMENT="${2:-}"
MODE="${3:-}"
SKIP_PURGE=false
PURGE_ONLY=false
VERIFY_ONLY=false
SPECIFIC_TABLE=""

# Parse optional flags
shift 3 2>/dev/null || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-purge)
            SKIP_PURGE=true
            shift
            ;;
        --purge-only)
            PURGE_ONLY=true
            shift
            ;;
        --verify-only)
            VERIFY_ONLY=true
            SKIP_PURGE=true
            shift
            ;;
        --table)
            SPECIFIC_TABLE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

if [[ "$TIER" == "-h" ]] || [[ "$TIER" == "--help" ]]; then
    show_help
    exit 0
fi

if [[ -z "$TIER" ]] || [[ -z "$ENVIRONMENT" ]] || [[ -z "$MODE" ]]; then
    log_error "Tier, environment, and mode arguments are required"
    show_help
    exit 1
fi

# Validate mode
if [[ "$MODE" != "graphql" ]] && [[ "$MODE" != "postgres" ]]; then
    log_error "Invalid mode: $MODE. Must be 'graphql' or 'postgres'"
    show_help
    exit 1
fi

# ================================================================================
# Main Logic
# ================================================================================

main() {
    start_timer

    # Initialize logging
    initialize_logging "$TIER" "$ENVIRONMENT" "load_seed_data_${MODE}"

    log_section "Enhanced Seed Data Loading - $TIER Tier ($ENVIRONMENT) [$MODE mode]"

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
    log_info "  Mode: $MODE"
    log_info "  Data Source: $DATA_SOURCE_PATH"

    if [[ "$MODE" == "graphql" ]]; then
        log_info "  GraphQL Endpoint: $GRAPHQL_ENDPOINT"
    else
        log_info "  Database URL: $DATABASE_URL"
    fi

    if [[ -n "$SPECIFIC_TABLE" ]]; then
        log_info "  Target Table: $SPECIFIC_TABLE"
    fi

    # Production confirmation
    if [[ "$ENVIRONMENT" == "production" ]] && [[ "$SKIP_PURGE" == "false" ]] && [[ "$VERIFY_ONLY" == "false" ]] && [[ "$PURGE_ONLY" == "false" ]]; then
        if ! confirm_production_operation "load seed data (including purge) to $TIER database"; then
            exit 0
        fi
    fi

    # Pipeline execution
    local phases_completed=0
    local phases_failed=0

    # Phase 1: Connection Test
    if test_connection "$MODE" "$TIER" "$ENVIRONMENT"; then
        ((phases_completed++))
    else
        ((phases_failed++))
        log_error "Pipeline failed at connection test phase"
        exit 1
    fi

    # Phase 2: Purge (optional)
    if [[ "$SKIP_PURGE" == "false" ]] && [[ "$VERIFY_ONLY" == "false" ]]; then
        if purge_data "$MODE" "$TIER" "$ENVIRONMENT"; then
            ((phases_completed++))
        else
            ((phases_failed++))
            log_error "Pipeline failed at purge phase"
        fi
    fi

    # Exit early if purge-only
    if [[ "$PURGE_ONLY" == "true" ]]; then
        log_section "Purge-only mode completed"
        show_command_summary
        exit $([ $phases_failed -eq 0 ] && echo 0 || echo 1)
    fi

    # Phase 3: Load (optional)
    if [[ "$VERIFY_ONLY" == "false" ]]; then
        if [[ $phases_failed -eq 0 ]] || [[ "$SKIP_PURGE" == "true" ]]; then
            if load_data "$MODE" "$TIER" "$ENVIRONMENT" "$SPECIFIC_TABLE"; then
                ((phases_completed++))
            else
                ((phases_failed++))
                log_error "Pipeline failed at loading phase"
            fi
        else
            log_warning "Skipping load phase due to purge failure"
            ((phases_failed++))
        fi
    fi

    # Phase 4: Verify
    if [[ $phases_failed -eq 0 ]] || [[ "$VERIFY_ONLY" == "true" ]]; then
        if verify_data "$MODE" "$TIER" "$ENVIRONMENT"; then
            ((phases_completed++))
        else
            ((phases_failed++))
            log_error "Pipeline failed at verification phase"
        fi
    else
        log_warning "Skipping verification phase due to previous failures"
        ((phases_failed++))
    fi

    # Final summary
    log_section "Pipeline Summary"

    if [[ $phases_failed -eq 0 ]]; then
        log_success "All pipeline phases completed successfully"
        log_success "Database is ready for use with $MODE mode"
    else
        log_error "Pipeline completed with $phases_failed failed phase(s)"
        log_error "Manual intervention may be required"
    fi

    # Generate detailed log summary report
    generate_log_summary "$TIER" "$ENVIRONMENT" "load_seed_data_${MODE}"

    show_command_summary

    # Exit with appropriate code
    exit $([ $phases_failed -eq 0 ] && echo 0 || echo 1)
}

# Set trap for error handling
trap cleanup_on_error EXIT

# Run main function
main

# Clear trap on success
trap - EXIT