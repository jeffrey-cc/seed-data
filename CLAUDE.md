# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **Seed Data Loading System** for Community Connect Tech's multi-tenant platform. It provides standardized CSV data loading capabilities across all three tiers (admin, operator, member) of the system, using GraphQL APIs as the target endpoints.

## Purpose and Architecture

### Core Function
This repository serves as the centralized data loading orchestrator that:
- Loads CSV data from child repositories into GraphQL APIs
- Provides consistent data deployment workflows across all tiers
- Handles data purging, loading, and verification in a unified pipeline
- Supports both development and production environments

### Data Flow Architecture
```
CSV Data Sources → Seed Data Commands → GraphQL APIs → Databases
```

### Tier Integration
- **Admin Tier**: Loads data from `admin-seed-sql/` child repository
- **Operator Tier**: Loads data from `lazygourmet-operator-data/` child repository
- **Member Tier**: Loads data from `lazygourmet-member-data/` child repository
- **Sensor Data**: Special purpose data from `seed-lazygourmet-sensors/` child repository

## Commands Overview

All commands are located in the `commands/` directory and follow a consistent interface pattern:

### Primary Commands

#### `load-seed-data.sh` - Enhanced Multi-Mode Deployment Pipeline
```bash
# Load via GraphQL (full pipeline)
./commands/load-seed-data.sh admin development graphql

# Load via PostgreSQL direct connection
./commands/load-seed-data.sh admin development postgres

# Load without purging existing data
./commands/load-seed-data.sh operator development postgres --skip-purge

# Load specific table only
./commands/load-seed-data.sh admin development graphql --table admin_users

# Purge data only
./commands/load-seed-data.sh admin development postgres --purge-only

# Verify existing data only
./commands/load-seed-data.sh admin development graphql --verify-only
```

#### `confirm-data.sh` - Data Confirmation and Counting
```bash
# Confirm data via both GraphQL and PostgreSQL
./commands/confirm-data.sh admin development

# Confirm via GraphQL only
./commands/confirm-data.sh operator development graphql

# Confirm via PostgreSQL only
./commands/confirm-data.sh admin production postgres
```

### Legacy Commands (Still Available)

#### `deploy-seed-data.sh` - Original GraphQL-Only Pipeline
```bash
# GraphQL-only full pipeline (legacy)
./commands/deploy-seed-data.sh admin development

# GraphQL load without purging
./commands/deploy-seed-data.sh operator development --skip-purge
```

#### `load-csv-data.sh` - GraphQL CSV Data Loading
```bash
# Load all CSV data via GraphQL
./commands/load-csv-data.sh admin development

# Load specific table via GraphQL
./commands/load-csv-data.sh operator development members
```

#### `purge-data.sh` - GraphQL Data Purging
```bash
# Purge via GraphQL API
./commands/purge-data.sh admin development
```

#### `verify-data.sh` - GraphQL Data Verification
```bash
# Verify via GraphQL API
./commands/verify-data.sh admin development
```

### Command Parameters

All commands follow this pattern:
- `<tier>`: Target tier (admin, operator, or member)
- `<environment>`: Target environment (development or production)
- Additional parameters vary by command

## Upload Modes

The system supports two primary upload modes for maximum flexibility:

### GraphQL Mode
- **Target**: Hasura GraphQL endpoints
- **Method**: GraphQL mutations with automatic type conversion
- **Advantages**: Schema validation, relationship enforcement, transaction safety
- **Use Case**: When GraphQL server is running and you want API-level validation

### PostgreSQL Mode
- **Target**: Direct PostgreSQL database connection
- **Method**: SQL INSERT statements with batch processing
- **Advantages**: Faster bulk loading, bypasses API limitations
- **Use Case**: When you need maximum performance or GraphQL is unavailable

## Integration Endpoints

### GraphQL Configuration
Commands automatically configure GraphQL endpoints based on tier:
- **Admin**: `http://localhost:8101/v1/graphql`
- **Operator**: `http://localhost:8102/v1/graphql`
- **Member**: `http://localhost:8103/v1/graphql`

### PostgreSQL Configuration
Commands automatically configure database connections based on tier:
- **Admin**: `postgresql://admin:CCTech2024Admin!@localhost:7101/admin_database`
- **Operator**: `postgresql://operator:CCTech2024Operator!@localhost:7102/operator_database`
- **Member**: `postgresql://member:CCTech2024Member!@localhost:7103/member_database`

### Authentication
- **GraphQL**: Uses Hasura admin secrets (`CCTech2024{Tier}`)
- **PostgreSQL**: Uses database user credentials with tier-specific passwords

### Data Operations
- **CSV to GraphQL**: Automatic conversion of CSV data to GraphQL mutations
- **CSV to SQL**: Direct SQL INSERT generation with proper escaping
- **Type Detection**: Intelligent handling of integers, floats, booleans, dates, and strings
- **Relationship Preservation**: Maintains foreign key relationships during loading
- **Dynamic Purging**: Discovers and truncates all user tables automatically

## CSV Data Requirements

### File Structure
CSV files should be located in tier-specific child repository directories:
```
{tier-specific-repo}/csv_original/  OR  {tier-specific-repo}/csv/
├── 01_category/
│   ├── 01_table1.csv
│   └── 02_table2.csv
└── 02_category/
    └── 01_table3.csv
```

