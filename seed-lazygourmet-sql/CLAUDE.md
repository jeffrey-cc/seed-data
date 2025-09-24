# CLAUDE.md - LazyGourmet Seed Data Repository

This repository contains cleaned and processed seed data from the LazyGourmet commercial kitchen facility for use with the Community Connect Tech multi-tenant platform.

## Repository Purpose

This seed data repository demonstrates a real-world commercial kitchen operation with:
- 430 member restaurant companies 
- Complete facility operations data
- Equipment usage and sensor monitoring
- Financial transactions and billing
- Support ticket management

## Data Status

✅ **Data Successfully Loaded**: 724,010 records in operator database  
✅ **Member Companies Identified**: 430 restaurant businesses  
✅ **Clean Architecture**: Proper operator/member data separation

## Key Member Companies

- Candid Confectioner
- When Pigs Fly  
- Parsdish Foods Inc
- Kondi Kitchen
- Revel Juice
- Beta 5 Chocolates
- Los Tacos
- Crumb Sandwich Shop

## Usage

This data is already loaded into the operator database at port 7102. The member companies are identified but would need schema transformation to load into the member database (port 7103) due to different table structures.

## Context for Claude

When working with this data:
- Operator database contains facility management for LazyGourmet kitchen
- Member companies represent real restaurants using the shared kitchen
- Data demonstrates proper multi-tenant architecture
- Financial records show actual business transactions
- Sensor data includes temperature monitoring and access control

This is production-quality seed data representing a functioning commercial kitchen ecosystem.