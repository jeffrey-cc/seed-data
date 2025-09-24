#!/usr/bin/env python3

"""
Extract CSV Files from PostgreSQL Dump
Processes the large "Source Data" PostgreSQL dump file and extracts
individual table data as CSV files.
"""

import re
import csv
import os
import sys
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple

# Color codes for terminal output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    BOLD = '\033[1m'
    RESET = '\033[0m'

def log_info(msg: str):
    print(f"{Colors.CYAN}ℹ{Colors.RESET} {msg}")

def log_success(msg: str):
    print(f"{Colors.GREEN}✓{Colors.RESET} {msg}")

def log_warning(msg: str):
    print(f"{Colors.YELLOW}⚠{Colors.RESET} {msg}")

def log_error(msg: str):
    print(f"{Colors.RED}✗{Colors.RESET} {msg}", file=sys.stderr)

def log_section(msg: str):
    print(f"\n{Colors.BOLD}{Colors.BLUE}{'━' * 72}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE} {msg}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'━' * 72}{Colors.RESET}\n")

class PostgreSQLDumpParser:
    """Parser for PostgreSQL dump files to extract table data"""

    def __init__(self, dump_file: str):
        self.dump_file = dump_file
        self.tables = {}
        self.current_table = None
        self.current_columns = []
        self.output_dir = None

    def parse_copy_statement(self, line: str) -> Optional[Tuple[str, List[str]]]:
        """Parse COPY statement to get table name and columns"""
        # Pattern: COPY [schema.]table_name (col1, col2, ...) FROM stdin;
        # Handles: COPY table_name, COPY public.table_name, COPY ar.table_name, etc.
        pattern = r'COPY\s+(?:(\w+)\.)?(\w+)\s*\((.*?)\)\s+FROM\s+stdin'
        match = re.match(pattern, line, re.IGNORECASE)

        if match:
            schema = match.group(1)  # May be None
            table_name = match.group(2)
            columns_str = match.group(3)

            # Include schema in table name if present and not 'public'
            if schema and schema.lower() != 'public':
                full_table_name = f"{schema}_{table_name}"
            else:
                full_table_name = table_name

            # Parse column names - handle quoted columns
            columns = []
            for col in columns_str.split(','):
                col = col.strip()
                # Remove quotes if present
                if col.startswith('"') and col.endswith('"'):
                    col = col[1:-1]
                columns.append(col)

            return full_table_name, columns
        return None

    def parse_data_row(self, line: str) -> Optional[List[str]]:
        """Parse a data row from COPY data section"""
        if line == '\\.\n' or line == '\\.':
            # End of COPY data
            return None

        # Tab-separated values
        fields = line.rstrip('\n').split('\t')

        # Convert PostgreSQL NULLs (\N) to empty strings
        fields = ['' if f == '\\N' else f for f in fields]

        return fields

    def process_dump(self, output_dir: str = "csv_export"):
        """Process the entire dump file"""
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)

        log_section("Processing PostgreSQL Dump")
        log_info(f"Source: {self.dump_file}")
        log_info(f"Output: {self.output_dir}")

        # Track statistics
        tables_found = 0
        total_rows = 0
        current_csv = None
        current_writer = None
        in_copy_data = False

        # Process the dump file
        try:
            with open(self.dump_file, 'r', encoding='utf-8', errors='ignore') as f:
                log_info("Scanning for table data...")

                for line_num, line in enumerate(f, 1):
                    # Progress indicator for large files
                    if line_num % 100000 == 0:
                        log_info(f"Processing line {line_num:,}...")

                    # Check for COPY statement
                    if line.startswith('COPY '):
                        result = self.parse_copy_statement(line)
                        if result:
                            table_name, columns = result

                            # Close previous CSV if open
                            if current_csv:
                                current_csv.close()

                            # Start new CSV file
                            csv_path = self.output_dir / f"{table_name}.csv"
                            log_info(f"Extracting table: {table_name}")

                            current_csv = open(csv_path, 'w', newline='', encoding='utf-8')
                            current_writer = csv.writer(current_csv)

                            # Write header
                            current_writer.writerow(columns)

                            self.current_table = table_name
                            self.current_columns = columns
                            in_copy_data = True
                            tables_found += 1
                            continue

                    # Process data rows
                    if in_copy_data:
                        if line.strip() == '\\.':
                            # End of COPY data
                            in_copy_data = False
                            rows_in_table = sum(1 for _ in open(self.output_dir / f"{self.current_table}.csv")) - 1
                            total_rows += rows_in_table
                            log_success(f"  → {rows_in_table:,} rows exported")
                            continue

                        # Parse and write data row
                        fields = self.parse_data_row(line)
                        if fields and current_writer:
                            # Ensure correct number of fields
                            if len(fields) == len(self.current_columns):
                                current_writer.writerow(fields)
                            else:
                                log_warning(f"  Skipping malformed row in {self.current_table}")

                # Close last file if open
                if current_csv:
                    current_csv.close()

        except Exception as e:
            log_error(f"Error processing dump: {e}")
            if current_csv:
                current_csv.close()
            return False

        log_section("Export Complete")
        log_success(f"Tables exported: {tables_found}")
        log_success(f"Total rows: {total_rows:,}")

        return True

    def compare_with_last_export(self, last_export_dir: str):
        """Compare extracted CSVs with last export"""
        last_export_path = Path(last_export_dir)

        if not last_export_path.exists():
            log_warning(f"Last export directory not found: {last_export_dir}")
            return

        log_section("Comparing with Last Export")

        # Get all CSV files from both directories
        new_files = set(f.name for f in self.output_dir.glob("*.csv"))
        old_files = set(f.name for f in last_export_path.glob("*.csv"))

        # Check each file
        for filename in sorted(new_files | old_files):
            new_path = self.output_dir / filename
            old_path = last_export_path / filename

            if not old_path.exists():
                log_info(f"{filename}: NEW FILE")
            elif not new_path.exists():
                log_warning(f"{filename}: MISSING (was in last export)")
            else:
                # Compare row counts
                with open(new_path) as f:
                    new_count = sum(1 for _ in f) - 1  # Subtract header
                with open(old_path) as f:
                    old_count = sum(1 for _ in f) - 1  # Subtract header

                if new_count == old_count:
                    log_success(f"{filename}: {new_count:,} rows (unchanged)")
                else:
                    diff = new_count - old_count
                    if diff > 0:
                        log_warning(f"{filename}: {new_count:,} rows (+{diff:,})")
                    else:
                        log_warning(f"{filename}: {new_count:,} rows ({diff:,})")

