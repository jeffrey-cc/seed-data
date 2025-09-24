#!/bin/bash

# ================================================================================
# LazyGourmet CSV Rebuild Command
# ================================================================================
# Simple wrapper to rebuild CSV files from Source Data
# Usage: ./rebuild.sh
# ================================================================================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAZYGOURMET_ROOT="$(dirname "$SCRIPT_DIR")"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Configuration
PYTHON_SCRIPT="$SCRIPT_DIR/extract_csv.py"
BASH_SCRIPT="$SCRIPT_DIR/rebuild-csv.sh"

echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${CYAN} LazyGourmet CSV Rebuild${RESET}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

# Check which method to use
if command -v python3 &> /dev/null && [[ -f "$PYTHON_SCRIPT" ]]; then
    echo -e "${GREEN}✓${RESET} Using Python extractor (recommended for large files)"
    echo ""
    python3 "$PYTHON_SCRIPT" "$@"
elif command -v psql &> /dev/null && [[ -f "$BASH_SCRIPT" ]]; then
    echo -e "${YELLOW}⚠${RESET} Using PostgreSQL method (requires temporary database)"
    echo ""
    "$BASH_SCRIPT" "$@"
else
    echo -e "${RED}✗${RESET} No suitable extraction method found"
    echo ""
    echo "Please ensure either:"
    echo "  1. Python 3 is installed, or"
    echo "  2. PostgreSQL (psql) is installed"
    exit 1
fi