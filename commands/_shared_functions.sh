#!/bin/bash

# ============================================================================
# SEED DATA FUNCTIONS
# Community Connect Tech - Seed Data Loading System
# ============================================================================
# Standardized CSV data loading functions for GraphQL APIs across all tiers
# Supports admin, operator, and member data sources
#
# Usage: configure_tier <admin|operator|member>
# ============================================================================

# Global constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SHARED_SEED_ROOT="$(dirname "$SCRIPT_DIR")"

# ANSI Color codes for consistent output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m' # Reset formatting

# Error tracking
COMMAND_ERRORS=0
COMMAND_WARNINGS=0

# Timer for performance tracking
START_TIME=""

# ============================================================================
# TIER CONFIGURATION SYSTEM
# ============================================================================

configure_tier() {
    local tier="$1"

    case "$tier" in
        "admin")
            GRAPHQL_ENDPOINT="http://localhost:8101/v1/graphql"
            GRAPHQL_ADMIN_SECRET="CCTech2024Admin"
            DATA_SOURCE_PATH="../graphql-admin-api/test-data"
            DB_TIER_DATABASE="admin_database"
            DB_TIER_PORT="7101"
            DB_TIER_CONTAINER="admin-postgres"
            DB_TIER_USER="admin"
            DB_TIER_PASSWORD="CCTech2024Admin!"
            ;;
        "operator")
            GRAPHQL_ENDPOINT="http://localhost:8102/v1/graphql"
            GRAPHQL_ADMIN_SECRET="CCTech2024Operator"
            DATA_SOURCE_PATH="../graphql-operator-api/test-data"
            DB_TIER_DATABASE="operator_database"
            DB_TIER_PORT="7102"
            DB_TIER_CONTAINER="operator-postgres"
            DB_TIER_USER="operator"
            DB_TIER_PASSWORD="CCTech2024Operator!"
            ;;
        "member")
            GRAPHQL_ENDPOINT="http://localhost:8103/v1/graphql"
            GRAPHQL_ADMIN_SECRET="CCTech2024Member"
            DATA_SOURCE_PATH="../graphql-member-api/test-data"
            DB_TIER_DATABASE="member_database"
            DB_TIER_PORT="7103"
            DB_TIER_CONTAINER="member-postgres"
            DB_TIER_USER="member"
            DB_TIER_PASSWORD="CCTech2024Member!"
            ;;
        *)
            log_error "Invalid tier: $tier. Must be admin, operator, or member"
            return 1
            ;;
    esac

    # Export all variables for use by calling scripts
    export GRAPHQL_ENDPOINT GRAPHQL_ADMIN_SECRET DATA_SOURCE_PATH DB_TIER_DATABASE
    export DB_TIER_PORT DB_TIER_CONTAINER DB_TIER_USER DB_TIER_PASSWORD

    log_debug "Configured tier: $tier"
    log_debug "GraphQL Endpoint: $GRAPHQL_ENDPOINT"
    log_debug "Database: $DB_TIER_DATABASE at localhost:$DB_TIER_PORT"
    log_debug "Data Source: $DATA_SOURCE_PATH"

    return 0
}

# ============================================================================
# LOGGING SYSTEM WITH FILE OUTPUT
# ============================================================================

# Initialize logging
LOG_DIR=""
LOG_FILE=""
LOG_ENABLED=true
OPERATION_SUMMARY=""

initialize_logging() {
    local tier="$1"
    local environment="$2"
    local operation="${3:-operation}"

    # Create logs directory structure
    LOG_DIR="$SHARED_SEED_ROOT/logs"
    mkdir -p "$LOG_DIR"

    # Create timestamped log file
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    LOG_FILE="$LOG_DIR/${tier}_${environment}_${operation}_${timestamp}.log"

    # Initialize log file with header
    {
        echo "═══════════════════════════════════════════════════════════════════════"
        echo " SEED DATA OPERATION LOG"
        echo "═══════════════════════════════════════════════════════════════════════"
        echo " Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo " Tier: $tier"
        echo " Environment: $environment"
        echo " Operation: $operation"
        echo " User: $(whoami)"
        echo " Host: $(hostname)"
        echo "═══════════════════════════════════════════════════════════════════════"
        echo ""
    } > "$LOG_FILE"

    # Initialize operation summary
    OPERATION_SUMMARY="$LOG_DIR/${tier}_${environment}_${operation}_${timestamp}_summary.json"
    echo '{"operations": [], "tables": {}, "errors": [], "warnings": []}' > "$OPERATION_SUMMARY"

    log_info "Logging initialized: $LOG_FILE"
}

