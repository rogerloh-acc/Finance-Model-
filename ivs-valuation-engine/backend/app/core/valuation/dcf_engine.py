"""
IVS Valuation Engine - DCF Engine
Discounted Cash Flow valuation module (Income Approach - IVS 105)
Supports FCFF, FCFE, and Dividend Discount models
"""

import numpy as np
import pandas as pd
from typing import List, Optional, Dict, Any
from dataclasses import dataclass, field
from enum import Enum


class DCFType(str, Enum):
    """Type of DCF model"""
    FCFF = "fcff"  # Free Cash Flow to Firm
    FCFE = "fcfe"  # Free Cash Flow to Equity
    DIVIDEND = "dividend"  # Dividend Discount Model


class DiscountConvention(str, Enum):
    """Discounting convention"""
    YEAR_END = "year_end"  # Discount at year end
    MID_YEAR = "mid_year"  # Mid-year convention (more accurate)


class TerminalValueMethod(str, Enum):
    """Terminal value calculation method"""
    GORDON_GROWTH = "gordon_growth"  # Perpetuity growth model
    EXIT_MULTIPLE = "exit_multiple"  # Exit multiple approach
    H_MODEL = "h_model"  # Two-stage H-model (for declining growth)


@dataclass
class CashFlowProjection:
    """Single period cash flow projection"""
    period: int  # Year number (1, 2, 3, ...)
    revenue: float
    ebitda: float
    ebit: float
    nopat: float  # Net Operating Profit After Tax
    depreciation: float
    capex: float
    working_capital_change: float
    fcff: Optional[float] = None  # Free Cash Flow to Firm
    fcfe: Optional[float] = None  # Free Cash Flow to Equity

    def calculate_fcff(self) -> float:
        """Calculate FCFF: NOPAT + D&A - Capex - ΔWC"""
        self.fcff = self.nopat + self.depreciation - self.capex - self.working_capital_change
        return self.fcff

    def calculate_fcfe(self, interest_expense: float, net_borrowing: float) -> float:
        """Calculate FCFE: FCFF - Interest(1-T) + Net Borrowing"""
        if self.fcff is None:
            self.calculate_fcff()
        # Note: Interest after-tax is already considered in NOPAT for FCFF
        # For FCFE, we need to adjust
        self.fcfe = self.fcff + net_borrowing
        return self.fcfe


@dataclass
class DCFInputs:
    """Input parameters for DCF valuation"""

    # Cash flow projections
    projections: List[CashFlowProjection]

    # Discount rate
    discount_rate: float  # WACC for FCFF, Cost of Equity for FCFE
    discount_convention: DiscountConvention = DiscountConvention.MID_YEAR

    # Terminal value parameters
    terminal_value_method: TerminalValueMethod = TerminalValueMethod.GORDON_GROWTH
    terminal_growth_rate: Optional[float] = None  # For Gordon Growth
    terminal_multiple: Optional[float] = None  # For Exit Multiple
    terminal_multiple_metric: Optional[str] = None  # e.g., 'EBITDA', 'EBIT', 'Revenue'

    # Enterprise value to equity value bridge (for FCFF)
    cash_and_equivalents: float = 0.0
    non_operating_assets: float = 0.0
    debt: float = 0.0
    minority_interest: float = 0.0
    preferred_equity: float = 0.0

    # Per-share calculation
    shares_outstanding: Optional[int] = None

    # Currency
    currency: str = "MYR"


@dataclass
class DCFResults:
    """Results of DCF valuation"""

    # Summary values
    enterprise_value: float
    equity_value: float
    value_per_share: Optional[float] = None

    # Detailed calculations
    pv_explicit_period: float = 0.0
    pv_terminal_value: float = 0.0
    terminal_value: float = 0.0
    terminal_fcf: float = 0.0

    # Year-by-year detail
    cash_flows: pd.DataFrame = field(default_factory=pd.DataFrame)

    # Implied metrics (for reasonableness check)
    implied_ev_revenue: Optional[float] = None
    implied_ev_ebitda: Optional[float] = None
    implied_ev_ebit: Optional[float] = None
    implied_pe: Optional[float] = None

    # EV to Equity bridge
    bridge: Dict[str, float] = field(default_factory=dict)

    # Metadata
    dcf_type: DCFType = DCFType.FCFF
    discount_rate: float = 0.0
    terminal_growth_rate: Optional[float] = None
    currency: str = "MYR"


