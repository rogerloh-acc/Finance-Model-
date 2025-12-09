-- IVS Valuation Engine - Model Schema
-- This schema contains all valuation models, calculations, scenarios, and results

CREATE SCHEMA IF NOT EXISTS model_schema;

SET search_path TO model_schema;

-- ============================================================================
-- VALUATION MODELS TABLE
-- Container for different valuation models (DCF, Market, Asset-based)
-- ============================================================================
CREATE TABLE valuation_models (
    model_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL, -- FK to engagement_schema.engagements

    model_name VARCHAR(255) NOT NULL,
    model_type VARCHAR(50) NOT NULL CHECK (model_type IN ('dcf', 'market_multiples', 'asset_based', 'option_pricing')),
    approach VARCHAR(50) NOT NULL CHECK (approach IN ('income', 'market', 'asset_cost')),
    method VARCHAR(100), -- e.g., 'DCF_FCFF', 'DCF_FCFE', 'Guideline_Public_Company', 'Guideline_Transaction', 'NAV'

    scenario VARCHAR(50) DEFAULT 'base' CHECK (scenario IN ('base', 'upside', 'downside', 'sensitivity', 'management', 'adjusted')),

    status VARCHAR(50) DEFAULT 'draft' CHECK (status IN ('draft', 'calculated', 'reviewed', 'approved', 'rejected')),

    description TEXT,
    key_assumptions JSONB,

    created_by UUID,
    reviewed_by UUID,
    approved_by UUID,
    approved_at TIMESTAMP,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_models_engagement ON valuation_models(engagement_id);
CREATE INDEX idx_models_type ON valuation_models(model_type);
CREATE INDEX idx_models_scenario ON valuation_models(scenario);

-- ============================================================================
-- FORECASTS TABLE
-- Forecast cash flows for DCF models (explicit period + terminal)
-- ============================================================================
CREATE TABLE forecasts (
    forecast_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_id UUID NOT NULL REFERENCES valuation_models(model_id) ON DELETE CASCADE,

    forecast_year INTEGER NOT NULL,
    period_end_date DATE,
    is_terminal_period BOOLEAN DEFAULT FALSE,

    -- Income statement items
    revenue NUMERIC(20, 2),
    revenue_growth_rate NUMERIC(10, 4),
    cogs NUMERIC(20, 2),
    gross_profit NUMERIC(20, 2),
    gross_margin NUMERIC(10, 4),
    operating_expenses NUMERIC(20, 2),
    ebitda NUMERIC(20, 2),
    ebitda_margin NUMERIC(10, 4),
    depreciation NUMERIC(20, 2),
    amortisation NUMERIC(20, 2),
    ebit NUMERIC(20, 2),
    ebit_margin NUMERIC(10, 4),
    interest_expense NUMERIC(20, 2),
    pbt NUMERIC(20, 2),
    tax NUMERIC(20, 2),
    tax_rate NUMERIC(10, 4),
    net_income NUMERIC(20, 2),

    -- Cash flow items
    nopat NUMERIC(20, 2), -- Net Operating Profit After Tax
    add_back_depreciation NUMERIC(20, 2),
    capex NUMERIC(20, 2),
    working_capital_change NUMERIC(20, 2),
    reinvestment NUMERIC(20, 2),
    reinvestment_rate NUMERIC(10, 4),

    -- Free cash flows
    fcff NUMERIC(20, 2), -- Free Cash Flow to Firm
    fcfe NUMERIC(20, 2), -- Free Cash Flow to Equity
    unlevered_fcf NUMERIC(20, 2),

    -- Drivers and assumptions (JSONB for flexibility)
    drivers JSONB, -- e.g., {"customer_count": 10000, "arpu": 50, "churn": 0.05}

    currency VARCHAR(10),

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_forecasts_model ON forecasts(model_id);
CREATE INDEX idx_forecasts_year ON forecasts(forecast_year);

-- ============================================================================
-- WACC CALCULATIONS TABLE
-- Weighted Average Cost of Capital detailed build-up
-- ============================================================================
CREATE TABLE wacc_calculations (
    wacc_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_id UUID NOT NULL REFERENCES valuation_models(model_id) ON DELETE CASCADE,

    calculation_name VARCHAR(255),
    calculation_method VARCHAR(50) CHECK (calculation_method IN ('CAPM', 'build_up', 'market_implied')),

    -- Risk-free rate
    risk_free_rate NUMERIC(10, 6) NOT NULL,
    risk_free_rate_source VARCHAR(255),
    risk_free_rate_date DATE,

    -- Equity risk premium
    equity_risk_premium NUMERIC(10, 6) NOT NULL,
    erp_source VARCHAR(255),
    country_risk_premium NUMERIC(10, 6) DEFAULT 0,

    -- Beta (for CAPM)
    raw_beta NUMERIC(10, 6),
    adjusted_beta NUMERIC(10, 6),
    beta_source VARCHAR(255),
    relevering_formula VARCHAR(100), -- e.g., 'Hamada', 'Harris-Pringle'

    -- Levered/unlevered
    unlevered_beta NUMERIC(10, 6),
    levered_beta NUMERIC(10, 6),
    target_debt_to_equity NUMERIC(10, 6),
    target_debt_to_value NUMERIC(10, 6),

    -- Size premium
    size_premium NUMERIC(10, 6) DEFAULT 0,
    size_premium_source VARCHAR(255),

    -- Company-specific risk premium
    company_specific_premium NUMERIC(10, 6) DEFAULT 0,
    company_specific_rationale TEXT,

    -- Resulting cost of equity
    cost_of_equity NUMERIC(10, 6) NOT NULL,

    -- Cost of debt
    cost_of_debt_pretax NUMERIC(10, 6),
    cost_of_debt_aftertax NUMERIC(10, 6),
    marginal_tax_rate NUMERIC(10, 6),

    -- Capital structure
    market_value_equity NUMERIC(20, 2),
    market_value_debt NUMERIC(20, 2),
    equity_weight NUMERIC(10, 6),
    debt_weight NUMERIC(10, 6),

    -- WACC result
    wacc NUMERIC(10, 6) NOT NULL,

    -- Sensitivity ranges (for scenario analysis)
    wacc_low NUMERIC(10, 6),
    wacc_high NUMERIC(10, 6),

    notes TEXT,
    created_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_wacc_model ON wacc_calculations(model_id);

-- ============================================================================
-- DCF CALCULATIONS TABLE
-- Detailed DCF valuation with discounting and terminal value
-- ============================================================================
CREATE TABLE dcf_calculations (
    dcf_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_id UUID NOT NULL REFERENCES valuation_models(model_id) ON DELETE CASCADE,
    wacc_id UUID REFERENCES wacc_calculations(wacc_id) ON DELETE SET NULL,

    dcf_type VARCHAR(50) CHECK (dcf_type IN ('FCFF', 'FCFE', 'dividend_discount')),

    -- Discount rate
    discount_rate NUMERIC(10, 6) NOT NULL, -- WACC for FCFF, Cost of Equity for FCFE
    discount_convention VARCHAR(50) DEFAULT 'mid_year' CHECK (discount_convention IN ('year_end', 'mid_year')),

    -- Explicit period
    explicit_period_years INTEGER DEFAULT 5,
    pv_explicit_period NUMERIC(20, 2),

    -- Terminal value
    terminal_value_method VARCHAR(50) CHECK (terminal_value_method IN ('gordon_growth', 'exit_multiple', 'perpetuity')),
    terminal_growth_rate NUMERIC(10, 6),
    terminal_multiple NUMERIC(10, 4),
    terminal_multiple_type VARCHAR(50), -- e.g., 'EV/EBITDA', 'P/E'
    terminal_fcf NUMERIC(20, 2),
    terminal_value NUMERIC(20, 2),
    pv_terminal_value NUMERIC(20, 2),

    -- Enterprise / equity value
    enterprise_value NUMERIC(20, 2),
    plus_cash NUMERIC(20, 2),
    plus_non_operating_assets NUMERIC(20, 2),
    less_debt NUMERIC(20, 2),
    less_minority_interest NUMERIC(20, 2),
    less_preferred_equity NUMERIC(20, 2),
    equity_value NUMERIC(20, 2),

    -- Per share (if applicable)
    shares_outstanding BIGINT,
    value_per_share NUMERIC(20, 4),

    -- Implied metrics (for reasonableness check)
    implied_ev_revenue NUMERIC(10, 4),
    implied_ev_ebitda NUMERIC(10, 4),
    implied_pe NUMERIC(10, 4),

    currency VARCHAR(10),

    created_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_dcf_model ON dcf_calculations(model_id);

-- ============================================================================
-- MARKET MULTIPLES CALCULATIONS TABLE
-- Market approach valuation using comparables
-- ============================================================================
CREATE TABLE market_multiples_calculations (
    multiples_calc_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_id UUID NOT NULL REFERENCES valuation_models(model_id) ON DELETE CASCADE,

    multiples_type VARCHAR(50) CHECK (multiples_type IN ('guideline_public_company', 'guideline_transaction')),

    -- Multiple metrics used
    metric_name VARCHAR(100) NOT NULL, -- e.g., 'EV/Revenue', 'EV/EBITDA', 'P/E', 'P/B'
    metric_type VARCHAR(50) CHECK (metric_type IN ('enterprise_value', 'equity_value')),

    -- Comparable set statistics
    peer_count INTEGER,
    multiple_min NUMERIC(10, 4),
    multiple_max NUMERIC(10, 4),
    multiple_mean NUMERIC(10, 4),
    multiple_median NUMERIC(10, 4),
    multiple_25th_percentile NUMERIC(10, 4),
    multiple_75th_percentile NUMERIC(10, 4),

    -- Selected multiple for subject
    selected_multiple NUMERIC(10, 4) NOT NULL,
    selection_rationale TEXT,

    -- Subject company metric
    subject_metric_value NUMERIC(20, 2) NOT NULL, -- e.g., Revenue, EBITDA
    subject_metric_period VARCHAR(100), -- e.g., 'LTM', 'FY2024', 'NTM'

    -- Calculated value
    indicated_value NUMERIC(20, 2) NOT NULL,

    -- Adjustments
    control_premium NUMERIC(10, 4) DEFAULT 0,
    discount_lack_of_marketability NUMERIC(10, 4) DEFAULT 0,
    other_adjustments NUMERIC(20, 2) DEFAULT 0,
    adjustment_rationale TEXT,

    adjusted_value NUMERIC(20, 2),

    currency VARCHAR(10),

    created_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_multiples_model ON market_multiples_calculations(model_id);

-- ============================================================================
-- ASSET-BASED CALCULATIONS TABLE
-- Net Asset Value / Asset-based approach
-- ============================================================================
CREATE TABLE asset_based_calculations (
    asset_calc_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_id UUID NOT NULL REFERENCES valuation_models(model_id) ON DELETE CASCADE,

    valuation_basis VARCHAR(50) CHECK (valuation_basis IN ('going_concern', 'orderly_liquidation', 'forced_sale')),

    -- Book values
    book_value_assets NUMERIC(20, 2),
    book_value_liabilities NUMERIC(20, 2),
    book_value_equity NUMERIC(20, 2),

    -- Adjustments to market/fair value
    tangible_assets_adjustment NUMERIC(20, 2) DEFAULT 0,
    intangible_assets_adjustment NUMERIC(20, 2) DEFAULT 0,
    financial_assets_adjustment NUMERIC(20, 2) DEFAULT 0,
    liabilities_adjustment NUMERIC(20, 2) DEFAULT 0,

    -- Fair value / market value
    fair_value_assets NUMERIC(20, 2),
    fair_value_liabilities NUMERIC(20, 2),
    net_asset_value NUMERIC(20, 2),

    -- Goodwill / going concern premium (if applicable)
    goodwill NUMERIC(20, 2) DEFAULT 0,
    goodwill_rationale TEXT,

    total_value NUMERIC(20, 2),

    adjustment_notes TEXT,
    currency VARCHAR(10),

    created_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_asset_model ON asset_based_calculations(model_id);

-- ============================================================================
-- VALUATION RESULTS TABLE
-- Indications of value from each approach/method
-- ============================================================================
CREATE TABLE valuation_results (
    result_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_id UUID NOT NULL REFERENCES valuation_models(model_id) ON DELETE CASCADE,
    engagement_id UUID NOT NULL, -- denormalized for easy querying

    approach VARCHAR(50) NOT NULL CHECK (approach IN ('income', 'market', 'asset_cost')),
    method VARCHAR(100) NOT NULL, -- e.g., 'DCF_FCFF', 'Guideline_Public_EV/EBITDA', 'NAV'

    indication_of_value NUMERIC(20, 2) NOT NULL,
    value_type VARCHAR(50) CHECK (value_type IN ('enterprise_value', 'equity_value', 'per_share')),

    sensitivity_range_low NUMERIC(20, 2),
    sensitivity_range_high NUMERIC(20, 2),

    -- Weighting for reconciliation
    weight_assigned NUMERIC(5, 2) DEFAULT 0, -- Percentage 0-100
    weighting_rationale TEXT,

    -- Reliability and relevance
    reliability_rating VARCHAR(20) CHECK (reliability_rating IN ('high', 'medium', 'low')),
    reliability_notes TEXT,

    currency VARCHAR(10),

    created_by UUID,
    approved BOOLEAN DEFAULT FALSE,
    approved_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_results_model ON valuation_results(model_id);
CREATE INDEX idx_results_engagement ON valuation_results(engagement_id);
CREATE INDEX idx_results_approach ON valuation_results(approach);

-- ============================================================================
-- SCENARIO ANALYSIS TABLE
-- Scenario and sensitivity analysis results
-- ============================================================================
CREATE TABLE scenario_analysis (
    scenario_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,
    model_id UUID REFERENCES valuation_models(model_id) ON DELETE CASCADE,

    scenario_name VARCHAR(255) NOT NULL,
    scenario_type VARCHAR(50) CHECK (scenario_type IN ('base', 'upside', 'downside', 'stress', 'sensitivity')),

    -- Scenario assumptions (JSONB for flexibility)
    scenario_assumptions JSONB NOT NULL,

    -- Results
    enterprise_value NUMERIC(20, 2),
    equity_value NUMERIC(20, 2),
    value_per_share NUMERIC(20, 4),

    -- Key metrics under scenario
    key_metrics JSONB,

    probability_weight NUMERIC(5, 2) DEFAULT 0, -- For probability-weighted scenarios

    created_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_scenario_engagement ON scenario_analysis(engagement_id);
CREATE INDEX idx_scenario_model ON scenario_analysis(model_id);

-- ============================================================================
-- SENSITIVITY ANALYSIS TABLE
-- Sensitivity tables (e.g., WACC vs Terminal Growth)
-- ============================================================================
CREATE TABLE sensitivity_analysis (
    sensitivity_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_id UUID NOT NULL REFERENCES valuation_models(model_id) ON DELETE CASCADE,

    sensitivity_name VARCHAR(255) NOT NULL,
    variable_1_name VARCHAR(100) NOT NULL, -- e.g., 'WACC'
    variable_1_min NUMERIC(20, 6),
    variable_1_max NUMERIC(20, 6),
    variable_1_step NUMERIC(20, 6),

    variable_2_name VARCHAR(100), -- For 2D sensitivity
    variable_2_min NUMERIC(20, 6),
    variable_2_max NUMERIC(20, 6),
    variable_2_step NUMERIC(20, 6),

    -- Results grid (stored as JSONB)
    sensitivity_grid JSONB NOT NULL,

    created_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sensitivity_model ON sensitivity_analysis(model_id);

-- ============================================================================
-- RECONCILIATION TABLE
-- Football field and weighting reconciliation
-- ============================================================================
CREATE TABLE reconciliation (
    reconciliation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    reconciliation_name VARCHAR(255) DEFAULT 'Final Reconciliation',
    reconciliation_date DATE DEFAULT CURRENT_DATE,

    -- Approach weights
    income_approach_weight NUMERIC(5, 2) DEFAULT 0,
    market_approach_weight NUMERIC(5, 2) DEFAULT 0,
    asset_approach_weight NUMERIC(5, 2) DEFAULT 0,

    weighting_rationale TEXT NOT NULL,

    -- Preliminary conclusion
    preliminary_value_low NUMERIC(20, 2),
    preliminary_value_high NUMERIC(20, 2),
    preliminary_value_midpoint NUMERIC(20, 2),

    -- Professional judgment notes
    professional_judgment_notes TEXT,

    currency VARCHAR(10),

    created_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT weights_sum_100 CHECK (income_approach_weight + market_approach_weight + asset_approach_weight = 100)
);

CREATE INDEX idx_reconciliation_engagement ON reconciliation(engagement_id);

-- ============================================================================
-- CONCLUDED VALUE TABLE
-- Final concluded value with rationale (one per engagement)
-- ============================================================================
CREATE TABLE concluded_values (
    conclusion_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL UNIQUE, -- One conclusion per engagement
    reconciliation_id UUID REFERENCES reconciliation(reconciliation_id) ON DELETE SET NULL,

    -- Concluded value
    point_estimate NUMERIC(20, 2),
    value_range_low NUMERIC(20, 2),
    value_range_high NUMERIC(20, 2),
    value_range_provided BOOLEAN DEFAULT FALSE,

    value_type VARCHAR(50) CHECK (value_type IN ('enterprise_value', 'equity_value', 'per_share', 'business_interest')),

    -- Rounding
    rounding_applied BOOLEAN DEFAULT FALSE,
    rounding_rationale TEXT,

    -- Rationale and conclusion
    conclusion_rationale TEXT NOT NULL,
    methods_given_greatest_weight TEXT,
    quality_of_data_assessment TEXT,
    market_conditions_assessment TEXT,
    unusual_uncertainties TEXT,

    -- Consistency checks
    implied_ev_revenue NUMERIC(10, 4),
    implied_ev_ebitda NUMERIC(10, 4),
    implied_pe NUMERIC(10, 4),
    comparison_to_nav NUMERIC(20, 2),
    comparison_to_transaction_price NUMERIC(20, 2),

    currency VARCHAR(10),

    -- Sign-offs
    concluded_by UUID NOT NULL,
    concluded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    reviewed_by UUID,
    reviewed_at TIMESTAMP,
    approved_by UUID,
    approved_at TIMESTAMP,

    final BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_concluded_engagement ON concluded_values(engagement_id);

-- ============================================================================
-- TRIGGERS
-- ============================================================================
CREATE TRIGGER update_models_updated_at BEFORE UPDATE ON valuation_models
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_forecasts_updated_at BEFORE UPDATE ON forecasts
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_wacc_updated_at BEFORE UPDATE ON wacc_calculations
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_dcf_updated_at BEFORE UPDATE ON dcf_calculations
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_multiples_updated_at BEFORE UPDATE ON market_multiples_calculations
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_asset_updated_at BEFORE UPDATE ON asset_based_calculations
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_results_updated_at BEFORE UPDATE ON valuation_results
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_reconciliation_updated_at BEFORE UPDATE ON reconciliation
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_concluded_updated_at BEFORE UPDATE ON concluded_values
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON SCHEMA model_schema IS 'IVS Valuation Engine - Valuation models, calculations, and results (IVS 105)';
COMMENT ON TABLE valuation_models IS 'Container for valuation models (DCF, Market, Asset-based)';
COMMENT ON TABLE forecasts IS 'Forecast cash flows for DCF models';
COMMENT ON TABLE wacc_calculations IS 'Detailed WACC build-up (CAPM, build-up method)';
COMMENT ON TABLE dcf_calculations IS 'DCF valuation with terminal value and bridge to equity value';
COMMENT ON TABLE market_multiples_calculations IS 'Market approach using comparable company/transaction multiples';
COMMENT ON TABLE asset_based_calculations IS 'Net Asset Value and asset-based valuations';
COMMENT ON TABLE valuation_results IS 'Indications of value from all approaches and methods';
COMMENT ON TABLE scenario_analysis IS 'Scenario analysis (base, upside, downside, stress)';
COMMENT ON TABLE reconciliation IS 'Football field reconciliation and weighting of approaches';
COMMENT ON TABLE concluded_values IS 'Final concluded value with professional judgment and rationale';