# Write to both console and log file
write_log() {
    local level="$1"
    local message="$2"
    local console_output="$3"

    # Write to log file
    if [[ -n "$LOG_FILE" ]] && [[ -f "$LOG_FILE" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
    fi

    # Write to console if requested
    if [[ "$console_output" != "false" ]]; then
        case "$level" in
            "DEBUG")
                if [[ "${DEBUG:-false}" == "true" ]]; then
                    echo -e "${CYAN}[DEBUG]${RESET} $message" >&2
                fi
                ;;
            "INFO")
                echo -e "${BLUE}[INFO]${RESET} $message" >&2
                ;;
            "STEP")
                echo -e "${YELLOW}[STEP]${RESET} $message" >&2
                ;;
            "SUCCESS")
                echo -e "${GREEN}[SUCCESS]${RESET} $message" >&2
                ;;
            "WARNING")
                echo -e "${YELLOW}[WARNING]${RESET} $message" >&2
                ;;
            "ERROR")
                echo -e "${RED}[ERROR]${RESET} $message" >&2
                ;;
            "SECTION")
                echo ""
                echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                echo -e "${BOLD}${MAGENTA} $message${RESET}"
                echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                echo ""
                ;;
        esac
    fi
}

# Log table operation
log_table_operation() {
    local table_name="$1"
    local operation="$2"
    local record_count="$3"
    local status="$4"
    local error_msg="${5:-}"

    # Log to file
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [TABLE] $table_name: $operation $record_count records - $status" >> "$LOG_FILE"
        if [[ -n "$error_msg" ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [TABLE_ERROR] $table_name: $error_msg" >> "$LOG_FILE"
        fi
    fi

    # Update JSON summary
    if [[ -n "$OPERATION_SUMMARY" ]] && [[ -f "$OPERATION_SUMMARY" ]]; then
        local temp_json=$(mktemp)
        jq --arg table "$table_name" \
           --arg op "$operation" \
           --arg count "$record_count" \
           --arg status "$status" \
           --arg error "$error_msg" \
           '.tables[$table] = {
               "operation": $op,
               "record_count": ($count | tonumber),
               "status": $status,
               "error": $error,
               "timestamp": now | todate
           }' "$OPERATION_SUMMARY" > "$temp_json"
        mv "$temp_json" "$OPERATION_SUMMARY"
    fi
}

# Timer functions
start_timer() {
    START_TIME=$(date +%s)
}

get_elapsed_time() {
    if [[ -n "$START_TIME" ]]; then
        local end_time=$(date +%s)
        local elapsed=$((end_time - START_TIME))
        echo "${elapsed}s"
    else
        echo "0s"
    fi
}

# Enhanced logging functions that use write_log
log_debug() {
    write_log "DEBUG" "$1" "true"
}

log_info() {
    write_log "INFO" "$1" "true"
}

log_step() {
    write_log "STEP" "$1" "true"
}

log_success() {
    write_log "SUCCESS" "$1" "true"
}

log_warning() {
    write_log "WARNING" "$1" "true"
    ((COMMAND_WARNINGS++))

    # Add to JSON summary
    if [[ -n "$OPERATION_SUMMARY" ]] && [[ -f "$OPERATION_SUMMARY" ]]; then
        local temp_json=$(mktemp)
        jq --arg warning "$1" '.warnings += [$warning]' "$OPERATION_SUMMARY" > "$temp_json"
        mv "$temp_json" "$OPERATION_SUMMARY"
    fi
}

log_error() {
    write_log "ERROR" "$1" "true"
    ((COMMAND_ERRORS++))

    # Add to JSON summary
    if [[ -n "$OPERATION_SUMMARY" ]] && [[ -f "$OPERATION_SUMMARY" ]]; then
        local temp_json=$(mktemp)
        jq --arg error "$1" '.errors += [$error]' "$OPERATION_SUMMARY" > "$temp_json"
        mv "$temp_json" "$OPERATION_SUMMARY"
    fi
}

log_section() {
    write_log "SECTION" "$1" "true"
}

# Generate final log summary
generate_log_summary() {
    local tier="$1"
    local environment="$2"
    local operation="$3"

    if [[ ! -f "$OPERATION_SUMMARY" ]]; then
        return
    fi

    log_section "Operation Summary Report"

    # Read summary data
    local total_tables=$(jq '.tables | length' "$OPERATION_SUMMARY")
    local successful_tables=$(jq '[.tables[] | select(.status == "success")] | length' "$OPERATION_SUMMARY")
    local failed_tables=$(jq '[.tables[] | select(.status == "error")] | length' "$OPERATION_SUMMARY")
    local total_records=$(jq '[.tables[] | .record_count] | add // 0' "$OPERATION_SUMMARY")
    local error_count=$(jq '.errors | length' "$OPERATION_SUMMARY")
    local warning_count=$(jq '.warnings | length' "$OPERATION_SUMMARY")

    # Display summary
    echo "╔═══════════════════════════════════════════════════════════════════╗" | tee -a "$LOG_FILE"
    echo "║                    OPERATION SUMMARY REPORT                       ║" | tee -a "$LOG_FILE"
    echo "╠═══════════════════════════════════════════════════════════════════╣" | tee -a "$LOG_FILE"
    printf "║ %-30s %-36s ║\n" "Tier:" "$tier" | tee -a "$LOG_FILE"
    printf "║ %-30s %-36s ║\n" "Environment:" "$environment" | tee -a "$LOG_FILE"
    printf "║ %-30s %-36s ║\n" "Operation:" "$operation" | tee -a "$LOG_FILE"
    printf "║ %-30s %-36s ║\n" "Timestamp:" "$(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
    printf "║ %-30s %-36s ║\n" "Duration:" "$(get_elapsed_time)" | tee -a "$LOG_FILE"
    echo "╠═══════════════════════════════════════════════════════════════════╣" | tee -a "$LOG_FILE"
    printf "║ %-30s %-36s ║\n" "Total Tables Processed:" "$total_tables" | tee -a "$LOG_FILE"
    printf "║ %-30s %-36s ║\n" "Successful Tables:" "$successful_tables" | tee -a "$LOG_FILE"
    printf "║ %-30s %-36s ║\n" "Failed Tables:" "$failed_tables" | tee -a "$LOG_FILE"
    printf "║ %-30s %-36s ║\n" "Total Records:" "$total_records" | tee -a "$LOG_FILE"
    printf "║ %-30s %-36s ║\n" "Errors:" "$error_count" | tee -a "$LOG_FILE"
    printf "║ %-30s %-36s ║\n" "Warnings:" "$warning_count" | tee -a "$LOG_FILE"
    echo "╠═══════════════════════════════════════════════════════════════════╣" | tee -a "$LOG_FILE"
    printf "║ %-30s %-36s ║\n" "Log File:" "$(basename $LOG_FILE)" | tee -a "$LOG_FILE"
    printf "║ %-30s %-36s ║\n" "Summary File:" "$(basename $OPERATION_SUMMARY)" | tee -a "$LOG_FILE"
    echo "╚═══════════════════════════════════════════════════════════════════╝" | tee -a "$LOG_FILE"

    # Table details
    if [[ $total_tables -gt 0 ]]; then
        echo "" | tee -a "$LOG_FILE"
        echo "Table Details:" | tee -a "$LOG_FILE"
        echo "─────────────────────────────────────────────────────────────────" | tee -a "$LOG_FILE"
        printf "%-30s %10s %10s %10s\n" "Table Name" "Records" "Status" "Operation" | tee -a "$LOG_FILE"
        echo "─────────────────────────────────────────────────────────────────" | tee -a "$LOG_FILE"

        jq -r '.tables | to_entries[] | "\(.key)|\(.value.record_count)|\(.value.status)|\(.value.operation)"' "$OPERATION_SUMMARY" | \
        while IFS='|' read -r table records status op; do
            printf "%-30s %10s %10s %10s\n" "$table" "$records" "$status" "$op" | tee -a "$LOG_FILE"
        done
    fi

    # Show errors if any
    if [[ $error_count -gt 0 ]]; then
        echo "" | tee -a "$LOG_FILE"
        echo "Errors Encountered:" | tee -a "$LOG_FILE"
        echo "─────────────────────────────────────────────────────────────────" | tee -a "$LOG_FILE"
        jq -r '.errors[]' "$OPERATION_SUMMARY" | while read -r error; do
            echo "  • $error" | tee -a "$LOG_FILE"
        done
    fi

    # Show warnings if any
    if [[ $warning_count -gt 0 ]]; then
        echo "" | tee -a "$LOG_FILE"
        echo "Warnings:" | tee -a "$LOG_FILE"
        echo "─────────────────────────────────────────────────────────────────" | tee -a "$LOG_FILE"
        jq -r '.warnings[]' "$OPERATION_SUMMARY" | while read -r warning; do
            echo "  • $warning" | tee -a "$LOG_FILE"
        done
    fi

    echo "" | tee -a "$LOG_FILE"

    if [[ $failed_tables -eq 0 ]] && [[ $error_count -eq 0 ]]; then
        log_success "Operation completed successfully!"
    else
        log_error "Operation completed with errors. Review log for details."
    fi
}

# ============================================================================
# HELP SYSTEM
# ============================================================================

show_help_header() {
    local script_name="$1"
    local description="$2"

    echo -e "${BOLD}${CYAN}$script_name${RESET} - $description"
    echo -e "${CYAN}Community Connect Tech - Seed Data Loading System${RESET}"
    echo ""
}

show_help_usage() {
    local usage="$1"
    echo -e "${BOLD}USAGE${RESET}"
    echo "    $usage"
    echo ""
}

# ============================================================================
# ENVIRONMENT CONFIGURATION FUNCTIONS
# ============================================================================

load_environment() {
    local environment="$1"

    case "$environment" in
        "development")
            DATABASE_URL="postgresql://$DB_TIER_USER:$DB_TIER_PASSWORD@localhost:$DB_TIER_PORT/$DB_TIER_DATABASE"
            ;;
        "production")
            # Production URLs would come from environment variables or config files
            if [[ -z "${PROD_DATABASE_URL:-}" ]]; then
                log_error "Production database URL not configured"
                return 1
            fi
            DATABASE_URL="$PROD_DATABASE_URL"
            ;;
        *)
            log_error "Invalid environment: $environment. Must be development or production"
            return 1
            ;;
    esac

    export DATABASE_URL
    return 0
}

