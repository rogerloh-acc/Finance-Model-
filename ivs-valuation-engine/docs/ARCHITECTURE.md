# IVS Valuation Engine - System Architecture

## 1. Overview

The IVS Valuation Engine is a multi-tier web application designed to support professional valuers in conducting IVS-compliant business valuations. The architecture separates concerns across presentation, business logic, data access, and external integration layers.

## 2. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        PRESENTATION LAYER                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   Web UI     │  │  Report Gen  │  │   Admin Console      │  │
│  │ (Next.js)    │  │  (PDF/PPTX)  │  │   (Dashboard)        │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        APPLICATION LAYER                         │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              REST API (FastAPI)                          │   │
│  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────────────┐    │   │
│  │  │  Auth  │ │  SoW   │ │ Data   │ │   Valuation    │    │   │
│  │  │        │ │        │ │ Intake │ │    Models      │    │   │
│  │  └────────┘ └────────┘ └────────┘ └────────────────┘    │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        BUSINESS LOGIC LAYER                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐    │
│  │   SoW    │  │   Data   │  │ Valuation│  │   Quality    │    │
│  │ Manager  │  │Processor │  │  Engine  │  │   Control    │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────────┘    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐    │
│  │  DCF     │  │  Market  │  │  Asset   │  │   Report     │    │
│  │ Module   │  │ Approach │  │ Approach │  │  Generator   │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        DATA ACCESS LAYER                         │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              ORM (SQLAlchemy)                            │   │
│  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌──────────────┐      │   │
│  │  │Engage- │ │  Data  │ │ Model  │ │    Audit     │      │   │
│  │  │ ment   │ │        │ │        │ │              │      │   │
│  │  └────────┘ └────────┘ └────────┘ └──────────────┘      │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        DATA STORAGE LAYER                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │  PostgreSQL  │  │  File Store  │  │   Cache (Redis)      │  │
│  │   Database   │  │  (S3/Local)  │  │                      │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     EXTERNAL SERVICES LAYER                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐    │
│  │Bloomberg │  │ Damodaran│  │  Yahoo   │  │     OCR      │    │
│  │   API    │  │   Data   │  │ Finance  │  │   Service    │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## 3. Database Schema Design

### 3.1 Schema Separation

The database is organized into four separate schemas for clarity and security:

1. **engagement_schema**: Engagement metadata, SoW, parties, compliance
2. **data_schema**: All input data, documents, financials, market data
3. **model_schema**: Valuation models, calculations, scenarios, results
4. **audit_schema**: Complete audit trail, version history, approvals

### 3.2 Core Tables

#### engagement_schema

```sql
-- Engagements (main engagement record)
engagements
  - engagement_id (PK)
  - client_name
  - legal_entity_name
  - registration_number
  - jurisdiction
  - valuation_date
  - report_date
  - status (draft, in_progress, review, final)
  - created_by
  - created_at
  - updated_at

-- Scope of Work
scope_of_work
  - sow_id (PK)
  - engagement_id (FK)
  - version
  - asset_description
  - intended_users
  - intended_use
  - basis_of_value (market_value, fair_value, investment_value, etc.)
  - premise_of_value
  - currency
  - ivs_compliance_statement
  - departures_from_ivs
  - locked (boolean)
  - locked_at
  - approved_by
  - approved_at

-- Valuers and Team
engagement_team
  - team_id (PK)
  - engagement_id (FK)
  - user_id (FK)
  - role (lead_valuer, reviewer, assistant, admin)
  - independence_declaration
  - conflict_of_interest_cleared

-- Assumptions
assumptions
  - assumption_id (PK)
  - engagement_id (FK)
  - assumption_type (standard, special, limiting)
  - description
  - rationale
  - impact_on_value
```

#### data_schema

