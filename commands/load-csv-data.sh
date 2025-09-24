#!/bin/bash

# ================================================================================
# Load CSV Data Command - Upload CSV data to GraphQL API
# ================================================================================
# Loads CSV seed data into the specified tier's GraphQL API
# Usage: ./load-csv-data.sh <tier> <environment> [table_name]
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
    show_help_header "load-csv-data.sh" "Load CSV data into GraphQL API"
    show_help_usage "./load-csv-data.sh <tier> <environment> [table_name]"

    echo -e "${BOLD}ARGUMENTS${RESET}"
    echo "    tier              Target tier (admin, operator, or member)"
    echo "    environment       Target environment (development or production)"
    echo "    table_name        Optional: specific table to load (loads all if omitted)"
    echo ""

    echo -e "${BOLD}DESCRIPTION${RESET}"
    echo "    Loads CSV data from child repositories into GraphQL APIs"
    echo "    Automatically detects CSV files and creates GraphQL mutations"
    echo "    Supports batch uploading and relationship preservation"
    echo "    Can purge existing data before loading (recommended)"
    echo ""

    echo -e "${BOLD}DATA SOURCES${RESET}"
    echo "    Admin:     ../graphql-admin-api/test-data/"
    echo "    Operator:  ../graphql-operator-api/test-data/"
    echo "    Member:    ../graphql-member-api/test-data/"
    echo ""

    echo -e "${BOLD}EXAMPLES${RESET}"
    echo "    Load all admin CSV data:"
    echo -e "    ${CYAN}./load-csv-data.sh admin development${RESET}"
    echo ""
    echo "    Load specific operator table:"
    echo -e "    ${CYAN}./load-csv-data.sh operator development members${RESET}"
    echo ""
    echo "    Load production data (with confirmation):"
    echo -e "    ${CYAN}./load-csv-data.sh admin production${RESET}"
    echo ""
}

# ================================================================================
# CSV to GraphQL Conversion Functions
# ================================================================================

csv_to_graphql_mutation() {
    local csv_file="$1"
    local table_name="$2"
    local mutation_type="$3" # insert or upsert

    # Read CSV header to get column names
    local header=$(head -n 1 "$csv_file")
    local columns=($(echo "$header" | tr ',' ' '))

    # Read CSV data (skip header)
    local data_lines=$(tail -n +2 "$csv_file")

    if [[ -z "$data_lines" ]]; then
        log_warning "No data found in CSV file: $csv_file"
        return 1
    fi

    # Create GraphQL mutation
    local mutation_name="insert_${table_name}"
    if [[ "$mutation_type" == "upsert" ]]; then
        mutation_name="insert_${table_name}_on_conflict"
    fi

    # Start building the mutation
    local mutation="mutation {\n  $mutation_name(\n    objects: ["

    # Process each data line
    local first_record=true
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi

        if [[ "$first_record" == "false" ]]; then
            mutation+=","
        fi

        mutation+="\n      {"

        # Split line by comma and process each value
        IFS=',' read -ra values <<< "$line"
        local first_field=true

        for i in "${!columns[@]}"; do
            local column="${columns[$i]}"
            local value="${values[$i]:-}"

            # Skip empty values
            if [[ -z "$value" ]]; then
                continue
            fi

            if [[ "$first_field" == "false" ]]; then
                mutation+=","
            fi

            # Format value based on type (simple heuristic)
            if [[ "$value" =~ ^[0-9]+$ ]]; then
                # Integer
                mutation+="\n        $column: $value"
            elif [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]]; then
                # Float
                mutation+="\n        $column: $value"
            elif [[ "$value" =~ ^(true|false)$ ]]; then
                # Boolean
                mutation+="\n        $column: $value"
            elif [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
                # Date/timestamp
                mutation+="\n        $column: \"$value\""
            else
                # String - escape quotes
                local escaped_value=$(echo "$value" | sed 's/"/\\"/g')
                mutation+="\n        $column: \"$escaped_value\""
            fi

            first_field=false
        done

        mutation+="\n      }"
        first_record=false
    done <<< "$data_lines"

    mutation+="\n    ]"

    # Add conflict resolution for upsert
    if [[ "$mutation_type" == "upsert" ]]; then
        mutation+="\n    on_conflict: {\n      constraint: ${table_name}_pkey\n      update_columns: ["
        local first_col=true
        for column in "${columns[@]}"; do
            if [[ "$column" != "id" ]]; then
                if [[ "$first_col" == "false" ]]; then
                    mutation+=", "
                fi
                mutation+="$column"
                first_col=false
            fi
        done
        mutation+="]\n    }"
    fi

    mutation+="\n  ) {\n    affected_rows\n    returning {\n      id\n    }\n  }\n}"

    echo -e "$mutation"
}

execute_graphql_mutation() {
    local mutation="$1"
    local endpoint="$2"
    local admin_secret="$3"

    # Create temporary file for mutation
    local temp_file=$(mktemp)
    echo "$mutation" > "$temp_file"

    # Prepare GraphQL request
    local graphql_query=$(jq -n --rawfile query "$temp_file" '{query: $query}')

    # Execute mutation
    local response=$(curl -s \
        -H "x-hasura-admin-secret: $admin_secret" \
        -H "Content-Type: application/json" \
        -d "$graphql_query" \
        "$endpoint" 2>/dev/null)

    # Clean up temp file
    rm -f "$temp_file"

    # Check for errors
    if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
        log_error "GraphQL mutation failed:"
        echo "$response" | jq '.errors' 2>/dev/null || echo "$response"
        return 1
    fi

    # Extract affected rows
    local affected_rows=$(echo "$response" | jq -r '.data | to_entries[0].value.affected_rows // 0' 2>/dev/null)
    echo "$affected_rows"

    return 0
}