# ============================================================================
# POSTGRESQL DATABASE FUNCTIONS
# ============================================================================

test_postgres_connection() {
    local database_url="$1"

    log_step "Testing PostgreSQL connection..."

    if psql "$database_url" -c "SELECT 1;" >/dev/null 2>&1; then
        log_success "PostgreSQL database is accessible"
        return 0
    else
        log_error "PostgreSQL database is not accessible"
        log_error "Database URL: $database_url"
        return 1
    fi
}

get_all_user_tables() {
    local database_url="$1"

    # Get all user tables (excluding system schemas)
    psql "$database_url" -t -c "
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema NOT IN ('information_schema', 'pg_catalog', 'hdb_catalog', 'hdb_views')
        AND table_type = 'BASE TABLE'
        ORDER BY table_name;
    " 2>/dev/null | xargs -n1 | grep -v '^$'
}

count_table_records_postgres() {
    local table_name="$1"
    local database_url="$2"

    local count=$(psql "$database_url" -t -c "SELECT COUNT(*) FROM \"$table_name\";" 2>/dev/null | xargs)
    echo "${count:-0}"
}

purge_table_postgres() {
    local table_name="$1"
    local database_url="$2"

    log_step "Purging table: $table_name"

    # Get record count before purging
    local record_count=$(count_table_records_postgres "$table_name" "$database_url")

    # Use TRUNCATE CASCADE to handle foreign key constraints
    if psql "$database_url" -c "TRUNCATE TABLE \"$table_name\" CASCADE;" >/dev/null 2>&1; then
        log_success "Purged $record_count records from table: $table_name"
        log_table_operation "$table_name" "PURGE_POSTGRES" "$record_count" "success" ""
        return 0
    else
        local error_msg=$(psql "$database_url" -c "TRUNCATE TABLE \"$table_name\" CASCADE;" 2>&1 | head -n 1)
        log_warning "Failed to purge table: $table_name - $error_msg"
        log_table_operation "$table_name" "PURGE_POSTGRES" "$record_count" "error" "$error_msg"
        return 1
    fi
}