class DCFEngine:
    """
    DCF Valuation Engine
    Implements IVS 105 Income Approach with DCF methodology
    """

    def __init__(self, inputs: DCFInputs, dcf_type: DCFType = DCFType.FCFF):
        self.inputs = inputs
        self.dcf_type = dcf_type
        self.results: Optional[DCFResults] = None

    def calculate_dcf(self) -> DCFResults:
        """
        Execute full DCF valuation

        Returns:
            DCFResults: Complete valuation results
        """
        # Step 1: Prepare cash flows
        cash_flows_df = self._prepare_cash_flows()

        # Step 2: Calculate discount factors
        cash_flows_df = self._calculate_discount_factors(cash_flows_df)

        # Step 3: Calculate present values
        cash_flows_df = self._calculate_present_values(cash_flows_df)

        # Step 4: Calculate terminal value
        terminal_value, terminal_fcf = self._calculate_terminal_value(cash_flows_df)

        # Step 5: Discount terminal value
        terminal_year = len(self.inputs.projections)
        if self.inputs.discount_convention == DiscountConvention.MID_YEAR:
            terminal_discount_factor = 1 / ((1 + self.inputs.discount_rate) ** (terminal_year - 0.5))
        else:
            terminal_discount_factor = 1 / ((1 + self.inputs.discount_rate) ** terminal_year)

        pv_terminal_value = terminal_value * terminal_discount_factor

        # Step 6: Sum to get enterprise/equity value
        pv_explicit_period = cash_flows_df['pv_cash_flow'].sum()
        total_pv = pv_explicit_period + pv_terminal_value

        if self.dcf_type == DCFType.FCFF:
            enterprise_value = total_pv
            equity_value = self._calculate_equity_value_from_ev(enterprise_value)
        else:  # FCFE or Dividend
            equity_value = total_pv
            enterprise_value = equity_value + self.inputs.debt - self.inputs.cash_and_equivalents

        # Step 7: Per-share value
        value_per_share = None
        if self.inputs.shares_outstanding:
            value_per_share = equity_value / self.inputs.shares_outstanding

        # Step 8: Calculate implied multiples
        implied_metrics = self._calculate_implied_multiples(
            enterprise_value,
            equity_value,
            cash_flows_df
        )

        # Step 9: Create bridge (for FCFF)
        bridge = {}
        if self.dcf_type == DCFType.FCFF:
            bridge = {
                "enterprise_value": enterprise_value,
                "plus_cash": self.inputs.cash_and_equivalents,
                "plus_non_operating_assets": self.inputs.non_operating_assets,
                "less_debt": -self.inputs.debt,
                "less_minority_interest": -self.inputs.minority_interest,
                "less_preferred_equity": -self.inputs.preferred_equity,
                "equity_value": equity_value
            }

        # Create results
        self.results = DCFResults(
            enterprise_value=enterprise_value,
            equity_value=equity_value,
            value_per_share=value_per_share,
            pv_explicit_period=pv_explicit_period,
            pv_terminal_value=pv_terminal_value,
            terminal_value=terminal_value,
            terminal_fcf=terminal_fcf,
            cash_flows=cash_flows_df,
            implied_ev_revenue=implied_metrics.get('ev_revenue'),
            implied_ev_ebitda=implied_metrics.get('ev_ebitda'),
            implied_ev_ebit=implied_metrics.get('ev_ebit'),
            implied_pe=implied_metrics.get('pe'),
            bridge=bridge,
            dcf_type=self.dcf_type,
            discount_rate=self.inputs.discount_rate,
            terminal_growth_rate=self.inputs.terminal_growth_rate,
            currency=self.inputs.currency
        )

        return self.results

    def _prepare_cash_flows(self) -> pd.DataFrame:
        """Prepare cash flows DataFrame"""
        data = []
        for proj in self.inputs.projections:
            if self.dcf_type == DCFType.FCFF:
                if proj.fcff is None:
                    proj.calculate_fcff()
                cash_flow = proj.fcff
            else:
                # For FCFE, need additional interest and borrowing data
                # Simplified: use fcff as proxy (should be enhanced)
                if proj.fcfe is not None:
                    cash_flow = proj.fcfe
                else:
                    if proj.fcff is None:
                        proj.calculate_fcff()
                    cash_flow = proj.fcff

            data.append({
                'period': proj.period,
                'revenue': proj.revenue,
                'ebitda': proj.ebitda,
                'ebit': proj.ebit,
                'nopat': proj.nopat,
                'depreciation': proj.depreciation,
                'capex': proj.capex,
                'wc_change': proj.working_capital_change,
                'cash_flow': cash_flow
            })

        return pd.DataFrame(data)

    def _calculate_discount_factors(self, df: pd.DataFrame) -> pd.DataFrame:
        """Calculate discount factors for each period"""
        discount_rate = self.inputs.discount_rate

        if self.inputs.discount_convention == DiscountConvention.MID_YEAR:
            # Mid-year convention: discount by (n - 0.5)
            df['discount_factor'] = 1 / ((1 + discount_rate) ** (df['period'] - 0.5))
        else:
            # Year-end convention: discount by n
            df['discount_factor'] = 1 / ((1 + discount_rate) ** df['period'])

        return df

    def _calculate_present_values(self, df: pd.DataFrame) -> pd.DataFrame:
        """Calculate present value of cash flows"""
        df['pv_cash_flow'] = df['cash_flow'] * df['discount_factor']
        return df

    def _calculate_terminal_value(self, df: pd.DataFrame) -> tuple[float, float]:
        """
        Calculate terminal value

        Returns:
            tuple: (terminal_value, terminal_fcf)
        """
        if self.inputs.terminal_value_method == TerminalValueMethod.GORDON_GROWTH:
            return self._gordon_growth_terminal_value(df)
        elif self.inputs.terminal_value_method == TerminalValueMethod.EXIT_MULTIPLE:
            return self._exit_multiple_terminal_value(df)
        elif self.inputs.terminal_value_method == TerminalValueMethod.H_MODEL:
            return self._h_model_terminal_value(df)
        else:
            raise ValueError(f"Unknown terminal value method: {self.inputs.terminal_value_method}")

    def _gordon_growth_terminal_value(self, df: pd.DataFrame) -> tuple[float, float]:
        """
        Gordon Growth Model: TV = FCF_{n+1} / (WACC - g)
        where FCF_{n+1} = FCF_n * (1 + g)
        """
        if self.inputs.terminal_growth_rate is None:
            raise ValueError("Terminal growth rate required for Gordon Growth model")

        g = self.inputs.terminal_growth_rate
        r = self.inputs.discount_rate

        if g >= r:
            raise ValueError(f"Terminal growth rate ({g:.2%}) must be less than discount rate ({r:.2%})")

        # Get last period cash flow
        last_fcf = df.iloc[-1]['cash_flow']

        # Calculate terminal year FCF (year n+1)
        terminal_fcf = last_fcf * (1 + g)

        # Calculate terminal value
        terminal_value = terminal_fcf / (r - g)

        return terminal_value, terminal_fcf

    def _exit_multiple_terminal_value(self, df: pd.DataFrame) -> tuple[float, float]:
        """
        Exit Multiple: TV = Terminal Metric × Multiple
        e.g., TV = EBITDA_terminal × EV/EBITDA multiple
        """
        if self.inputs.terminal_multiple is None:
            raise ValueError("Terminal multiple required for Exit Multiple method")

        if self.inputs.terminal_multiple_metric is None:
            raise ValueError("Terminal multiple metric required (e.g., 'EBITDA', 'EBIT')")

        multiple = self.inputs.terminal_multiple
        metric = self.inputs.terminal_multiple_metric.lower()

        # Get terminal year metric
        if metric == 'ebitda':
            terminal_metric = df.iloc[-1]['ebitda']
        elif metric == 'ebit':
            terminal_metric = df.iloc[-1]['ebit']
        elif metric == 'revenue':
            terminal_metric = df.iloc[-1]['revenue']
        elif metric == 'fcf' or metric == 'cash_flow':
            terminal_metric = df.iloc[-1]['cash_flow']
        else:
            raise ValueError(f"Unknown terminal metric: {metric}")

        terminal_value = terminal_metric * multiple
        terminal_fcf = df.iloc[-1]['cash_flow']  # Not directly used, but for reference

        return terminal_value, terminal_fcf

    def _h_model_terminal_value(self, df: pd.DataFrame) -> tuple[float, float]:
        """
        H-Model for declining growth
        TV = FCF × (1 + g_L) × (1 + H × (g_S - g_L)) / (r - g_L)
        where g_S = short-term growth, g_L = long-term growth, H = half-life

        Simplified implementation - can be enhanced
        """
        # For now, fall back to Gordon Growth
        # A full implementation would require additional parameters
        return self._gordon_growth_terminal_value(df)

    def _calculate_equity_value_from_ev(self, enterprise_value: float) -> float:
        """
        Bridge from Enterprise Value to Equity Value
        Equity Value = EV + Cash - Debt - Minority Interest - Preferred Equity + Non-Operating Assets
        """
        equity_value = (
            enterprise_value
            + self.inputs.cash_and_equivalents
            + self.inputs.non_operating_assets
            - self.inputs.debt
            - self.inputs.minority_interest
            - self.inputs.preferred_equity
        )

        return equity_value

    def _calculate_implied_multiples(
        self,
        enterprise_value: float,
        equity_value: float,
        df: pd.DataFrame
    ) -> Dict[str, Optional[float]]:
        """Calculate implied valuation multiples for reasonableness check"""

        # Use last-twelve-months (LTM) or latest year
        ltm_revenue = df.iloc[-1]['revenue']
        ltm_ebitda = df.iloc[-1]['ebitda']
        ltm_ebit = df.iloc[-1]['ebit']
        ltm_nopat = df.iloc[-1]['nopat']

        implied_multiples = {}

        if ltm_revenue > 0:
            implied_multiples['ev_revenue'] = enterprise_value / ltm_revenue

        if ltm_ebitda > 0:
            implied_multiples['ev_ebitda'] = enterprise_value / ltm_ebitda

        if ltm_ebit > 0:
            implied_multiples['ev_ebit'] = enterprise_value / ltm_ebit

        if ltm_nopat > 0:
            implied_multiples['pe'] = equity_value / ltm_nopat

        return implied_multiples

    def sensitivity_analysis_2d(
        self,
        wacc_range: tuple[float, float] = (0.06, 0.14),
        growth_range: tuple[float, float] = (0.01, 0.04),
        steps: int = 5
    ) -> pd.DataFrame:
        """
        2D sensitivity analysis (WACC vs Terminal Growth)

        Args:
            wacc_range: (min_wacc, max_wacc)
            growth_range: (min_growth, max_growth)
            steps: Number of steps for each variable

        Returns:
            DataFrame with sensitivity grid
        """
        wacc_values = np.linspace(wacc_range[0], wacc_range[1], steps)
        growth_values = np.linspace(growth_range[0], growth_range[1], steps)

        sensitivity_grid = []

        original_wacc = self.inputs.discount_rate
        original_growth = self.inputs.terminal_growth_rate

        for wacc in wacc_values:
            row = []
            for growth in growth_values:
                # Temporarily change parameters
                self.inputs.discount_rate = wacc
                self.inputs.terminal_growth_rate = growth

                # Recalculate
                try:
                    results = self.calculate_dcf()
                    value = results.enterprise_value if self.dcf_type == DCFType.FCFF else results.equity_value
                    row.append(value)
                except:
                    row.append(None)

            sensitivity_grid.append(row)

        # Restore original values
        self.inputs.discount_rate = original_wacc
        self.inputs.terminal_growth_rate = original_growth

        # Create DataFrame
        df_sensitivity = pd.DataFrame(
            sensitivity_grid,
            index=[f"WACC: {w:.2%}" for w in wacc_values],
            columns=[f"Growth: {g:.2%}" for g in growth_values]
        )

        return df_sensitivity