```sql
-- Documents
documents
  - document_id (PK)
  - engagement_id (FK)
  - document_type (financial_statements, contract, cap_table, forecast, etc.)
  - file_name
  - file_path
  - file_size
  - upload_date
  - uploaded_by
  - source (management, auditor, external)
  - reliability_level (high, medium, low)
  - date_of_data

-- Historical Financials
historical_financials
  - financial_id (PK)
  - engagement_id (FK)
  - period_end_date
  - statement_type (income_statement, balance_sheet, cash_flow)
  - audited (boolean)
  - financial_data (JSONB - flexible structure)

-- Chart of Accounts Mapping
coa_mapping
  - mapping_id (PK)
  - engagement_id (FK)
  - original_account_code
  - original_account_name
  - mapped_category (revenue, cogs, opex, etc.)
  - mapping_confidence (auto, manual)
  - approved_by

-- Normalisation Adjustments
normalisations
  - adjustment_id (PK)
  - engagement_id (FK)
  - adjustment_type (recurring, non_recurring, operating, non_operating)
  - description
  - amount
  - affected_years
  - rationale
  - source (management, valuer, external)
  - approved (boolean)

-- Market Data
market_data
  - market_data_id (PK)
  - engagement_id (FK)
  - data_type (risk_free_rate, erp, beta, etc.)
  - value
  - source
  - date_retrieved
  - observable (boolean)

-- Comparable Companies
comparables
  - comparable_id (PK)
  - engagement_id (FK)
  - company_name
  - ticker
  - sector
  - geography
  - revenue
  - ebitda
  - market_cap
  - enterprise_value
  - inclusion_rationale
  - exclusion_rationale
```

#### model_schema

```sql
-- Valuation Models
valuation_models
  - model_id (PK)
  - engagement_id (FK)
  - model_type (dcf, market_multiples, asset_based)
  - scenario (base, upside, downside)
  - status (draft, calculated, reviewed)
  - created_at
  - updated_at

-- Forecasts
forecasts
  - forecast_id (PK)
  - model_id (FK)
  - forecast_year
  - forecast_period
  - revenue
  - cogs
  - opex
  - ebitda
  - ebit
  - tax
  - capex
  - depreciation
  - working_capital_change
  - free_cash_flow
  - assumptions (JSONB)

-- WACC Calculations
wacc_calculations
  - wacc_id (PK)
  - model_id (FK)
  - risk_free_rate
  - equity_risk_premium
  - beta
  - size_premium
  - company_specific_premium
  - cost_of_equity
  - cost_of_debt
  - tax_rate
  - debt_ratio
  - equity_ratio
  - wacc

-- Valuation Results
valuation_results
  - result_id (PK)
  - model_id (FK)
  - approach (income, market, asset)
  - method (dcf, guideline_public, guideline_transaction, nav)
  - indication_of_value
  - sensitivity_range_low
  - sensitivity_range_high
  - weight_assigned
  - weighting_rationale

-- Concluded Value
concluded_values
  - conclusion_id (PK)
  - engagement_id (FK)
  - point_estimate
  - value_range_low
  - value_range_high
  - conclusion_rationale
  - concluded_by
  - concluded_at
  - approved_by
  - approved_at
```

#### audit_schema

```sql
-- Audit Trail
audit_trail
  - audit_id (PK)
  - engagement_id (FK)
  - table_name
  - record_id
  - action (create, update, delete, approve)
  - old_value (JSONB)
  - new_value (JSONB)
  - changed_by
  - changed_at
  - ip_address

-- Query Log (professional scepticism)
query_log
  - query_id (PK)
  - engagement_id (FK)
  - query_description
  - flagged_by (system, valuer)
  - flag_type (red_flag, yellow_flag, inquiry)
  - management_response
  - valuer_resolution
  - resolution_status (open, accepted, rejected, modified)
  - created_at
  - resolved_at

-- Review Comments
review_comments
  - comment_id (PK)
  - engagement_id (FK)
  - reviewer_id (FK)
  - section (sow, data, model, report)
  - comment_text
  - status (open, addressed, rejected)
  - created_at
  - resolved_at

-- Version Control
version_history
  - version_id (PK)
  - engagement_id (FK)
  - version_number
  - version_date
  - changes_summary
  - created_by
```

## 4. Core Modules

### 4.1 Engagement & SoW Module
- **Purpose**: Enforce IVS 101 compliance before any valuation work
- **Features**:
  - Mandatory field validation
  - Version control and locking
  - Independence and conflict checks
  - Amendment tracking

### 4.2 Data Intake & Processing Module
- **Purpose**: Structured capture and validation of all inputs
- **Features**:
  - Document upload and OCR
  - Financial statement parsing
  - Chart of accounts mapping (AI-assisted)
  - Data quality checks and reconciliation

### 4.3 Normalisation & Adjustments Module
- **Purpose**: Professional scepticism and earnings normalization
- **Features**:
  - Automated red flag detection
  - Adjustment proposal and tracking
  - Rationale documentation
  - Approval workflow

### 4.4 Forecasting Module (PFI Builder)
- **Purpose**: Driver-based financial projections
- **Features**:
  - Management forecast input
  - Auto-forecast (fallback)
  - Consistency checks vs. history
  - Scenario modeling

