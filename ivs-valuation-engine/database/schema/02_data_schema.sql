-- IVS Valuation Engine - Data Schema
-- This schema contains all input data, documents, financials, market data, and comparables

CREATE SCHEMA IF NOT EXISTS data_schema;

SET search_path TO data_schema;

-- ============================================================================
-- DOCUMENTS TABLE
-- All uploaded documents with metadata and reliability assessment (IVS 104)
-- ============================================================================
CREATE TABLE documents (
    document_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL, -- FK to engagement_schema.engagements
    document_type VARCHAR(100) NOT NULL CHECK (document_type IN (
        'constitutional_documents', 'shareholders_agreement', 'cap_table',
        'option_register', 'loan_agreement', 'banking_covenant', 'key_contract',
        'income_statement', 'balance_sheet', 'cash_flow_statement', 'trial_balance',
        'tax_return', 'tax_computation', 'management_forecast', 'budget',
        'fixed_asset_register', 'customer_concentration', 'supplier_concentration',
        'operational_kpis', 'other'
    )),
    document_category VARCHAR(50) NOT NULL CHECK (document_category IN (
        'corporate_legal', 'financial_statements', 'forecasts', 'operational', 'tax', 'other'
    )),
    file_name VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_size BIGINT,
    file_type VARCHAR(50), -- e.g., 'pdf', 'xlsx', 'docx'

    -- IVS 104 Data quality attributes
    source VARCHAR(100) NOT NULL CHECK (source IN ('management', 'auditor', 'external_advisor', 'public_database', 'other')),
    reliability_level VARCHAR(20) CHECK (reliability_level IN ('high', 'medium', 'low')),
    data_type VARCHAR(50) CHECK (data_type IN ('observable', 'non_observable')), -- IVS 104 classification
    date_of_data DATE, -- Date the data relates to (vs upload date)
    audited BOOLEAN DEFAULT FALSE,
    auditor_name VARCHAR(255),

    upload_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    uploaded_by UUID NOT NULL,
    processed BOOLEAN DEFAULT FALSE,
    processing_status VARCHAR(50) DEFAULT 'pending',
    extraction_method VARCHAR(50), -- e.g., 'manual', 'ocr', 'api', 'excel_import'

    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_documents_engagement ON documents(engagement_id);
CREATE INDEX idx_documents_type ON documents(document_type);
CREATE INDEX idx_documents_source ON documents(source);

-- ============================================================================
-- HISTORICAL FINANCIALS TABLE
-- Structured historical financial statements (3-5 years)
-- ============================================================================
CREATE TABLE historical_financials (
    financial_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,
    document_id UUID REFERENCES documents(document_id) ON DELETE SET NULL,

    period_end_date DATE NOT NULL,
    period_type VARCHAR(20) DEFAULT 'annual' CHECK (period_type IN ('annual', 'quarterly', 'monthly')),
    fiscal_year INTEGER,
    statement_type VARCHAR(50) NOT NULL CHECK (statement_type IN ('income_statement', 'balance_sheet', 'cash_flow_statement')),

    audited BOOLEAN DEFAULT FALSE,
    audit_opinion VARCHAR(50) CHECK (audit_opinion IN ('unqualified', 'qualified', 'adverse', 'disclaimer', 'not_audited')),

    -- Flexible JSONB for financial line items
    financial_data JSONB NOT NULL,

    currency VARCHAR(10) NOT NULL,
    reporting_standard VARCHAR(50), -- e.g., 'IFRS', 'US_GAAP', 'local_GAAP'

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_financial_period_statement UNIQUE (engagement_id, period_end_date, statement_type)
);

CREATE INDEX idx_financials_engagement ON historical_financials(engagement_id);
CREATE INDEX idx_financials_period ON historical_financials(period_end_date);
CREATE INDEX idx_financials_type ON historical_financials(statement_type);
CREATE INDEX idx_financials_data ON historical_financials USING gin(financial_data);

-- ============================================================================
-- CHART OF ACCOUNTS MAPPING TABLE
-- AI-assisted mapping of company COA to standardized valuation template
-- ============================================================================
CREATE TABLE coa_mapping (
    mapping_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    original_account_code VARCHAR(100),
    original_account_name VARCHAR(255) NOT NULL,
    original_category VARCHAR(100), -- From source system

    mapped_category VARCHAR(100) NOT NULL, -- Standardized: revenue, cogs, opex_salaries, opex_rent, etc.
    mapped_subcategory VARCHAR(100),
    mapping_level VARCHAR(50) CHECK (mapping_level IN ('revenue', 'cogs', 'gross_profit', 'opex', 'ebitda', 'depreciation', 'ebit', 'interest', 'tax', 'net_income', 'assets', 'liabilities', 'equity')),

    mapping_confidence VARCHAR(20) DEFAULT 'manual' CHECK (mapping_confidence IN ('auto_high', 'auto_medium', 'auto_low', 'manual')),
    mapping_method VARCHAR(50), -- e.g., 'ml_model', 'keyword_match', 'manual_selection'

    approved BOOLEAN DEFAULT FALSE,
    approved_by UUID,
    approved_at TIMESTAMP,

    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_original_account UNIQUE (engagement_id, original_account_code)
);

CREATE INDEX idx_coa_engagement ON coa_mapping(engagement_id);
CREATE INDEX idx_coa_mapped_category ON coa_mapping(mapped_category);

-- ============================================================================
-- NORMALISATION ADJUSTMENTS TABLE
-- All adjustments to arrive at normalised/adjusted earnings (IVS 102)
-- ============================================================================
CREATE TABLE normalisations (
    adjustment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    adjustment_name VARCHAR(255) NOT NULL,
    adjustment_type VARCHAR(50) NOT NULL CHECK (adjustment_type IN ('recurring', 'non_recurring', 'operating', 'non_operating')),
    adjustment_category VARCHAR(100), -- e.g., 'owner_compensation', 'related_party', 'one_off_event', 'accounting_policy'

    description TEXT NOT NULL,
    rationale TEXT NOT NULL,
    supporting_evidence TEXT,

    affected_statement VARCHAR(50) CHECK (affected_statement IN ('income_statement', 'balance_sheet', 'cash_flow')),
    affected_line_item VARCHAR(100),

    -- Financial impact
    amount NUMERIC(20, 2) NOT NULL,
    currency VARCHAR(10) NOT NULL,
    affected_years INTEGER[], -- Array of fiscal years affected
    recurring_impact BOOLEAN DEFAULT FALSE,

    -- Basis of value consideration
    entity_specific BOOLEAN DEFAULT TRUE, -- If TRUE, relevant for Investment Value but maybe not Market Value
    market_participant_adjustment BOOLEAN DEFAULT FALSE, -- If TRUE, adjustment a market participant would make

    -- Source and approval
    source VARCHAR(50) CHECK (source IN ('management', 'valuer', 'external_advisor', 'auditor')),
    proposed_by UUID,
    approved BOOLEAN DEFAULT FALSE,
    approved_by UUID,
    approved_at TIMESTAMP,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_normalisations_engagement ON normalisations(engagement_id);
CREATE INDEX idx_normalisations_type ON normalisations(adjustment_type);
CREATE INDEX idx_normalisations_approved ON normalisations(approved);

-- ============================================================================
-- PROSPECTIVE FINANCIAL INFORMATION (PFI) TABLE
-- Management forecasts and auto-generated forecasts
-- ============================================================================
CREATE TABLE prospective_financials (
    pfi_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    forecast_name VARCHAR(255) NOT NULL, -- e.g., 'Management Base Case', 'Auto-Generated', 'Adjusted Case'
    forecast_type VARCHAR(50) CHECK (forecast_type IN ('management', 'auto_generated', 'valuer_adjusted')),
    scenario VARCHAR(50) DEFAULT 'base' CHECK (scenario IN ('base', 'upside', 'downside', 'sensitivity')),

    period_end_date DATE NOT NULL,
    period_number INTEGER, -- Forecast year 1, 2, 3, etc.

    -- Financial projections (can be JSONB or explicit columns)
    revenue NUMERIC(20, 2),
    cogs NUMERIC(20, 2),
    gross_profit NUMERIC(20, 2),
    operating_expenses NUMERIC(20, 2),
    ebitda NUMERIC(20, 2),
    depreciation NUMERIC(20, 2),
    amortisation NUMERIC(20, 2),
    ebit NUMERIC(20, 2),
    interest_expense NUMERIC(20, 2),
    pbt NUMERIC(20, 2),
    tax NUMERIC(20, 2),
    net_income NUMERIC(20, 2),

    capex NUMERIC(20, 2),
    working_capital_change NUMERIC(20, 2),
    free_cash_flow NUMERIC(20, 2),

    -- Key assumptions (JSONB for flexibility)
    assumptions JSONB,

    currency VARCHAR(10) NOT NULL,

    created_by UUID,
    approved BOOLEAN DEFAULT FALSE,
    approved_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_pfi_engagement ON prospective_financials(engagement_id);
CREATE INDEX idx_pfi_forecast_type ON prospective_financials(forecast_type);
CREATE INDEX idx_pfi_period ON prospective_financials(period_end_date);

-- ============================================================================
-- MARKET DATA TABLE
-- External market data: risk-free rate, ERP, betas, inflation, FX, etc.
-- ============================================================================
CREATE TABLE market_data (
    market_data_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    data_category VARCHAR(100) NOT NULL, -- e.g., 'risk_free_rate', 'equity_risk_premium', 'beta', 'inflation', 'gdp_growth', 'fx_rate'
    data_type VARCHAR(50) CHECK (data_type IN ('observable', 'non_observable')), -- IVS 104

    geography VARCHAR(100), -- e.g., 'Malaysia', 'US', 'Global'
    sector VARCHAR(100),

    value NUMERIC(20, 6) NOT NULL,
    value_unit VARCHAR(50), -- e.g., '%', 'ratio', 'currency'

    as_of_date DATE NOT NULL,
    source VARCHAR(255) NOT NULL, -- e.g., 'Bloomberg', 'Damodaran', 'Central Bank', 'Yahoo Finance'
    source_detail TEXT, -- e.g., ticker, URL, report reference

    retrieval_method VARCHAR(50) CHECK (retrieval_method IN ('api', 'manual', 'web_scrape', 'database')),
    retrieved_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    retrieved_by UUID,

    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_market_data_engagement ON market_data(engagement_id);
CREATE INDEX idx_market_data_category ON market_data(data_category);
CREATE INDEX idx_market_data_date ON market_data(as_of_date);

-- ============================================================================
-- COMPARABLE COMPANIES TABLE
-- Public company comparables for market approach
-- ============================================================================
CREATE TABLE comparable_companies (
    comparable_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    company_name VARCHAR(255) NOT NULL,
    ticker VARCHAR(50),
    exchange VARCHAR(100),

    sector VARCHAR(100),
    industry VARCHAR(100),
    geography VARCHAR(100),
    business_model TEXT,

    -- Financials and metrics (as of comparison date)
    as_of_date DATE NOT NULL,
    market_cap NUMERIC(20, 2),
    enterprise_value NUMERIC(20, 2),
    revenue NUMERIC(20, 2),
    ebitda NUMERIC(20, 2),
    ebit NUMERIC(20, 2),
    net_income NUMERIC(20, 2),
    total_assets NUMERIC(20, 2),
    book_value NUMERIC(20, 2),

    -- Multiples (calculated or sourced)
    ev_revenue NUMERIC(10, 4),
    ev_ebitda NUMERIC(10, 4),
    ev_ebit NUMERIC(10, 4),
    pe_ratio NUMERIC(10, 4),
    pb_ratio NUMERIC(10, 4),

    -- Growth and profitability
    revenue_growth_rate NUMERIC(10, 4),
    ebitda_margin NUMERIC(10, 4),

    -- Inclusion/exclusion
    included BOOLEAN DEFAULT TRUE,
    inclusion_rationale TEXT,
    exclusion_rationale TEXT,

    data_source VARCHAR(100), -- e.g., 'Bloomberg', 'S&P CIQ', 'Refinitiv'
    currency VARCHAR(10),

    created_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_comparables_engagement ON comparable_companies(engagement_id);
CREATE INDEX idx_comparables_included ON comparable_companies(included);
CREATE INDEX idx_comparables_sector ON comparable_companies(sector);

-- ============================================================================
-- TRANSACTION COMPARABLES TABLE
-- Precedent transactions for market approach
-- ============================================================================
CREATE TABLE transaction_comparables (
    transaction_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    target_company_name VARCHAR(255) NOT NULL,
    acquirer_company_name VARCHAR(255),

    transaction_date DATE NOT NULL,
    announced_date DATE,
    closed_date DATE,

    sector VARCHAR(100),
    industry VARCHAR(100),
    geography VARCHAR(100),

    -- Transaction details
    transaction_value NUMERIC(20, 2),
    equity_value NUMERIC(20, 2),
    enterprise_value NUMERIC(20, 2),
    ownership_acquired NUMERIC(5, 2), -- Percentage
    transaction_type VARCHAR(50) CHECK (transaction_type IN ('acquisition', 'merger', 'buyout', 'minority_stake', 'ipo')),

    -- Target financials (LTM or at transaction)
    revenue NUMERIC(20, 2),
    ebitda NUMERIC(20, 2),
    ebit NUMERIC(20, 2),

    -- Multiples
    ev_revenue NUMERIC(10, 4),
    ev_ebitda NUMERIC(10, 4),
    ev_ebit NUMERIC(10, 4),

    -- Control premium (if disclosed)
    control_premium NUMERIC(10, 4),

    -- Inclusion/exclusion
    included BOOLEAN DEFAULT TRUE,
    inclusion_rationale TEXT,
    exclusion_rationale TEXT,

    data_source VARCHAR(100),
    currency VARCHAR(10),

    created_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_transactions_engagement ON transaction_comparables(engagement_id);
CREATE INDEX idx_transactions_included ON transaction_comparables(included);
CREATE INDEX idx_transactions_date ON transaction_comparables(transaction_date);

-- ============================================================================
-- CAPITAL STRUCTURE TABLE
-- Detailed debt schedule and equity structure
-- ============================================================================
CREATE TABLE capital_structure (
    capital_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    item_type VARCHAR(50) NOT NULL CHECK (item_type IN ('equity', 'debt', 'hybrid', 'option', 'warrant', 'convertible')),
    instrument_name VARCHAR(255) NOT NULL,

    -- For equity
    share_class VARCHAR(100),
    shares_outstanding BIGINT,
    par_value NUMERIC(20, 4),
    voting_rights BOOLEAN,
    dividend_rights BOOLEAN,
    liquidation_preference NUMERIC(20, 2),

    -- For debt
    lender VARCHAR(255),
    principal_amount NUMERIC(20, 2),
    currency VARCHAR(10),
    interest_rate NUMERIC(10, 4), -- %
    interest_type VARCHAR(20) CHECK (interest_type IN ('fixed', 'floating', 'zero_coupon')),
    margin NUMERIC(10, 4), -- Basis points or %
    maturity_date DATE,
    amortisation_schedule TEXT,
    security_ranking VARCHAR(50) CHECK (security_ranking IN ('senior_secured', 'senior_unsecured', 'subordinated', 'mezzanine')),
    covenants TEXT,

    -- For options/warrants
    strike_price NUMERIC(20, 4),
    expiry_date DATE,
    vesting_schedule TEXT,

    as_of_date DATE NOT NULL,

    created_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_capital_engagement ON capital_structure(engagement_id);
CREATE INDEX idx_capital_type ON capital_structure(item_type);

-- ============================================================================
-- OPERATIONAL METRICS TABLE
-- Sector-specific KPIs (SaaS: ARR, churn; Retail: stores, footfall, etc.)
-- ============================================================================
CREATE TABLE operational_metrics (
    metric_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    period_end_date DATE NOT NULL,
    metric_category VARCHAR(100), -- e.g., 'SaaS', 'Retail', 'Manufacturing', 'General'
    metric_name VARCHAR(255) NOT NULL, -- e.g., 'ARR', 'Churn_Rate', 'CAC', 'LTV', 'Store_Count'
    metric_value NUMERIC(20, 4),
    metric_unit VARCHAR(50), -- e.g., 'currency', '%', 'count', 'days'

    source VARCHAR(100),
    notes TEXT,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_metrics_engagement ON operational_metrics(engagement_id);
CREATE INDEX idx_metrics_category ON operational_metrics(metric_category);
CREATE INDEX idx_metrics_period ON operational_metrics(period_end_date);

-- ============================================================================
-- CUSTOMER & SUPPLIER CONCENTRATION TABLE
-- Top customers and suppliers for risk assessment
-- ============================================================================
CREATE TABLE concentration_analysis (
    concentration_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    analysis_type VARCHAR(20) CHECK (analysis_type IN ('customer', 'supplier')),
    entity_name VARCHAR(255) NOT NULL,
    ranking INTEGER, -- Top 1, Top 2, etc.

    period_end_date DATE NOT NULL,
    revenue_or_cost NUMERIC(20, 2),
    percentage_of_total NUMERIC(5, 2),

    relationship_duration VARCHAR(100), -- e.g., '5 years', 'new customer'
    contract_status VARCHAR(100), -- e.g., 'long-term contract', 'at-will', 'renewal pending'

    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_concentration_engagement ON concentration_analysis(engagement_id);
CREATE INDEX idx_concentration_type ON concentration_analysis(analysis_type);

-- ============================================================================
-- TRIGGERS
-- ============================================================================
CREATE TRIGGER update_documents_updated_at BEFORE UPDATE ON documents
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_financials_updated_at BEFORE UPDATE ON historical_financials
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_coa_updated_at BEFORE UPDATE ON coa_mapping
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_normalisations_updated_at BEFORE UPDATE ON normalisations
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_pfi_updated_at BEFORE UPDATE ON prospective_financials
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_comparables_updated_at BEFORE UPDATE ON comparable_companies
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_transactions_updated_at BEFORE UPDATE ON transaction_comparables
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_capital_updated_at BEFORE UPDATE ON capital_structure
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON SCHEMA data_schema IS 'IVS Valuation Engine - All input data, documents, financials, and market data (IVS 104)';
COMMENT ON TABLE documents IS 'Document repository with IVS 104 data quality attributes';
COMMENT ON TABLE historical_financials IS 'Structured historical financial statements (3-5 years minimum)';
COMMENT ON TABLE coa_mapping IS 'AI-assisted chart of accounts mapping to standardized template';
COMMENT ON TABLE normalisations IS 'Normalisation adjustments for arriving at adjusted earnings (IVS 102)';
COMMENT ON TABLE market_data IS 'External market data (observable and non-observable per IVS 104)';
COMMENT ON TABLE comparable_companies IS 'Public company comparables for market approach (IVS 105)';
COMMENT ON TABLE transaction_comparables IS 'Precedent transactions for market approach';
