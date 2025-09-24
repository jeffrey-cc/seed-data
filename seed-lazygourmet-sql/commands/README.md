# LazyGourmet CSV Rebuild Commands

This directory contains commands for rebuilding CSV files from the PostgreSQL dump "Source Data".

## Quick Start

To rebuild CSV files from the Source Data:

```bash
./rebuild.sh
```

This will:
1. Parse the PostgreSQL dump file "Source Data"
2. Extract all table data
3. Save as CSV files in the `csv_export` directory
4. Compare with "Last CSV Export" to show changes

## Commands

### `rebuild.sh`
Main command - automatically chooses the best extraction method (Python or PostgreSQL).

### `extract_csv.py`
Python-based extractor (recommended) - processes the dump file directly without needing a database.

```bash
# Basic usage
python3 extract_csv.py

# Custom output directory
python3 extract_csv.py -o my_csv_output

# Skip comparison with last export
python3 extract_csv.py --no-compare
```

### `rebuild-csv.sh`
PostgreSQL-based extractor - creates a temporary database, restores the dump, then exports CSVs.

```bash
# Requires PostgreSQL to be installed
./rebuild-csv.sh [output_dir]
```

## Output

CSV files are saved with the following naming convention:
- Tables with schemas: `schema_tablename.csv` (e.g., `ar_charges.csv`)
- Tables without schemas: `tablename.csv`

## Comparison

The scripts automatically compare the new export with "Last CSV Export" directory and show:
- New tables
- Missing tables
- Row count changes

## Data Format

The CSV files include:
- Headers with column names
- Tab-separated values converted to comma-separated
- PostgreSQL NULL values (\N) converted to empty strings
- Proper quoting for fields containing commas