Actual child repositories:
- `admin-seed-sql/` - Admin tier seed data
- `lazygourmet-operator-data/` - Operator tier seed data
- `lazygourmet-member-data/` - Member tier seed data
- `seed-lazygourmet-sensors/` - Sensor data (special purpose)

### Naming Conventions
- Files: `[0-9][0-9]_table_name.csv` (e.g., `01_admin_users.csv`)
- Table names derived by removing numeric prefixes
- Directories processed in alphabetical order for dependency resolution

### CSV Format Requirements
- First row must contain column headers
- Headers must match database column names
- Empty values are skipped during loading
- Data types auto-detected based on content patterns

## Development Workflow

### Standard Data Deployment

#### GraphQL Mode (Recommended for Development)
1. **Ensure GraphQL servers are running** for target tier
2. **Run complete pipeline**:
   ```bash
   ./commands/load-seed-data.sh admin development graphql
   ```
3. **Confirm deployment**:
   ```bash
   ./commands/confirm-data.sh admin development
   ```

#### PostgreSQL Mode (Recommended for Bulk Loading)
1. **Ensure PostgreSQL databases are running** for target tier
2. **Run complete pipeline**:
   ```bash
   ./commands/load-seed-data.sh admin development postgres
   ```
3. **Confirm deployment**:
   ```bash
   ./commands/confirm-data.sh admin development postgres
   ```

### Incremental Data Loading
For adding data without destroying existing records:
```bash
# Via GraphQL
./commands/load-seed-data.sh admin development graphql --skip-purge

# Via PostgreSQL
./commands/load-seed-data.sh admin development postgres --skip-purge
```

### Production Deployment
Production operations require explicit confirmation:
```bash
# PostgreSQL mode for production (faster)
./commands/load-seed-data.sh admin production postgres
# Will prompt for confirmation before destructive operations

# Confirm deployment
./commands/confirm-data.sh admin production
```

### Data Purging Only
To clear data without loading new data:
```bash
# Via GraphQL
./commands/load-seed-data.sh admin development graphql --purge-only

# Via PostgreSQL (faster)
./commands/load-seed-data.sh admin development postgres --purge-only
```

### Troubleshooting
- **Connection Issues**:
  - GraphQL: Verify GraphQL servers are running on expected ports
  - PostgreSQL: Verify database containers are running and accessible
- **Data Conflicts**: Use purge command before loading if encountering constraint violations
- **Verification Failures**:
  - GraphQL: Check GraphQL schema matches CSV column names
  - PostgreSQL: Check database schema matches CSV structure
- **Performance Issues**: Use PostgreSQL mode for large datasets

## Error Handling and Logging

### Logging Levels
- **DEBUG**: Detailed operation information (enable with `DEBUG=true`)
- **INFO**: General operational messages
- **WARNING**: Non-fatal issues that should be noted
- **ERROR**: Fatal errors that prevent operation completion

### Error Recovery
- Commands use `set -euo pipefail` for strict error handling
- Failed operations provide detailed error messages
- Production operations include confirmation steps
- Cleanup functions handle error states gracefully

## Integration with Parent System

### Repository Relationships
This system integrates with:
- **database-sql**: Provides database deployment and management
- **graphql-api**: Provides GraphQL server management and deployment
- **Child repositories**: Contain the actual CSV data sources:
  - `admin-seed-sql/` - Admin tier CSV data
  - `lazygourmet-operator-data/` - Operator tier CSV data
  - `lazygourmet-member-data/` - Member tier CSV data
  - `seed-lazygourmet-sensors/` - Sensor CSV data

### Coordination with Other Systems
- Database must be deployed before CSV loading
- GraphQL servers must be running and accessible
- Schema must be tracked in Hasura before data loading

## Production Safety

### Confirmation Requirements
Production operations require typing confirmation phrases:
- Data purge: `DELETE ALL DATA`
- General operations: `CONFIRM`

### Data Protection
- All destructive operations clearly warn about permanence
- Production confirmation prevents accidental data loss
- Verification phase ensures data integrity after loading

## Command Reference

### Enhanced Primary Command
- **`load-seed-data.sh`**: Multi-mode deployment pipeline with GraphQL and PostgreSQL support
- **`confirm-data.sh`**: Comprehensive data verification and counting across both modes

### Legacy Commands (GraphQL Only)
- **`deploy-seed-data.sh`**: Original GraphQL-only pipeline
- **`load-csv-data.sh`**: GraphQL CSV loading
- **`purge-data.sh`**: GraphQL data purging
- **`verify-data.sh`**: GraphQL data verification

### Shared Functions
- **`_shared_functions.sh`**: Core functions supporting both GraphQL and PostgreSQL modes

## Dependencies

### Required Tools
- `curl`: For GraphQL API communication
- `jq`: For JSON processing and GraphQL query construction
- `psql`: For PostgreSQL database operations
- `bash`: Version 4+ with associative arrays
- Standard Unix tools: `find`, `sort`, `head`, `tail`, `wc`

### System Requirements
- **GraphQL Mode**: Access to GraphQL endpoints on specified ports (8101-8103)
- **PostgreSQL Mode**: Direct database access on specified ports (7101-7103)
- Network connectivity to target systems
- Read access to CSV data source directories

### Performance Considerations
- **GraphQL Mode**: Better for development and validation, slower for large datasets
- **PostgreSQL Mode**: Better for production and bulk loading, faster for large datasets
- **Hybrid Approach**: Use PostgreSQL for loading, GraphQL for verification