### 4.5 WACC & Discount Rate Module
- **Purpose**: Cost of capital calculation
- **Features**:
  - CAPM implementation
  - Build-up method
  - Market data integration
  - Sensitivity analysis

### 4.6 DCF Valuation Module
- **Purpose**: Income approach valuation
- **Features**:
  - FCFF/FCFE calculation
  - Terminal value (Gordon Growth, exit multiple)
  - Mid-year convention
  - Scenario analysis

### 4.7 Market Approach Module
- **Purpose**: Relative valuation using comparables
- **Features**:
  - Peer selection (AI-assisted)
  - Multiple calculation (EV/EBITDA, P/E, etc.)
  - Control/marketability adjustments
  - Transaction database integration

### 4.8 Asset Approach Module
- **Purpose**: Asset-based valuation
- **Features**:
  - Net asset value calculation
  - Asset revaluation to market
  - Liquidation value scenarios

### 4.9 Reconciliation & Weighting Engine
- **Purpose**: Football field and value conclusion
- **Features**:
  - Visual football field chart
  - Structured weighting framework
  - Professional judgment capture
  - Consistency checks

### 4.10 Reporting Module
- **Purpose**: IVS-compliant report generation
- **Features**:
  - Template-based report builder
  - Automated data population
  - Appendices and workpapers
  - PDF/PPTX export
  - Audit trail package

### 4.11 Quality Control Module
- **Purpose**: Review workflow and compliance
- **Features**:
  - Multi-level review
  - Comment tracking
  - Approval workflow
  - IVS compliance checklist

## 5. Security & Access Control

### 5.1 Authentication
- JWT-based authentication
- Multi-factor authentication (optional)
- Session management

### 5.2 Authorization
- Role-based access control (RBAC):
  - **Admin**: Full system access
  - **Lead Valuer**: Create and conclude valuations
  - **Assistant Valuer**: Input data and prepare models
  - **Reviewer**: Review and approve valuations
  - **Read-Only**: View completed valuations

### 5.3 Data Security
- Encryption at rest (database)
- Encryption in transit (TLS/SSL)
- Audit logging of all access
- Data retention policies

## 6. Integration Points

### 6.1 Market Data APIs
- Bloomberg API (risk-free rates, betas, multiples)
- Refinitiv/LSEG
- Yahoo Finance (backup)
- Damodaran Online (ERP, industry data)

### 6.2 Document Processing
- OCR service for scanned financials
- PDF parsing libraries
- Excel/CSV import

### 6.3 Export & Reporting
- HTML-to-PDF (WeasyPrint, Puppeteer)
- PPTX generation (python-pptx)
- Excel export (openpyxl)

## 7. Scalability & Performance

### 7.1 Caching Strategy
- Redis for session data
- Market data caching (15-minute refresh)
- Report generation queue

### 7.2 Background Processing
- Celery for async tasks:
  - Financial data parsing
  - Market data fetching
  - Report generation
  - Email notifications

### 7.3 Database Optimization
- Indexing on engagement_id, dates, status
- Partitioning for large audit tables
- Query optimization

## 8. Compliance & Governance

### 8.1 IVS Compliance Enforcement
- No value conclusion without approved SoW
- Mandatory professional judgment capture
- Audit trail for all decisions
- Version control and amendment tracking

### 8.2 AVM Classification
- System classified as Automated Valuation Model (AVM)
- Valuer retains full responsibility
- Human review required before "IVS-compliant" label
- Clear separation of automated calculations vs. professional judgment

### 8.3 Quality Assurance
- Built-in validation rules
- Mandatory review workflow (optional enable)
- Compliance checklists
- Report quality review

## 9. Deployment Architecture

### 9.1 Development Environment
- Local PostgreSQL
- Local file storage
- Mock external APIs

### 9.2 Production Environment
- Containerized deployment (Docker)
- PostgreSQL (managed service)
- S3 or equivalent for file storage
- Load balancer
- Auto-scaling backend instances
- CDN for frontend assets

### 9.3 CI/CD Pipeline
- GitHub Actions
- Automated testing
- Database migration checks
- Deployment to staging → production

## 10. Future Enhancements

- Machine learning for peer selection
- Natural language processing for management discussion analysis
- Integration with accounting systems
- Mobile app for data collection
- Real-time collaboration features
- Advanced ESG analytics
- Blockchain-based audit trail
