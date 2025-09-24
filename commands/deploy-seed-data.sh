#!/bin/bash

# ================================================================================
# Deploy Seed Data Command - Complete CSV data deployment pipeline
# ================================================================================
# Full pipeline: purge existing data, load CSV data, verify results
# Usage: ./deploy-seed-data.sh <tier> <environment> [--skip-purge]
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
    show_help_header "deploy-seed-data.sh" "Complete CSV data deployment pipeline"
    show_help_usage "./deploy-seed-data.sh <tier> <environment> [--skip-purge]"

    echo -e "${BOLD}ARGUMENTS${RESET}"
    echo "    tier              Target tier (admin, operator, or member)"
    echo "    environment       Target environment (development or production)"
    echo ""

    echo -e "${BOLD}OPTIONS${RESET}"
    echo "    --skip-purge      Skip the data purge step (append to existing data)"
    echo "    --verify-only     Only run verification, skip purge and load"
    echo ""

    echo -e "${BOLD}DESCRIPTION${RESET}"
    echo "    Complete deployment pipeline for CSV seed data:"
    echo "    1. Purge existing data (unless --skip-purge specified)"
    echo "    2. Load CSV data from source repositories"
    echo "    3. Verify data integrity and accessibility"
    echo "    4. Generate deployment report"
    echo ""

    echo -e "${BOLD}PIPELINE STEPS${RESET}"
    echo "    Phase 1: Data Purge (optional)"
    echo "      - Connect to GraphQL endpoint"
    echo "      - Remove all existing data"
    echo "      - Preserve schema and relationships"
    echo ""
    echo "    Phase 2: Data Loading"
    echo "      - Load CSV files in dependency order"
    echo "      - Handle foreign key relationships"
    echo "      - Track loading progress and errors"
    echo ""
    echo "    Phase 3: Verification"
    echo "      - Verify record counts"
    echo "      - Test data accessibility"
    echo "      - Compare with source data"
    echo ""

    echo -e "${BOLD}EXAMPLES${RESET}"
    echo "    Full deployment (purge + load + verify):"
    echo -e "    ${CYAN}./deploy-seed-data.sh admin development${RESET}"
    echo ""
    echo "    Append data without purging:"
    echo -e "    ${CYAN}./deploy-seed-data.sh operator development --skip-purge${RESET}"
    echo ""
    echo "    Verify existing data only:"
    echo -e "    ${CYAN}./deploy-seed-data.sh admin production --verify-only${RESET}"
    echo ""
}

# ================================================================================
# Pipeline Functions
# ================================================================================

run_purge_phase() {
    local tier="$1"
    local environment="$2"

    log_section "Phase 1: Data Purge"

    local purge_script="$COMMANDS_DIR/purge-data.sh"

    if [[ ! -x "$purge_script" ]]; then
        log_error "Purge script not found or not executable: $purge_script"
        return 1
    fi

    log_step "Executing data purge..."

    if "$purge_script" "$tier" "$environment"; then
        log_success "Data purge completed successfully"
        return 0
    else
        log_error "Data purge failed"
        return 1
    fi
}

run_load_phase() {
    local tier="$1"
    local environment="$2"

    log_section "Phase 2: Data Loading"

    local load_script="$COMMANDS_DIR/load-csv-data.sh"

    if [[ ! -x "$load_script" ]]; then
        log_error "Load script not found or not executable: $load_script"
        return 1
    fi

    log_step "Executing CSV data loading..."

    if "$load_script" "$tier" "$environment"; then
        log_success "Data loading completed successfully"
        return 0
    else
        log_error "Data loading failed"
        return 1
    fi
}

run_verify_phase() {
    local tier="$1"
    local environment="$2"

    log_section "Phase 3: Data Verification"

    local verify_script="$COMMANDS_DIR/verify-data.sh"

    if [[ ! -x "$verify_script" ]]; then
        log_error "Verify script not found or not executable: $verify_script"
        return 1
    fi

    log_step "Executing data verification..."

    if "$verify_script" "$tier" "$environment"; then
        log_success "Data verification completed successfully"
        return 0
    else
        log_error "Data verification failed"
        return 1
    fi
}