purge_all_tables_postgres() {
    local database_url="$1"

    log_step "Discovering tables to purge..."
    local tables=$(get_all_user_tables "$database_url")

    if [[ -z "$tables" ]]; then
        log_warning "No user tables found to purge"
        return 0
    fi

    local table_count=$(echo "$tables" | wc -l | xargs)
    local total_records_purged=0
    log_info "Found $table_count tables to purge"

    # Count total records before purging
    while IFS= read -r table; do
        if [[ -n "$table" ]]; then
            local count=$(count_table_records_postgres "$table" "$database_url")
            ((total_records_purged += count))
        fi
    done <<< "$tables"

    log_info "Total records to purge: $total_records_purged"

    # Purge all tables at once with CASCADE to handle dependencies
    log_step "Purging all tables..."
    local table_list=$(echo "$tables" | tr '\n' ',' | sed 's/,$//')

    if psql "$database_url" -c "TRUNCATE TABLE $table_list CASCADE;" >/dev/null 2>&1; then
        log_success "Successfully purged all $table_count tables ($total_records_purged total records)"

        # Log each table as purged
        while IFS= read -r table; do
            if [[ -n "$table" ]]; then
                log_table_operation "$table" "PURGE_POSTGRES_BULK" "0" "success" ""
            fi
        done <<< "$tables"

        return 0
    else
        log_error "Failed to purge tables"
        return 1
    fi
}

