#!/bin/bash

# ================================================================================
# Rebuild CSV Files from Source Data
# ================================================================================
# Converts PostgreSQL dump "Source Data" to CSV files for LazyGourmet imports
# Usage: ./rebuild-csv.sh [output_dir]
# ================================================================================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAZYGOURMET_ROOT="$(dirname "$SCRIPT_DIR")"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Configuration
SOURCE_DATA="$LAZYGOURMET_ROOT/Source Data"
DEFAULT_OUTPUT_DIR="$LAZYGOURMET_ROOT/csv_export"
LAST_EXPORT_DIR="$LAZYGOURMET_ROOT/Last CSV Export"
OUTPUT_DIR="${1:-$DEFAULT_OUTPUT_DIR}"

# Logging functions
log_info() {
    echo -e "${CYAN}ℹ${RESET} $1"
}

log_success() {
    echo -e "${GREEN}✓${RESET} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${RESET} $1"
}

log_error() {
    echo -e "${RED}✗${RESET} $1" >&2
}

log_section() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${BLUE} $1${RESET}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

# ================================================================================
# Help Documentation
# ================================================================================

show_help() {
    echo ""
    echo -e "${BOLD}NAME${RESET}"
    echo "    rebuild-csv.sh - Convert PostgreSQL dump to CSV files"
    echo ""
    echo -e "${BOLD}USAGE${RESET}"
    echo "    ./rebuild-csv.sh [output_dir]"
    echo ""
    echo -e "${BOLD}DESCRIPTION${RESET}"
    echo "    Extracts table data from 'Source Data' PostgreSQL dump"
    echo "    and converts it to CSV files for LazyGourmet imports"
    echo ""
    echo -e "${BOLD}ARGUMENTS${RESET}"
    echo "    output_dir    Directory for CSV output (default: csv_export)"
    echo ""
    echo -e "${BOLD}EXAMPLES${RESET}"
    echo "    Rebuild CSV files to default directory:"
    echo -e "    ${CYAN}./rebuild-csv.sh${RESET}"
    echo ""
    echo "    Rebuild to custom directory:"
    echo -e "    ${CYAN}./rebuild-csv.sh /path/to/output${RESET}"
    echo ""
}

# ================================================================================
# Validation Functions
# ================================================================================

check_requirements() {
    # Check if psql is installed
    if ! command -v psql &> /dev/null; then
        log_error "psql is required but not installed"
        exit 1
    fi

    # Check if Source Data exists
    if [[ ! -f "$SOURCE_DATA" ]]; then
        log_error "Source Data file not found: $SOURCE_DATA"
        exit 1
    fi

    log_success "Requirements checked"
}

# ================================================================================
# PostgreSQL to CSV Conversion
# ================================================================================

setup_temp_database() {
    local temp_db="lazygourmet_temp_$(date +%s)"

    log_info "Creating temporary database: $temp_db"

    # Create temporary database
    createdb "$temp_db" 2>/dev/null || {
        log_error "Failed to create temporary database"
        exit 1
    }

    echo "$temp_db"
}

cleanup_temp_database() {
    local temp_db="$1"

    log_info "Cleaning up temporary database: $temp_db"
    dropdb "$temp_db" 2>/dev/null || true
}

restore_dump_to_temp() {
    local temp_db="$1"

    log_info "Restoring PostgreSQL dump to temporary database..."

    # Restore the dump
    if psql "$temp_db" < "$SOURCE_DATA" > /dev/null 2>&1; then
        log_success "Database restored successfully"
    else
        log_error "Failed to restore database dump"
        cleanup_temp_database "$temp_db"
        exit 1
    fi
}

get_table_list() {
    local temp_db="$1"

    # Get list of tables from the database
    psql -d "$temp_db" -t -c "
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
        ORDER BY tablename;
    " | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'
}

export_table_to_csv() {
    local temp_db="$1"
    local table_name="$2"
    local output_file="$3"

    log_info "Exporting table: $table_name"

    # Export table to CSV with headers
    psql -d "$temp_db" -c "\COPY (SELECT * FROM $table_name) TO STDOUT WITH CSV HEADER" > "$output_file" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        local row_count=$(wc -l < "$output_file" | xargs)
        log_success "Exported $table_name: $((row_count - 1)) rows"
        return 0
    else
        log_warning "Failed to export $table_name"
        return 1
    fi
}

# ================================================================================
# Main Conversion Process
# ================================================================================

main() {
    # Parse arguments
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        show_help
        exit 0
    fi

    log_section "LazyGourmet CSV Rebuild"

    # Check requirements
    check_requirements

    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    log_info "Output directory: $OUTPUT_DIR"

    # Create temporary database
    TEMP_DB=$(setup_temp_database)

    # Set trap to cleanup on exit
    trap "cleanup_temp_database '$TEMP_DB'" EXIT

    # Restore dump to temporary database
    restore_dump_to_temp "$TEMP_DB"

    # Get list of tables
    log_section "Exporting Tables to CSV"

    TABLES=$(get_table_list "$TEMP_DB")

    if [[ -z "$TABLES" ]]; then
        log_error "No tables found in database"
        exit 1
    fi

    # Count tables
    TABLE_COUNT=$(echo "$TABLES" | wc -l | xargs)
    log_info "Found $TABLE_COUNT tables to export"

    # Export each table
    EXPORTED_COUNT=0
    FAILED_COUNT=0

    while IFS= read -r table; do
        if [[ -n "$table" ]]; then
            output_file="$OUTPUT_DIR/${table}.csv"

            if export_table_to_csv "$TEMP_DB" "$table" "$output_file"; then
                ((EXPORTED_COUNT++))
            else
                ((FAILED_COUNT++))
            fi
        fi
    done <<< "$TABLES"

    # Compare with last export if it exists
    if [[ -d "$LAST_EXPORT_DIR" ]]; then
        log_section "Comparing with Last Export"

        for csv_file in "$OUTPUT_DIR"/*.csv; do
            if [[ -f "$csv_file" ]]; then
                filename=$(basename "$csv_file")
                last_file="$LAST_EXPORT_DIR/$filename"

                if [[ -f "$last_file" ]]; then
                    new_count=$(wc -l < "$csv_file" | xargs)
                    old_count=$(wc -l < "$last_file" | xargs)

                    if [[ $new_count -eq $old_count ]]; then
                        log_success "$filename: $((new_count - 1)) rows (unchanged)"
                    else
                        diff=$((new_count - old_count))
                        if [[ $diff -gt 0 ]]; then
                            log_warning "$filename: $((new_count - 1)) rows (+$diff)"
                        else
                            log_warning "$filename: $((new_count - 1)) rows ($diff)"
                        fi
                    fi
                else
                    log_info "$filename: NEW FILE"
                fi
            fi
        done
    fi

    # Summary
    log_section "Export Summary"

    log_info "Total tables found: $TABLE_COUNT"
    log_success "Successfully exported: $EXPORTED_COUNT"

    if [[ $FAILED_COUNT -gt 0 ]]; then
        log_error "Failed exports: $FAILED_COUNT"
    fi

    log_info "CSV files saved to: $OUTPUT_DIR"

    # Cleanup is handled by trap
    log_success "CSV rebuild completed!"
}

# Run main function
main "$@"