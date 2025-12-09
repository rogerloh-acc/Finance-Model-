-- IVS Valuation Engine - Engagement Schema
-- This schema contains all engagement-level data, Scope of Work, and compliance information

CREATE SCHEMA IF NOT EXISTS engagement_schema;

SET search_path TO engagement_schema;

-- ============================================================================
-- ENGAGEMENTS TABLE
-- Core engagement metadata
-- ============================================================================
CREATE TABLE engagements (
    engagement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_name VARCHAR(255) NOT NULL,
    legal_entity_name VARCHAR(255) NOT NULL,
    registration_number VARCHAR(100),
    group_structure TEXT,
    business_lines TEXT,
    subject_asset_description TEXT NOT NULL,
    jurisdiction VARCHAR(100) NOT NULL,
    valuation_date DATE NOT NULL,
    report_date DATE,
    status VARCHAR(50) DEFAULT 'draft' CHECK (status IN ('draft', 'in_progress', 'review', 'quality_review', 'final', 'archived')),
    created_by UUID NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_dates CHECK (report_date IS NULL OR report_date >= valuation_date)
);

CREATE INDEX idx_engagements_status ON engagements(status);
CREATE INDEX idx_engagements_valuation_date ON engagements(valuation_date);
CREATE INDEX idx_engagements_created_by ON engagements(created_by);

-- ============================================================================
-- SCOPE OF WORK TABLE
-- IVS 101 compliant Scope of Work with versioning
-- ============================================================================
CREATE TABLE scope_of_work (
    sow_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL REFERENCES engagements(engagement_id) ON DELETE CASCADE,
    version INTEGER NOT NULL DEFAULT 1,

    -- What is being valued
    valuation_subject VARCHAR(100) NOT NULL CHECK (valuation_subject IN ('equity', 'enterprise_value', 'share_class', 'business_interest', 'other')),
    valuation_subject_detail TEXT,

    -- Client and users
    client_relationship VARCHAR(50) CHECK (client_relationship IN ('internal', 'external')),
    intended_users TEXT NOT NULL,
    intended_use TEXT NOT NULL,
    intended_use_category VARCHAR(100) NOT NULL CHECK (intended_use_category IN (
        'M&A', 'financial_reporting', 'tax', 'ESOP_409A', 'litigation',
        'restructuring', 'internal_planning', 'regulatory_capital', 'other'
    )),

    -- Basis and premise of value
    basis_of_value VARCHAR(50) NOT NULL CHECK (basis_of_value IN (
        'market_value', 'fair_value_ifrs', 'investment_value',
        'liquidation_value', 'equitable_value', 'synergistic_value', 'other'
    )),
    basis_of_value_detail TEXT,
    premise_of_value VARCHAR(100) NOT NULL CHECK (premise_of_value IN (
        'going_concern', 'orderly_liquidation', 'forced_sale', 'highest_best_use', 'other'
    )),
    premise_of_value_detail TEXT,

    -- Currency and dates
    functional_currency VARCHAR(10) NOT NULL,
    presentation_currency VARCHAR(10) NOT NULL,
    fx_assumptions TEXT,

    -- Assumptions
    standard_assumptions TEXT,
    special_assumptions TEXT,
    limiting_conditions TEXT,

    -- Specialists and external sources
    use_of_specialists BOOLEAN DEFAULT FALSE,
    specialists_detail TEXT,
    service_organisations TEXT,

    -- ESG, Shariah, and regulatory
    esg_applicable BOOLEAN DEFAULT FALSE,
    esg_detail TEXT,
    shariah_compliant BOOLEAN DEFAULT FALSE,
    shariah_detail TEXT,
    regulatory_requirements TEXT,
    sector_specific_regulations TEXT,

    -- Deliverables
    deliverable_types TEXT[], -- array: e.g., ['long_form_report', 'presentation', 'certificate']
    report_language VARCHAR(50) DEFAULT 'British English',

    -- IVS Compliance
    ivs_compliance_statement TEXT NOT NULL DEFAULT
        'The valuation will be prepared in compliance with IVS (2022/2025) except where departures are required by applicable law or regulation.',
    departures_from_ivs TEXT,
    applicable_standards TEXT DEFAULT 'IVS 100, 101, 102, 104, 105, 200',

    -- Version control and locking
    locked BOOLEAN DEFAULT FALSE,
    locked_at TIMESTAMP,
    locked_by UUID,
    approved_by UUID,
    approved_at TIMESTAMP,
    amendment_reason TEXT,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_sow_version UNIQUE (engagement_id, version)
);

CREATE INDEX idx_sow_engagement ON scope_of_work(engagement_id);
CREATE INDEX idx_sow_locked ON scope_of_work(locked);