# ============================================================================
# CSV TO SQL CONVERSION FUNCTIONS
# ============================================================================

csv_to_sql_insert() {
    local csv_file="$1"
    local table_name="$2"

    if ! validate_csv_file "$csv_file"; then
        return 1
    fi

    # Read CSV header
    local header=$(head -n 1 "$csv_file")
    local columns=($(echo "$header" | tr ',' ' '))

    # Create column list for INSERT
    local column_list=$(IFS=','; echo "${columns[*]}")

    # Read CSV data (skip header) and convert to SQL INSERT statements
    local sql_file=$(mktemp)

    echo "BEGIN;" > "$sql_file"

    tail -n +2 "$csv_file" | while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi

        # Split line by comma and process each value
        IFS=',' read -ra values <<< "$line"

        # Build VALUES clause
        local values_clause=""
        local first_value=true

        for i in "${!columns[@]}"; do
            local value="${values[$i]:-}"

            if [[ "$first_value" == "false" ]]; then
                values_clause+=", "
            fi

            # Handle different data types
            if [[ -z "$value" ]]; then
                values_clause+="NULL"
            elif [[ "$value" =~ ^[0-9]+$ ]]; then
                # Integer
                values_clause+="$value"
            elif [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]]; then
                # Float
                values_clause+="$value"
            elif [[ "$value" =~ ^(true|false)$ ]]; then
                # Boolean
                values_clause+="$value"
            else
                # String - escape single quotes
                local escaped_value=$(echo "$value" | sed "s/'/''/g")
                values_clause+="'$escaped_value'"
            fi

            first_value=false
        done

        echo "INSERT INTO \"$table_name\" ($column_list) VALUES ($values_clause);" >> "$sql_file"
    done

    echo "COMMIT;" >> "$sql_file"
    echo "$sql_file"
}

load_csv_to_postgres() {
    local csv_file="$1"
    local table_name="$2"
    local database_url="$3"

    log_step "Loading CSV file: $(basename "$csv_file") -> $table_name"

    local record_count=$(get_csv_record_count "$csv_file")
    log_info "Found $record_count records to load"

    if [[ $record_count -eq 0 ]]; then
        log_warning "No records to load for table $table_name"
        log_table_operation "$table_name" "LOAD_POSTGRES" "0" "warning" "No records in CSV file"
        return 0
    fi

    # Convert CSV to SQL
    local sql_file=$(csv_to_sql_insert "$csv_file" "$table_name")

    if [[ ! -f "$sql_file" ]]; then
        log_error "Failed to convert CSV to SQL for table $table_name"
        log_table_operation "$table_name" "LOAD_POSTGRES" "$record_count" "error" "CSV to SQL conversion failed"
        return 1
    fi

    # Execute SQL
    if psql "$database_url" -f "$sql_file" >/dev/null 2>&1; then
        log_success "Loaded $record_count records into $table_name"
        log_table_operation "$table_name" "LOAD_POSTGRES" "$record_count" "success" ""
        rm -f "$sql_file"
        return 0
    else
        local error_msg=$(psql "$database_url" -f "$sql_file" 2>&1 | head -n 1)
        log_error "Failed to load data into $table_name: $error_msg"
        log_table_operation "$table_name" "LOAD_POSTGRES" "$record_count" "error" "$error_msg"
        rm -f "$sql_file"
        return 1
    fi
}

