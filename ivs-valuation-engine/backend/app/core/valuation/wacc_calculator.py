"""
IVS Valuation Engine - WACC Calculator
Weighted Average Cost of Capital calculation module
Supports CAPM, Build-up method, and Malaysian market specifics
"""

import numpy as np
from typing import Optional, Dict, Any
from dataclasses import dataclass
from enum import Enum


class CAPMMethod(str, Enum):
    """CAPM calculation methods"""
    STANDARD = "standard"
    MODIFIED = "modified"  # With country risk premium
    BUILD_UP = "build_up"  # Build-up method for private companies


class ReleveringFormula(str, Enum):
    """Formula for relevering beta"""
    HAMADA = "hamada"  # Standard: βL = βU * (1 + (1-T) * D/E)
    HARRIS_PRINGLE = "harris_pringle"  # βL = βU * (1 + D/E)
    PRACTITIONERS = "practitioners"  # βL = βU * (1 + D/V)


@dataclass
class WACCInputs:
    """Input parameters for WACC calculation"""

    # Risk-free rate
    risk_free_rate: float  # As decimal (e.g., 0.04 for 4%)
    risk_free_rate_source: str = "Malaysia 10Y Government Bond"

    # Equity risk premium
    equity_risk_premium: float  # As decimal
    erp_source: str = "Damodaran"

    # Country risk premium (for emerging markets)
    country_risk_premium: float = 0.0
    country: str = "Malaysia"

    # Beta
    unlevered_beta: Optional[float] = None
    levered_beta: Optional[float] = None
    beta_source: str = "Comparable companies"
    relevering_formula: ReleveringFormula = ReleveringFormula.HAMADA

    # Size premium (for small/mid-cap companies)
    size_premium: float = 0.0
    size_premium_source: Optional[str] = None

    # Company-specific risk premium
    company_specific_premium: float = 0.0
    company_specific_rationale: Optional[str] = None

    # Capital structure
    target_debt_to_equity: Optional[float] = None  # D/E ratio
    target_debt_to_value: Optional[float] = None  # D/V ratio
    market_value_equity: Optional[float] = None
    market_value_debt: Optional[float] = None

    # Cost of debt
    cost_of_debt_pretax: Optional[float] = None
    marginal_tax_rate: float = 0.24  # Malaysia corporate tax rate


@dataclass
class WACCResults:
    """Results of WACC calculation"""

    # Cost of equity components
    risk_free_rate: float
    equity_risk_premium: float
    country_risk_premium: float
    levered_beta: float
    size_premium: float
    company_specific_premium: float

    # Cost of equity
    cost_of_equity: float

    # Cost of debt
    cost_of_debt_pretax: float
    cost_of_debt_aftertax: float
    marginal_tax_rate: float

    # Capital structure weights
    debt_weight: float
    equity_weight: float

    # WACC
    wacc: float

    # Detailed breakdown
    breakdown: Dict[str, Any]