generate_deployment_report() {
    local tier="$1"
    local environment="$2"
    local skip_purge="$3"
    local verify_only="$4"
    local phases_completed="$5"
    local phases_failed="$6"

    log_section "Deployment Report"

    echo ""
    echo -e "${BOLD}Deployment Summary${RESET}"
    echo "  Tier: $tier"
    echo "  Environment: $environment"
    echo "  Timestamp: $(date)"
    echo "  Pipeline Mode: $([ "$verify_only" == "true" ] && echo "Verify Only" || ([ "$skip_purge" == "true" ] && echo "Load + Verify" || echo "Full Pipeline"))"
    echo ""

    echo -e "${BOLD}Pipeline Results${RESET}"

    if [[ "$verify_only" == "true" ]]; then
        echo "  Data Purge: SKIPPED"
        echo "  Data Loading: SKIPPED"
    else
        if [[ "$skip_purge" == "true" ]]; then
            echo "  Data Purge: SKIPPED"
        else
            echo "  Data Purge: $([ "$phases_completed" -ge 1 ] && echo "COMPLETED" || echo "FAILED")"
        fi
        echo "  Data Loading: $([ "$phases_completed" -ge 2 ] && echo "COMPLETED" || echo "FAILED")"
    fi

    echo "  Data Verification: $([ "$phases_completed" -ge 3 ] && echo "COMPLETED" || echo "FAILED")"
    echo ""

    if [[ $phases_failed -eq 0 ]]; then
        log_success "Deployment completed successfully - all phases passed"
        echo ""
        echo -e "${GREEN}✓ Database is ready for use${RESET}"
        echo -e "${GREEN}✓ Data is accessible via GraphQL API${RESET}"
        echo -e "${GREEN}✓ All integrity checks passed${RESET}"
    else
        log_error "Deployment completed with $phases_failed failed phase(s)"
        echo ""
        echo -e "${RED}✗ Some deployment phases failed${RESET}"
        echo -e "${RED}✗ Database may not be in desired state${RESET}"
        echo -e "${RED}✗ Manual intervention may be required${RESET}"
    fi

    echo ""
}

# ================================================================================
# Parse Arguments
# ================================================================================

TIER="${1:-}"
ENVIRONMENT="${2:-}"
SKIP_PURGE=false
VERIFY_ONLY=false

# Parse optional flags
shift 2 2>/dev/null || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-purge)
            SKIP_PURGE=true
            shift
            ;;
        --verify-only)
            VERIFY_ONLY=true
            SKIP_PURGE=true
            shift
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

    log_section "Seed Data Deployment Pipeline - $TIER Tier ($ENVIRONMENT)"

    # Configure tier settings
    configure_tier "$TIER" || exit 1

    # Validate environment
    validate_environment_parameter "$ENVIRONMENT" || exit 1

    # Show pipeline configuration
    echo ""
    log_info "Pipeline Configuration:"
    log_info "  Target: $tier $environment"
    log_info "  GraphQL Endpoint: $GRAPHQL_ENDPOINT"
    log_info "  Data Source: $DATA_SOURCE_PATH"

    if [[ "$VERIFY_ONLY" == "true" ]]; then
        log_info "  Mode: Verification Only"
    elif [[ "$SKIP_PURGE" == "true" ]]; then
        log_info "  Mode: Load + Verify (skip purge)"
    else
        log_info "  Mode: Full Pipeline (purge + load + verify)"
    fi

    # Production confirmation for destructive operations
    if [[ "$ENVIRONMENT" == "production" ]] && [[ "$SKIP_PURGE" == "false" ]] && [[ "$VERIFY_ONLY" == "false" ]]; then
        if ! confirm_production_operation "deploy seed data (including purge) to $TIER database"; then
            exit 0
        fi
    fi

    # Pipeline execution
    local phases_completed=0
    local phases_failed=0

    # Phase 1: Purge (optional)
    if [[ "$SKIP_PURGE" == "false" ]] && [[ "$VERIFY_ONLY" == "false" ]]; then
        if run_purge_phase "$TIER" "$ENVIRONMENT"; then
            ((phases_completed++))
        else
            ((phases_failed++))
            log_error "Pipeline failed at purge phase"
        fi
    fi

    # Phase 2: Load (optional)
    if [[ "$VERIFY_ONLY" == "false" ]]; then
        if [[ $phases_failed -eq 0 ]] || [[ "$SKIP_PURGE" == "true" ]]; then
            if run_load_phase "$TIER" "$ENVIRONMENT"; then
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

    # Phase 3: Verify (always run)
    if [[ $phases_failed -eq 0 ]] || [[ "$VERIFY_ONLY" == "true" ]]; then
        if run_verify_phase "$TIER" "$ENVIRONMENT"; then
            ((phases_completed++))
        else
            ((phases_failed++))
            log_error "Pipeline failed at verification phase"
        fi
    else
        log_warning "Skipping verification phase due to previous failures"
        ((phases_failed++))
    fi

    # Generate final report
    generate_deployment_report "$TIER" "$ENVIRONMENT" "$SKIP_PURGE" "$VERIFY_ONLY" "$phases_completed" "$phases_failed"

    show_command_summary

    # Exit with appropriate code
    if [[ $phases_failed -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Set trap for error handling
trap cleanup_on_error EXIT

# Run main function
main

# Clear trap on success
trap - EXIT