# Example usage
if __name__ == "__main__":
    # Example DCF calculation
    projections = [
        CashFlowProjection(
            period=1,
            revenue=1000,
            ebitda=200,
            ebit=150,
            nopat=112.5,  # EBIT * (1 - 0.25 tax rate)
            depreciation=50,
            capex=60,
            working_capital_change=10
        ),
        CashFlowProjection(
            period=2,
            revenue=1100,
            ebitda=230,
            ebit=175,
            nopat=131.25,
            depreciation=55,
            capex=65,
            working_capital_change=12
        ),
        CashFlowProjection(
            period=3,
            revenue=1200,
            ebitda=260,
            ebit=200,
            nopat=150,
            depreciation=60,
            capex=70,
            working_capital_change=15
        ),
        CashFlowProjection(
            period=4,
            revenue=1300,
            ebitda=285,
            ebit=220,
            nopat=165,
            depreciation=65,
            capex=75,
            working_capital_change=18
        ),
        CashFlowProjection(
            period=5,
            revenue=1400,
            ebitda=310,
            ebit=240,
            nopat=180,
            depreciation=70,
            capex=80,
            working_capital_change=20
        ),
    ]

    inputs = DCFInputs(
        projections=projections,
        discount_rate=0.10,  # 10% WACC
        terminal_growth_rate=0.02,  # 2% perpetual growth
        cash_and_equivalents=50,
        debt=200,
        shares_outstanding=100_000_000
    )

    engine = DCFEngine(inputs, dcf_type=DCFType.FCFF)
    results = engine.calculate_dcf()

    print(f"Enterprise Value: {results.enterprise_value:,.2f}")
    print(f"Equity Value: {results.equity_value:,.2f}")
    print(f"Value Per Share: {results.value_per_share:.4f}")
    print(f"\nImplied EV/EBITDA: {results.implied_ev_ebitda:.2f}x")
    print(f"\nCash Flow Detail:")
    print(results.cash_flows)