def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(
        description="Extract CSV files from PostgreSQL dump"
    )
    parser.add_argument(
        '-s', '--source',
        default='Source Data',
        help='Path to PostgreSQL dump file (default: "Source Data")'
    )
    parser.add_argument(
        '-o', '--output',
        default='csv_export',
        help='Output directory for CSV files (default: csv_export)'
    )
    parser.add_argument(
        '-c', '--compare',
        default='Last CSV Export',
        help='Directory with last export for comparison'
    )
    parser.add_argument(
        '--no-compare',
        action='store_true',
        help='Skip comparison with last export'
    )

    args = parser.parse_args()

    # Get script directory
    script_dir = Path(__file__).parent
    lazygourmet_root = script_dir.parent

    # Build full paths
    source_path = lazygourmet_root / args.source
    output_path = lazygourmet_root / args.output
    compare_path = lazygourmet_root / args.compare

    # Check if source exists
    if not source_path.exists():
        log_error(f"Source file not found: {source_path}")
        sys.exit(1)

    log_section("LazyGourmet CSV Extraction")
    log_info(f"Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    # Create parser and process
    parser = PostgreSQLDumpParser(str(source_path))

    if parser.process_dump(str(output_path)):
        # Compare with last export if requested
        if not args.no_compare and compare_path.exists():
            parser.compare_with_last_export(str(compare_path))

        log_success("Extraction completed successfully!")
    else:
        log_error("Extraction failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()