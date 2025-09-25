# LazyGourmet Data Upload Guide

## Overview
The LazyGourmet data has been separated into two distinct upload processes for the Community Connect Tech multi-tenant platform:

1. **lazygourmet-operator-data** → Operator Database (port 7102)
2. **lazygourmet-member-data** → Member Database (port 7103)

## Quick Commands

### Upload to OPERATOR Database
```bash
cd lazygourmet-operator-data
./upload_to_operator.sh
```
This loads:
- Facility management data
- Equipment and assets
- Access control systems
- Facility financial records

### Upload to MEMBER Database
```bash
cd lazygourmet-member-data
./upload_to_member.sh
```
This loads:
- 430+ member companies
- Member bookings
- Member transactions
- Member communications

## Data Separation

### Operator Data (Facility Management)
- **Target**: operator_database at port 7102
- **Focus**: Managing the shared commercial kitchen
- **Categories**:
  - 02_operations (facility config)
  - 03_access (doors & locks)
  - 04_assets (equipment)
  - 05_financial (facility billing)
  - 07_communications (templates)
  - 08_documents (document mgmt)

### Member Data (Restaurant Companies)
- **Target**: member_database at port 7103
- **Focus**: Individual restaurant companies
- **Categories**:
  - 01_identity (member companies, kind=2)
  - 04_assets (member bookings)
  - 05_financial (member transactions)
  - 07_communications (member support)

## Key Differences

| Aspect | Operator Data | Member Data |
|--------|--------------|-------------|
| Database | operator_database | member_database |
| Port | 7102 | 7103 |
| GraphQL | :8102/v1/graphql | :8103/v1/graphql |
| Focus | Facility Management | Restaurant Companies |
| Principal Type | kind=1 (operator) | kind=2 (members) |
| Record Count | ~300K facility records | ~400K member records |

## Running Both Uploads

To upload both datasets:
```bash
# Upload operator data first
cd lazygourmet-operator-data
./upload_to_operator.sh

# Then upload member data
cd ../lazygourmet-member-data
./upload_to_member.sh
```

## Verification

After uploading, verify the data:

### Operator Database
```bash
psql postgresql://operator@localhost:7102/operator_database
# Check facility data
SELECT COUNT(*) FROM facilities;
SELECT COUNT(*) FROM assets;
SELECT COUNT(*) FROM doors;
```

### Member Database
```bash
psql postgresql://member@localhost:7103/member_database
# Check member data
SELECT COUNT(*) FROM members WHERE kind = 2;
SELECT COUNT(*) FROM bookings;
SELECT COUNT(*) FROM transactions;
```

## Notes
- Both directories contain the same source data but filter differently
- Upload scripts automatically filter based on target database
- Member extraction uses kind=2 to identify member companies
- Operator data excludes member-specific records
- Both processes can run independently