-- ============================================================================
-- ENGAGEMENT TEAM TABLE
-- Valuers, reviewers, and team members with independence declarations
-- ============================================================================
CREATE TABLE engagement_team (
    team_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL REFERENCES engagements(engagement_id) ON DELETE CASCADE,
    user_id UUID NOT NULL, -- FK to users table (to be created in auth schema)
    role VARCHAR(50) NOT NULL CHECK (role IN ('lead_valuer', 'co_valuer', 'reviewer', 'quality_reviewer', 'assistant', 'admin')),

    -- Independence and conflicts
    independence_declaration TEXT,
    independence_confirmed BOOLEAN DEFAULT FALSE,
    independence_confirmed_at TIMESTAMP,
    conflict_of_interest_checked BOOLEAN DEFAULT FALSE,
    conflict_of_interest_detail TEXT,
    conflict_cleared BOOLEAN DEFAULT FALSE,

    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    assigned_by UUID,

    CONSTRAINT unique_user_per_engagement UNIQUE (engagement_id, user_id)
);

CREATE INDEX idx_team_engagement ON engagement_team(engagement_id);
CREATE INDEX idx_team_user ON engagement_team(user_id);

-- ============================================================================
-- ASSUMPTIONS TABLE
-- All assumptions (standard, special, limiting) with IVS categorization
-- ============================================================================
CREATE TABLE assumptions (
    assumption_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL REFERENCES engagements(engagement_id) ON DELETE CASCADE,
    assumption_type VARCHAR(50) NOT NULL CHECK (assumption_type IN ('standard', 'special', 'limiting')),
    category VARCHAR(100), -- e.g., 'going_concern', 'contract_completion', 'regulatory_approval'
    description TEXT NOT NULL,
    rationale TEXT NOT NULL,
    impact_on_value TEXT,
    data_supporting_assumption TEXT,
    disclosed_in_report BOOLEAN DEFAULT TRUE,
    created_by UUID NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_assumptions_engagement ON assumptions(engagement_id);
CREATE INDEX idx_assumptions_type ON assumptions(assumption_type);

-- ============================================================================
-- ENGAGEMENT RESTRICTIONS TABLE
-- Limitations on use, reliance, and distribution
-- ============================================================================
CREATE TABLE engagement_restrictions (
    restriction_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL REFERENCES engagements(engagement_id) ON DELETE CASCADE,
    restriction_type VARCHAR(50) CHECK (restriction_type IN ('use', 'reliance', 'distribution', 'liability')),
    description TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_restrictions_engagement ON engagement_restrictions(engagement_id);

-- ============================================================================
-- COMPLIANCE CHECKLIST TABLE
-- IVS compliance checklist items and sign-offs
-- ============================================================================
CREATE TABLE compliance_checklist (
    checklist_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL REFERENCES engagements(engagement_id) ON DELETE CASCADE,
    checklist_category VARCHAR(100) NOT NULL, -- e.g., 'IVS_101_SoW', 'IVS_102_Investigations', 'IVS_104_Data'
    checklist_item TEXT NOT NULL,
    required BOOLEAN DEFAULT TRUE,
    completed BOOLEAN DEFAULT FALSE,
    completed_by UUID,
    completed_at TIMESTAMP,
    evidence_reference TEXT,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_checklist_engagement ON compliance_checklist(engagement_id);
CREATE INDEX idx_checklist_category ON compliance_checklist(checklist_category);
CREATE INDEX idx_checklist_completed ON compliance_checklist(completed);

-- ============================================================================
-- FUNCTIONS AND TRIGGERS
-- ============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER update_engagements_updated_at BEFORE UPDATE ON engagements
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sow_updated_at BEFORE UPDATE ON scope_of_work
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_assumptions_updated_at BEFORE UPDATE ON assumptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to prevent SoW modification when locked
CREATE OR REPLACE FUNCTION prevent_locked_sow_modification()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.locked = TRUE THEN
        RAISE EXCEPTION 'Cannot modify locked Scope of Work. Create a new version or unlock first.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_sow_modification_when_locked BEFORE UPDATE ON scope_of_work
    FOR EACH ROW EXECUTE FUNCTION prevent_locked_sow_modification();

-- ============================================================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================================================
COMMENT ON SCHEMA engagement_schema IS 'IVS Valuation Engine - Engagement and Scope of Work data';
COMMENT ON TABLE engagements IS 'Core engagement records with client and subject asset information';
COMMENT ON TABLE scope_of_work IS 'IVS 101 compliant Scope of Work with versioning and locking';
COMMENT ON TABLE engagement_team IS 'Valuation team members with independence declarations (IVS 100)';
COMMENT ON TABLE assumptions IS 'Standard, special, and limiting assumptions (IVS 102)';
COMMENT ON TABLE compliance_checklist IS 'IVS compliance checklist for quality control';