# ================================================================================
# Data Loading Functions
# ================================================================================

load_csv_file() {
    local csv_file="$1"
    local table_name="$2"
    local endpoint="$3"
    local admin_secret="$4"
    local use_upsert="${5:-false}"

    log_step "Loading CSV file: $(basename "$csv_file")"

    # Validate CSV file
    if ! validate_csv_file "$csv_file"; then
        return 1
    fi

    local record_count=$(get_csv_record_count "$csv_file")
    log_info "Found $record_count records to load"

    if [[ $record_count -eq 0 ]]; then
        log_warning "No records to load"
        return 0
    fi

    # Generate GraphQL mutation
    local mutation_type="insert"
    if [[ "$use_upsert" == "true" ]]; then
        mutation_type="upsert"
    fi

    log_debug "Generating GraphQL mutation for $table_name"
    local mutation=$(csv_to_graphql_mutation "$csv_file" "$table_name" "$mutation_type")

    if [[ -z "$mutation" ]]; then
        log_error "Failed to generate GraphQL mutation"
        return 1
    fi

    # Execute mutation
    log_debug "Executing GraphQL mutation"
    local affected_rows=$(execute_graphql_mutation "$mutation" "$endpoint" "$admin_secret")

    if [[ $? -eq 0 ]]; then
        log_success "Loaded $affected_rows records into $table_name"
        return 0
    else
        log_error "Failed to load data into $table_name"
        return 1
    fi
}

load_table_data() {
    local data_dir="$1"
    local table_pattern="$2"
    local endpoint="$3"
    local admin_secret="$4"
    local use_upsert="${5:-false}"

    log_section "Loading Table Data: $table_pattern"

    # Find CSV files matching the pattern
    local csv_files=($(find "$data_dir" -name "*${table_pattern}*.csv" | sort))

    if [[ ${#csv_files[@]} -eq 0 ]]; then
        log_warning "No CSV files found matching pattern: $table_pattern"
        return 1
    fi

    local total_loaded=0
    local files_processed=0

    for csv_file in "${csv_files[@]}"; do
        # Extract table name from filename
        local filename=$(basename "$csv_file" .csv)
        local table_name=$(echo "$filename" | sed 's/^[0-9][0-9]_//' | sed 's/^[0-9]_//')

        if load_csv_file "$csv_file" "$table_name" "$endpoint" "$admin_secret" "$use_upsert"; then
            ((files_processed++))
            local record_count=$(get_csv_record_count "$csv_file")
            ((total_loaded += record_count))
        fi
    done

    log_info "Processed $files_processed files, loaded $total_loaded total records"
    return 0
}

# ================================================================================
# Parse Arguments
# ================================================================================

TIER="${1:-}"
ENVIRONMENT="${2:-}"
TABLE_NAME="${3:-}"

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

    log_section "Loading CSV Data - $TIER Tier ($ENVIRONMENT)"

    # Configure tier settings
    configure_tier "$TIER" || exit 1

    # Validate environment
    validate_environment_parameter "$ENVIRONMENT" || exit 1

    # Production confirmation
    if [[ "$ENVIRONMENT" == "production" ]]; then
        if ! confirm_production_operation "load CSV data into $TIER GraphQL API"; then
            exit 0
        fi
    fi

    # Test GraphQL connection
    if ! test_graphql_connection "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET"; then
        log_error "Cannot connect to GraphQL endpoint: $GRAPHQL_ENDPOINT"
        log_error "Please ensure the GraphQL server is running"
        exit 1
    fi

    # Check if data source directory exists
    if [[ ! -d "$DATA_SOURCE_PATH" ]]; then
        log_error "Data source directory not found: $DATA_SOURCE_PATH"
        log_error "Please ensure the data source repository is available"
        exit 1
    fi

    # Load data
    if [[ -n "$TABLE_NAME" ]]; then
        # Load specific table
        load_table_data "$DATA_SOURCE_PATH" "$TABLE_NAME" "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET" "false"
    else
        # Load all tables (process directories in order)
        log_section "Loading All CSV Data"

        local total_files=0
        local successful_files=0

        # Find all directories with CSV files
        for data_subdir in $(find "$DATA_SOURCE_PATH" -type d | sort); do
            if [[ -n "$(find "$data_subdir" -maxdepth 1 -name "*.csv" 2>/dev/null)" ]]; then
                local subdir_name=$(basename "$data_subdir")
                log_step "Processing directory: $subdir_name"

                # Load all CSV files in this directory
                for csv_file in $(find "$data_subdir" -maxdepth 1 -name "*.csv" | sort); do
                    ((total_files++))

                    # Extract table name from filename
                    local filename=$(basename "$csv_file" .csv)
                    local table_name=$(echo "$filename" | sed 's/^[0-9][0-9]_//' | sed 's/^[0-9]_//')

                    if load_csv_file "$csv_file" "$table_name" "$GRAPHQL_ENDPOINT" "$GRAPHQL_ADMIN_SECRET" "false"; then
                        ((successful_files++))
                    fi
                done
            fi
        done

        log_section "Data Loading Summary"
        log_info "Total files processed: $total_files"
        log_info "Successful loads: $successful_files"

        if [[ $successful_files -eq $total_files ]]; then
            log_success "All CSV files loaded successfully"
        else
            log_warning "Some files failed to load ($((total_files - successful_files)) failures)"
        fi
    fi

    show_command_summary
}

# Set trap for error handling
trap cleanup_on_error EXIT

# Run main function
main

# Clear trap on success
trap - EXIT