# ============================================================================
# GRAPHQL API FUNCTIONS
# ============================================================================

test_graphql_connection() {
    local endpoint="$1"
    local admin_secret="$2"

    log_step "Testing GraphQL connection to $endpoint"

    local response=$(curl -s -H "x-hasura-admin-secret: $admin_secret" \
        -H "Content-Type: application/json" \
        -d '{"query": "{ __schema { queryType { name } } }"}' \
        "$endpoint" 2>/dev/null)

    if echo "$response" | grep -q '"queryType"'; then
        log_success "GraphQL endpoint is accessible"
        return 0
    else
        log_error "GraphQL endpoint is not accessible"
        log_error "Response: $response"
        return 1
    fi
}

# ============================================================================
# DATA VALIDATION FUNCTIONS
# ============================================================================

validate_csv_file() {
    local csv_file="$1"

    if [[ ! -f "$csv_file" ]]; then
        log_error "CSV file not found: $csv_file"
        return 1
    fi

    # Check if file has content
    if [[ ! -s "$csv_file" ]]; then
        log_error "CSV file is empty: $csv_file"
        return 1
    fi

    # Check if file has header
    local header_count=$(head -n 1 "$csv_file" | tr ',' '\n' | wc -l)
    if [[ $header_count -lt 1 ]]; then
        log_error "CSV file appears to have no header: $csv_file"
        return 1
    fi

    log_debug "CSV file validated: $csv_file ($header_count columns)"
    return 0
}

get_csv_record_count() {
    local csv_file="$1"

    if [[ ! -f "$csv_file" ]]; then
        echo "0"
        return
    fi

    # Count lines excluding header
    local count=$(tail -n +2 "$csv_file" | wc -l | xargs)
    echo "$count"
}

# ============================================================================
# CLEANUP AND ERROR HANDLING
# ============================================================================

cleanup_on_error() {
    if [[ $? -ne 0 ]]; then
        log_error "Command failed with errors"

        if [[ $COMMAND_ERRORS -gt 0 ]]; then
            log_error "Total errors: $COMMAND_ERRORS"
        fi

        if [[ $COMMAND_WARNINGS -gt 0 ]]; then
            log_warning "Total warnings: $COMMAND_WARNINGS"
        fi
    fi
}

show_command_summary() {
    local elapsed=$(get_elapsed_time)

    echo ""
    log_section "Command Summary"

    if [[ $COMMAND_ERRORS -eq 0 ]]; then
        log_success "Command completed successfully in $elapsed"
    else
        log_error "Command completed with $COMMAND_ERRORS error(s) in $elapsed"
    fi

    if [[ $COMMAND_WARNINGS -gt 0 ]]; then
        log_warning "Total warnings: $COMMAND_WARNINGS"
    fi
}

# ============================================================================
# ENVIRONMENT VALIDATION
# ============================================================================

validate_environment_parameter() {
    local environment="$1"

    if [[ "$environment" != "development" ]] && [[ "$environment" != "production" ]]; then
        log_error "Invalid environment: $environment. Must be 'development' or 'production'"
        return 1
    fi

    return 0
}

confirm_production_operation() {
    local operation="$1"

    echo ""
    log_warning "Production Operation Confirmation"
    echo -e "${YELLOW}You are about to $operation in PRODUCTION.${RESET}"
    echo -e "${YELLOW}This operation cannot be undone.${RESET}"
    echo ""
    read -p "Type 'CONFIRM' to proceed: " confirmation

    if [[ "$confirmation" == "CONFIRM" ]]; then
        log_info "Production operation confirmed"
        return 0
    else
        log_info "Production operation cancelled"
        return 1
    fi
}