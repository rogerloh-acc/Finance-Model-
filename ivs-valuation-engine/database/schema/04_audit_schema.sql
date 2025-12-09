-- IVS Valuation Engine - Audit Schema
-- This schema contains complete audit trail, query logs, review comments, and version history

CREATE SCHEMA IF NOT EXISTS audit_schema;

SET search_path TO audit_schema;

-- ============================================================================
-- AUDIT TRAIL TABLE
-- Complete record of all changes to critical data (IVS 100 Quality Control)
-- ============================================================================
CREATE TABLE audit_trail (
    audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL, -- FK to engagement_schema.engagements

    -- What changed
    schema_name VARCHAR(100) NOT NULL,
    table_name VARCHAR(100) NOT NULL,
    record_id UUID NOT NULL,
    action VARCHAR(20) NOT NULL CHECK (action IN ('create', 'update', 'delete', 'approve', 'reject', 'lock', 'unlock')),

    -- Change details
    old_value JSONB,
    new_value JSONB,
    changed_fields TEXT[], -- Array of field names that changed

    -- Who, when, where
    changed_by UUID NOT NULL,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ip_address INET,
    user_agent TEXT,

    -- Context
    change_reason TEXT,
    business_justification TEXT
);

CREATE INDEX idx_audit_engagement ON audit_trail(engagement_id);
CREATE INDEX idx_audit_table ON audit_trail(table_name);
CREATE INDEX idx_audit_record ON audit_trail(record_id);
CREATE INDEX idx_audit_changed_by ON audit_trail(changed_by);
CREATE INDEX idx_audit_changed_at ON audit_trail(changed_at);
CREATE INDEX idx_audit_action ON audit_trail(action);

-- Partition by month for performance (optional, for high-volume deployments)
-- ALTER TABLE audit_trail PARTITION BY RANGE (changed_at);

-- ============================================================================
-- QUERY LOG TABLE
-- Professional scepticism - red flags, queries, and resolutions (IVS 102)
-- ============================================================================
CREATE TABLE query_log (
    query_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    query_number INTEGER, -- Sequential query number within engagement
    query_title VARCHAR(255) NOT NULL,
    query_description TEXT NOT NULL,

    -- Classification
    flagged_by VARCHAR(50) CHECK (flagged_by IN ('system', 'valuer', 'reviewer', 'external')),
    flag_type VARCHAR(50) CHECK (flag_type IN ('red_flag', 'yellow_flag', 'inquiry', 'anomaly', 'inconsistency')),
    severity VARCHAR(20) CHECK (severity IN ('critical', 'high', 'medium', 'low')),

    -- Area of concern
    related_area VARCHAR(100), -- e.g., 'revenue_recognition', 'working_capital', 'related_party', 'margin_analysis'
    related_table VARCHAR(100),
    related_record_id UUID,

    -- Query details
    flagged_data JSONB, -- The actual data point(s) that triggered the flag
    expected_range TEXT,
    deviation_magnitude NUMERIC(10, 2),

    -- Management response
    sent_to_management BOOLEAN DEFAULT FALSE,
    sent_to_management_at TIMESTAMP,
    management_response TEXT,
    management_responded_at TIMESTAMP,
    supporting_evidence TEXT,

    -- Valuer resolution
    valuer_resolution TEXT,
    resolution_status VARCHAR(50) DEFAULT 'open' CHECK (resolution_status IN ('open', 'accepted', 'rejected', 'modified', 'escalated', 'closed')),
    resolution_action VARCHAR(100), -- e.g., 'adjustment_made', 'assumption_updated', 'no_action_required'

    -- Workflow
    created_by UUID NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    assigned_to UUID,
    resolved_by UUID,
    resolved_at TIMESTAMP,

    -- Impact on valuation
    impact_on_value BOOLEAN DEFAULT FALSE,
    impact_description TEXT
);

CREATE INDEX idx_query_engagement ON query_log(engagement_id);
CREATE INDEX idx_query_status ON query_log(resolution_status);
CREATE INDEX idx_query_flagged_by ON query_log(flagged_by);
CREATE INDEX idx_query_created_at ON query_log(created_at);