class WACCCalculator:
    """
    WACC Calculator implementing CAPM and Build-up methods
    Compliant with IVS cost of capital estimation principles
    """

    def __init__(self, inputs: WACCInputs, method: CAPMMethod = CAPMMethod.STANDARD):
        self.inputs = inputs
        self.method = method

    def calculate_cost_of_equity(self) -> float:
        """
        Calculate cost of equity using CAPM or Build-up method

        CAPM: Re = Rf + β * (Rm - Rf) + CRP + Size Premium + Company-Specific Premium
        Build-up: Re = Rf + ERP + CRP + Size Premium + Company-Specific Premium

        Returns:
            float: Cost of equity as decimal
        """
        rf = self.inputs.risk_free_rate
        erp = self.inputs.equity_risk_premium
        crp = self.inputs.country_risk_premium
        size_prem = self.inputs.size_premium
        company_prem = self.inputs.company_specific_premium

        if self.method == CAPMMethod.BUILD_UP:
            # Build-up method (no beta, used for private/small companies)
            cost_of_equity = rf + erp + crp + size_prem + company_prem

        else:
            # CAPM (standard or modified)
            # Need to calculate levered beta first
            levered_beta = self._get_levered_beta()

            if self.method == CAPMMethod.MODIFIED:
                # Modified CAPM with country risk premium
                cost_of_equity = rf + levered_beta * erp + crp + size_prem + company_prem
            else:
                # Standard CAPM
                cost_of_equity = rf + levered_beta * (erp + crp) + size_prem + company_prem

        return cost_of_equity

    def _get_levered_beta(self) -> float:
        """
        Calculate or retrieve levered beta

        If unlevered beta is provided, relever it using target capital structure.
        If levered beta is provided, use it directly.

        Returns:
            float: Levered beta
        """
        if self.inputs.levered_beta is not None:
            return self.inputs.levered_beta

        if self.inputs.unlevered_beta is None:
            raise ValueError("Either levered_beta or unlevered_beta must be provided")

        # Relever beta using target capital structure
        unlevered_beta = self.inputs.unlevered_beta
        D_E = self._get_debt_to_equity_ratio()
        tax_rate = self.inputs.marginal_tax_rate

        if self.inputs.relevering_formula == ReleveringFormula.HAMADA:
            # Hamada: βL = βU * (1 + (1-T) * D/E)
            levered_beta = unlevered_beta * (1 + (1 - tax_rate) * D_E)

        elif self.inputs.relevering_formula == ReleveringFormula.HARRIS_PRINGLE:
            # Harris-Pringle: βL = βU * (1 + D/E)
            levered_beta = unlevered_beta * (1 + D_E)

        elif self.inputs.relevering_formula == ReleveringFormula.PRACTITIONERS:
            # Practitioners method: βL = βU * (1 + D/V)
            D_V = self._get_debt_to_value_ratio()
            levered_beta = unlevered_beta * (1 + D_V)

        else:
            raise ValueError(f"Unknown relevering formula: {self.inputs.relevering_formula}")

        return levered_beta

    def _get_debt_to_equity_ratio(self) -> float:
        """Get target debt-to-equity ratio"""
        if self.inputs.target_debt_to_equity is not None:
            return self.inputs.target_debt_to_equity

        if self.inputs.market_value_debt is not None and self.inputs.market_value_equity is not None:
            return self.inputs.market_value_debt / self.inputs.market_value_equity

        # Default to 0 if not provided
        return 0.0

    def _get_debt_to_value_ratio(self) -> float:
        """Get target debt-to-value ratio"""
        if self.inputs.target_debt_to_value is not None:
            return self.inputs.target_debt_to_value

        if self.inputs.market_value_debt is not None and self.inputs.market_value_equity is not None:
            total_value = self.inputs.market_value_debt + self.inputs.market_value_equity
            return self.inputs.market_value_debt / total_value

        # Default to 0 if not provided
        return 0.0

    def _get_capital_structure_weights(self) -> tuple[float, float]:
        """
        Get capital structure weights (debt weight, equity weight)

        Returns:
            tuple: (debt_weight, equity_weight) as decimals summing to 1.0
        """
        if self.inputs.market_value_debt is not None and self.inputs.market_value_equity is not None:
            total_value = self.inputs.market_value_debt + self.inputs.market_value_equity
            debt_weight = self.inputs.market_value_debt / total_value
            equity_weight = self.inputs.market_value_equity / total_value
        elif self.inputs.target_debt_to_value is not None:
            debt_weight = self.inputs.target_debt_to_value
            equity_weight = 1 - debt_weight
        elif self.inputs.target_debt_to_equity is not None:
            D_E = self.inputs.target_debt_to_equity
            debt_weight = D_E / (1 + D_E)
            equity_weight = 1 / (1 + D_E)
        else:
            # Default to 100% equity if no debt information
            debt_weight = 0.0
            equity_weight = 1.0

        return debt_weight, equity_weight

    def calculate_cost_of_debt(self) -> tuple[float, float]:
        """
        Calculate after-tax cost of debt

        Returns:
            tuple: (pretax_cost_of_debt, aftertax_cost_of_debt)
        """
        if self.inputs.cost_of_debt_pretax is None:
            # If not provided, could estimate from credit spread + risk-free rate
            # For now, default to risk-free rate + 200 bps
            pretax_cod = self.inputs.risk_free_rate + 0.02
        else:
            pretax_cod = self.inputs.cost_of_debt_pretax

        aftertax_cod = pretax_cod * (1 - self.inputs.marginal_tax_rate)

        return pretax_cod, aftertax_cod

    def calculate_wacc(self) -> WACCResults:
        """
        Calculate WACC using the formula:
        WACC = (E/V) * Re + (D/V) * Rd * (1 - T)

        Returns:
            WACCResults: Complete WACC calculation results
        """
        # Calculate cost of equity
        cost_of_equity = self.calculate_cost_of_equity()

        # Calculate cost of debt
        pretax_cod, aftertax_cod = self.calculate_cost_of_debt()

        # Get capital structure weights
        debt_weight, equity_weight = self._get_capital_structure_weights()

        # Calculate WACC
        wacc = (equity_weight * cost_of_equity) + (debt_weight * aftertax_cod)

        # Get levered beta for reporting
        if self.method != CAPMMethod.BUILD_UP:
            levered_beta = self._get_levered_beta()
        else:
            levered_beta = 0.0  # Not applicable for build-up method

        # Prepare detailed breakdown
        breakdown = {
            "method": self.method,
            "relevering_formula": self.inputs.relevering_formula if self.method != CAPMMethod.BUILD_UP else None,
            "cost_of_equity_calculation": self._get_cost_of_equity_breakdown(cost_of_equity, levered_beta),
            "cost_of_debt_calculation": {
                "pretax_cost_of_debt": pretax_cod,
                "tax_rate": self.inputs.marginal_tax_rate,
                "aftertax_cost_of_debt": aftertax_cod
            },
            "capital_structure": {
                "equity_weight": equity_weight,
                "debt_weight": debt_weight,
                "equity_value": self.inputs.market_value_equity,
                "debt_value": self.inputs.market_value_debt
            },
            "wacc_calculation": {
                "equity_component": equity_weight * cost_of_equity,
                "debt_component": debt_weight * aftertax_cod,
                "wacc": wacc
            }
        }

        # Create results object
        results = WACCResults(
            risk_free_rate=self.inputs.risk_free_rate,
            equity_risk_premium=self.inputs.equity_risk_premium,
            country_risk_premium=self.inputs.country_risk_premium,
            levered_beta=levered_beta,
            size_premium=self.inputs.size_premium,
            company_specific_premium=self.inputs.company_specific_premium,
            cost_of_equity=cost_of_equity,
            cost_of_debt_pretax=pretax_cod,
            cost_of_debt_aftertax=aftertax_cod,
            marginal_tax_rate=self.inputs.marginal_tax_rate,
            debt_weight=debt_weight,
            equity_weight=equity_weight,
            wacc=wacc,
            breakdown=breakdown
        )

        return results

    def _get_cost_of_equity_breakdown(self, cost_of_equity: float, levered_beta: float) -> Dict[str, Any]:
        """Get detailed breakdown of cost of equity calculation"""
        breakdown = {
            "risk_free_rate": self.inputs.risk_free_rate,
            "risk_free_rate_source": self.inputs.risk_free_rate_source,
            "equity_risk_premium": self.inputs.equity_risk_premium,
            "erp_source": self.inputs.erp_source,
        }

        if self.method != CAPMMethod.BUILD_UP:
            breakdown.update({
                "levered_beta": levered_beta,
                "beta_source": self.inputs.beta_source,
                "market_risk_premium_component": levered_beta * self.inputs.equity_risk_premium
            })

        if self.inputs.country_risk_premium > 0:
            breakdown["country_risk_premium"] = self.inputs.country_risk_premium
            breakdown["country"] = self.inputs.country

        if self.inputs.size_premium > 0:
            breakdown["size_premium"] = self.inputs.size_premium
            breakdown["size_premium_source"] = self.inputs.size_premium_source

        if self.inputs.company_specific_premium > 0:
            breakdown["company_specific_premium"] = self.inputs.company_specific_premium
            breakdown["company_specific_rationale"] = self.inputs.company_specific_rationale

        breakdown["total_cost_of_equity"] = cost_of_equity

        return breakdown

    def sensitivity_analysis(
        self,
        wacc_range: float = 0.02,
        steps: int = 5
    ) -> Dict[str, Any]:
        """
        Perform sensitivity analysis on WACC

        Args:
            wacc_range: Range for sensitivity (+/- percentage points as decimal)
            steps: Number of steps in each direction

        Returns:
            Dict with sensitivity results
        """
        base_wacc = self.calculate_wacc().wacc

        # Create sensitivity ranges
        wacc_low = max(0.01, base_wacc - wacc_range)  # Floor at 1%
        wacc_high = base_wacc + wacc_range

        wacc_values = np.linspace(wacc_low, wacc_high, steps * 2 + 1)

        return {
            "base_wacc": base_wacc,
            "wacc_low": wacc_low,
            "wacc_high": wacc_high,
            "sensitivity_range": list(wacc_values),
            "range_percentage_points": wacc_range
        }


# Example usage and testing
if __name__ == "__main__":
    # Example: Malaysian company valuation
    inputs = WACCInputs(
        risk_free_rate=0.04196,  # Malaysia 10Y bond
        risk_free_rate_source="Malaysia 10Y Government Bond",
        equity_risk_premium=0.055,  # From Damodaran
        erp_source="Damodaran 2024",
        country_risk_premium=0.01,  # Malaysia country risk premium
        country="Malaysia",
        unlevered_beta=1.0,
        beta_source="Industry average",
        size_premium=0.02,  # 2% for mid-cap company
        company_specific_premium=0.01,  # 1% for company-specific risks
        target_debt_to_equity=0.3,  # 30% D/E
        cost_of_debt_pretax=0.06,  # 6% pretax
        marginal_tax_rate=0.24  # Malaysia corporate tax
    )

    calculator = WACCCalculator(inputs, method=CAPMMethod.MODIFIED)
    results = calculator.calculate_wacc()

    print(f"Cost of Equity: {results.cost_of_equity:.2%}")
    print(f"Cost of Debt (after-tax): {results.cost_of_debt_aftertax:.2%}")
    print(f"WACC: {results.wacc:.2%}")
    print(f"\nDetailed Breakdown:")
    print(results.breakdown)
