# LazyGourmet Seed Data

This repository contains seed data extracted from the LazyGourmet commercial kitchen facility for loading into the Community Connect Tech database system.

## Data Structure

The LazyGourmet data represents a real commercial kitchen operation with:

- **430 Member Companies** - Restaurant businesses using the shared kitchen facility
  - Examples: Candid Confectioner, When Pigs Fly, Parsdish Foods Inc, Kondi Kitchen
- **Facility Operations** - Equipment, bookings, billing, support tickets
- **Sensor Data** - Temperature monitoring and door access logs
- **Financial Data** - Charges, invoices, payments for facility usage

## Data Distribution

- **Total Records**: 749,025 successfully loaded
- **Integration Schema**: 75% (sensor data, access logs)
- **Assets Schema**: 20.7% (equipment, bookings)
- **Financial Schema**: 2.5% (billing data)
- **Communications**: 1.5% (email events)
- **Other Schemas**: <1% each

## Loading Status

✅ **Operator Database**: Successfully loaded 724,010 records  
⚠️ **Member Database**: Schema mismatch - member companies identified but require transformation

## Architecture Notes

This data follows the proper tier separation:
- **Operator Tier**: Facility management, operations, equipment, sensors
- **Member Tier**: Individual restaurant companies and their usage

The data demonstrates a real-world multi-tenant commercial kitchen operation where one operator (LazyGourmet) manages a facility used by many member restaurant businesses.