-- ============================================================================
-- REVIEW COMMENTS TABLE
-- Comments from reviewers (peer review, quality review, etc.)
-- ============================================================================
CREATE TABLE review_comments (
    comment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    review_type VARCHAR(50) CHECK (review_type IN ('peer_review', 'quality_review', 'technical_review', 'compliance_review')),
    review_level VARCHAR(50) CHECK (review_level IN ('first_level', 'second_partner', 'quality_control', 'external')),

    reviewer_id UUID NOT NULL,
    reviewer_name VARCHAR(255),

    -- Comment location
    section VARCHAR(100) NOT NULL, -- e.g., 'scope_of_work', 'data_quality', 'dcf_model', 'assumptions', 'report_draft'
    subsection VARCHAR(255),
    related_table VARCHAR(100),
    related_record_id UUID,

    -- Comment details
    comment_number INTEGER,
    comment_category VARCHAR(50) CHECK (comment_category IN (
        'factual_error', 'calculation_error', 'inconsistency', 'missing_data',
        'insufficient_evidence', 'unclear_rationale', 'ivs_compliance', 'recommendation', 'question'
    )),
    comment_text TEXT NOT NULL,
    severity VARCHAR(20) CHECK (severity IN ('critical', 'high', 'medium', 'low', 'informational')),

    -- Response and resolution
    response_text TEXT,
    responded_by UUID,
    responded_at TIMESTAMP,

    status VARCHAR(50) DEFAULT 'open' CHECK (status IN ('open', 'addressed', 'accepted', 'rejected', 'deferred', 'closed')),
    resolution_notes TEXT,
    resolved_by UUID,
    resolved_at TIMESTAMP,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_review_engagement ON review_comments(engagement_id);
CREATE INDEX idx_review_status ON review_comments(status);
CREATE INDEX idx_review_reviewer ON review_comments(reviewer_id);
CREATE INDEX idx_review_type ON review_comments(review_type);

-- ============================================================================
-- VERSION HISTORY TABLE
-- Track major versions of the engagement (SoW changes, model revisions, etc.)
-- ============================================================================
CREATE TABLE version_history (
    version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    version_number VARCHAR(50) NOT NULL, -- e.g., '1.0', '1.1', '2.0'
    version_type VARCHAR(50) CHECK (version_type IN ('sow', 'model', 'report', 'full_engagement')),
    version_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    changes_summary TEXT NOT NULL,
    change_reason VARCHAR(50) CHECK (change_reason IN (
        'initial', 'amendment', 'correction', 'client_request', 'new_information',
        'scope_change', 'assumption_change', 'data_update', 'review_feedback'
    )),

    -- Snapshot of key data (optional, for critical versions)
    snapshot_data JSONB,

    created_by UUID NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_version UNIQUE (engagement_id, version_number, version_type)
);

CREATE INDEX idx_version_engagement ON version_history(engagement_id);
CREATE INDEX idx_version_date ON version_history(version_date);

-- ============================================================================
-- APPROVAL WORKFLOW TABLE
-- Multi-level approval workflow (optional feature)
-- ============================================================================
CREATE TABLE approval_workflow (
    approval_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    workflow_step VARCHAR(100) NOT NULL, -- e.g., 'data_approval', 'model_approval', 'conclusion_approval', 'report_approval'
    workflow_sequence INTEGER NOT NULL,

    approver_role VARCHAR(50) CHECK (approver_role IN ('lead_valuer', 'reviewer', 'quality_reviewer', 'partner')),
    approver_id UUID,
    approver_name VARCHAR(255),

    approval_status VARCHAR(50) DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected', 'deferred')),
    approval_date TIMESTAMP,
    approval_comments TEXT,

    rejection_reason TEXT,
    conditions TEXT,

    required BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_approval_engagement ON approval_workflow(engagement_id);
CREATE INDEX idx_approval_status ON approval_workflow(approval_status);
CREATE INDEX idx_approval_step ON approval_workflow(workflow_step);

-- ============================================================================
-- REPORT GENERATION LOG TABLE
-- Track all report generations and exports
-- ============================================================================
CREATE TABLE report_generation_log (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    report_type VARCHAR(50) CHECK (report_type IN ('full_report', 'summary_report', 'presentation', 'certificate', 'workpapers', 'audit_trail')),
    report_format VARCHAR(20) CHECK (report_format IN ('pdf', 'docx', 'pptx', 'xlsx', 'html', 'json')),

    report_version VARCHAR(50),
    report_status VARCHAR(50) CHECK (report_status IN ('draft', 'review_copy', 'client_draft', 'final')),

    file_name VARCHAR(255),
    file_path VARCHAR(500),
    file_size BIGINT,

    generated_by UUID NOT NULL,
    generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    watermark VARCHAR(255), -- e.g., 'DRAFT', 'CONFIDENTIAL', 'FOR DISCUSSION ONLY'
    access_restrictions TEXT,

    downloaded BOOLEAN DEFAULT FALSE,
    download_count INTEGER DEFAULT 0,
    last_downloaded_at TIMESTAMP,
    last_downloaded_by UUID
);

CREATE INDEX idx_report_log_engagement ON report_generation_log(engagement_id);
CREATE INDEX idx_report_log_generated_at ON report_generation_log(generated_at);

-- ============================================================================
-- USER ACCESS LOG TABLE
-- Track user access to engagements for security and compliance
-- ============================================================================
CREATE TABLE user_access_log (
    access_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID,

    user_id UUID NOT NULL,
    user_email VARCHAR(255),
    user_role VARCHAR(50),

    access_type VARCHAR(50) CHECK (access_type IN ('view', 'edit', 'approve', 'export', 'delete')),
    accessed_section VARCHAR(100), -- e.g., 'scope_of_work', 'financials', 'models', 'report'

    access_granted BOOLEAN DEFAULT TRUE,
    denial_reason TEXT,

    ip_address INET,
    user_agent TEXT,
    session_id UUID,

    accessed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_access_log_engagement ON user_access_log(engagement_id);
CREATE INDEX idx_access_log_user ON user_access_log(user_id);
CREATE INDEX idx_access_log_accessed_at ON user_access_log(accessed_at);

-- ============================================================================
-- DATA QUALITY CHECKS LOG TABLE
-- Log all automated data quality checks and their results
-- ============================================================================
CREATE TABLE data_quality_checks_log (
    check_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    check_name VARCHAR(255) NOT NULL,
    check_category VARCHAR(100) CHECK (check_category IN (
        'completeness', 'accuracy', 'consistency', 'integrity', 'timeliness', 'reasonableness'
    )),
    check_type VARCHAR(100), -- e.g., 'balance_sheet_check', 'cash_reconciliation', 'margin_analysis'

    check_description TEXT,
    expected_result TEXT,
    actual_result TEXT,

    check_status VARCHAR(50) CHECK (check_status IN ('passed', 'failed', 'warning', 'not_applicable')),
    failure_reason TEXT,

    related_table VARCHAR(100),
    related_record_id UUID,

    auto_remediation_attempted BOOLEAN DEFAULT FALSE,
    remediation_action TEXT,

    reviewed_by UUID,
    review_notes TEXT,

    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_quality_checks_engagement ON data_quality_checks_log(engagement_id);
CREATE INDEX idx_quality_checks_status ON data_quality_checks_log(check_status);
CREATE INDEX idx_quality_checks_category ON data_quality_checks_log(check_category);

-- ============================================================================
-- COMPLIANCE EVIDENCE TABLE
-- Repository for IVS compliance evidence and documentation
-- ============================================================================
CREATE TABLE compliance_evidence (
    evidence_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID NOT NULL,

    ivs_standard VARCHAR(100) NOT NULL, -- e.g., 'IVS 101', 'IVS 102', 'IVS 104', 'IVS 105', 'IVS 200'
    ivs_requirement TEXT NOT NULL,

    evidence_type VARCHAR(100) CHECK (evidence_type IN (
        'document', 'calculation', 'analysis', 'declaration', 'approval', 'external_data', 'correspondence'
    )),
    evidence_description TEXT NOT NULL,

    evidence_location TEXT, -- File path, table reference, or document ID
    evidence_reference UUID, -- FK to related record

    compliance_status VARCHAR(50) CHECK (compliance_status IN ('compliant', 'partial', 'not_compliant', 'not_applicable')),
    compliance_notes TEXT,

    verified_by UUID,
    verified_at TIMESTAMP,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_compliance_evidence_engagement ON compliance_evidence(engagement_id);
CREATE INDEX idx_compliance_evidence_standard ON compliance_evidence(ivs_standard);
CREATE INDEX idx_compliance_evidence_status ON compliance_evidence(compliance_status);

-- ============================================================================
-- EXCEPTION LOG TABLE
-- Log system errors, exceptions, and technical issues
-- ============================================================================
CREATE TABLE exception_log (
    exception_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engagement_id UUID,

    exception_type VARCHAR(100) NOT NULL, -- e.g., 'validation_error', 'calculation_error', 'api_error', 'data_error'
    exception_severity VARCHAR(20) CHECK (exception_severity IN ('critical', 'high', 'medium', 'low')),

    error_message TEXT NOT NULL,
    error_stack_trace TEXT,
    error_code VARCHAR(50),

    module VARCHAR(100), -- e.g., 'dcf_calculator', 'wacc_builder', 'report_generator'
    function_name VARCHAR(255),

    user_id UUID,
    session_id UUID,

    resolution_status VARCHAR(50) DEFAULT 'open' CHECK (resolution_status IN ('open', 'investigating', 'resolved', 'deferred', 'cannot_reproduce')),
    resolution_notes TEXT,
    resolved_by UUID,
    resolved_at TIMESTAMP,

    occurred_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_exception_engagement ON exception_log(engagement_id);
CREATE INDEX idx_exception_severity ON exception_log(exception_severity);
CREATE INDEX idx_exception_status ON exception_log(resolution_status);
CREATE INDEX idx_exception_occurred_at ON exception_log(occurred_at);

-- ============================================================================
-- TRIGGERS
-- ============================================================================
CREATE TRIGGER update_review_comments_updated_at BEFORE UPDATE ON review_comments
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

CREATE TRIGGER update_approval_workflow_updated_at BEFORE UPDATE ON approval_workflow
    FOR EACH ROW EXECUTE FUNCTION engagement_schema.update_updated_at_column();

-- ============================================================================
-- FUNCTIONS FOR AUDIT TRAIL
-- ============================================================================

-- Generic function to create audit trail entries (can be called from application)
CREATE OR REPLACE FUNCTION create_audit_trail_entry(
    p_engagement_id UUID,
    p_schema_name VARCHAR,
    p_table_name VARCHAR,
    p_record_id UUID,
    p_action VARCHAR,
    p_old_value JSONB,
    p_new_value JSONB,
    p_changed_by UUID,
    p_change_reason TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_audit_id UUID;
BEGIN
    INSERT INTO audit_trail (
        engagement_id, schema_name, table_name, record_id, action,
        old_value, new_value, changed_by, change_reason
    ) VALUES (
        p_engagement_id, p_schema_name, p_table_name, p_record_id, p_action,
        p_old_value, p_new_value, p_changed_by, p_change_reason
    ) RETURNING audit_id INTO v_audit_id;

    RETURN v_audit_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEWS FOR COMMON QUERIES
-- ============================================================================

-- View: Open queries requiring attention
CREATE VIEW open_queries AS
SELECT
    q.query_id,
    q.engagement_id,
    q.query_number,
    q.query_title,
    q.flag_type,
    q.severity,
    q.resolution_status,
    q.created_at,
    q.assigned_to,
    CASE
        WHEN q.sent_to_management AND q.management_response IS NULL THEN 'Awaiting management response'
        WHEN q.management_response IS NOT NULL AND q.valuer_resolution IS NULL THEN 'Awaiting valuer resolution'
        ELSE 'In progress'
    END as current_stage
FROM query_log q
WHERE q.resolution_status IN ('open', 'escalated')
ORDER BY
    CASE q.severity
        WHEN 'critical' THEN 1
        WHEN 'high' THEN 2
        WHEN 'medium' THEN 3
        WHEN 'low' THEN 4
    END,
    q.created_at;

-- View: Pending review comments
CREATE VIEW pending_review_comments AS
SELECT
    c.comment_id,
    c.engagement_id,
    c.review_type,
    c.section,
    c.comment_category,
    c.severity,
    c.comment_text,
    c.status,
    c.reviewer_name,
    c.created_at
FROM review_comments c
WHERE c.status IN ('open', 'deferred')
ORDER BY
    CASE c.severity
        WHEN 'critical' THEN 1
        WHEN 'high' THEN 2
        WHEN 'medium' THEN 3
        WHEN 'low' THEN 4
        WHEN 'informational' THEN 5
    END,
    c.created_at;

-- View: Compliance status summary per engagement
CREATE VIEW compliance_summary AS
SELECT
    e.engagement_id,
    COUNT(DISTINCT ce.ivs_standard) as standards_addressed,
    COUNT(CASE WHEN ce.compliance_status = 'compliant' THEN 1 END) as compliant_count,
    COUNT(CASE WHEN ce.compliance_status = 'partial' THEN 1 END) as partial_count,
    COUNT(CASE WHEN ce.compliance_status = 'not_compliant' THEN 1 END) as non_compliant_count,
    ROUND(
        100.0 * COUNT(CASE WHEN ce.compliance_status = 'compliant' THEN 1 END) /
        NULLIF(COUNT(*), 0), 2
    ) as compliance_percentage
FROM compliance_evidence ce
GROUP BY ce.engagement_id;

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON SCHEMA audit_schema IS 'IVS Valuation Engine - Complete audit trail, quality control, and compliance evidence (IVS 100)';
COMMENT ON TABLE audit_trail IS 'Complete audit trail of all changes to critical data';
COMMENT ON TABLE query_log IS 'Professional scepticism - queries, red flags, and resolutions (IVS 102)';
COMMENT ON TABLE review_comments IS 'Review comments from peer review, quality review, etc.';
COMMENT ON TABLE version_history IS 'Version control for SoW, models, and reports';
COMMENT ON TABLE compliance_evidence IS 'Repository of IVS compliance evidence';
COMMENT ON TABLE data_quality_checks_log IS 'Automated data quality check results';
COMMENT ON VIEW open_queries IS 'All open queries requiring attention, prioritized by severity';
COMMENT ON VIEW compliance_summary IS 'Compliance status summary per engagement';
