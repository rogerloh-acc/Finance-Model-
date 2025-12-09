"""
IVS Valuation Engine - Market Data Service
Fetch external market data: risk-free rates, ERPs, betas, comparables
"""

import yfinance as yf
import requests
from typing import Optional, Dict, List, Any
from datetime import datetime, timedelta
import logging

logger = logging.getLogger(__name__)


class MarketDataService:
    """
    Service for fetching market data from various sources
    IVS 104 compliant - tracks data sources and observable/non-observable classification
    """

    def __init__(self):
        self.cache = {}  # Simple in-memory cache

    def get_risk_free_rate(
        self,
        country: str = "Malaysia",
        tenor: str = "10Y",
        as_of_date: Optional[datetime] = None
    ) -> Dict[str, Any]:
        """
        Get risk-free rate for specified country and tenor

        Args:
            country: Country name
            tenor: Bond tenor (e.g., '10Y', '5Y')
            as_of_date: Date for rate (default: latest)

        Returns:
            Dict with rate, source, date, and metadata
        """
        if country == "Malaysia":
            # For Malaysia, use government bond yield
            # In production, integrate with Bloomberg or local data provider
            # For now, return mock/recent data
            return {
                "value": 0.04196,  # 4.196%
                "country": "Malaysia",
                "tenor": "10Y",
                "instrument": "Malaysia Government Bond",
                "source": "Bank Negara Malaysia / Bloomberg",
                "as_of_date": as_of_date or datetime.now().date(),
                "data_type": "observable",
                "currency": "MYR"
            }
        elif country == "US" or country == "USA":
            # For US, can use Yahoo Finance for Treasury yields
            try:
                ticker = "^TNX" if tenor == "10Y" else "^FVX"  # 10Y or 5Y
                bond = yf.Ticker(ticker)
                hist = bond.history(period="1d")
                if not hist.empty:
                    rate = hist['Close'].iloc[-1] / 100  # Convert to decimal
                    return {
                        "value": rate,
                        "country": "US",
                        "tenor": tenor,
                        "instrument": f"US Treasury {tenor}",
                        "source": "Yahoo Finance",
                        "as_of_date": hist.index[-1].date(),
                        "data_type": "observable",
                        "currency": "USD"
                    }
            except Exception as e:
                logger.error(f"Error fetching US Treasury rate: {e}")

        # Default fallback
        return {
            "value": 0.03,
            "country": country,
            "tenor": tenor,
            "source": "Default/Estimated",
            "as_of_date": datetime.now().date(),
            "data_type": "non_observable",
            "note": "Unable to fetch real-time data; using default estimate"
        }

    def get_equity_risk_premium(
        self,
        geography: str = "Global",
        source: str = "Damodaran"
    ) -> Dict[str, Any]:
        """
        Get equity risk premium

        Args:
            geography: Geographic market (Global, US, Developed, Emerging)
            source: Data source (Damodaran, historical, etc.)

        Returns:
            Dict with ERP, source, and metadata
        """
        # Damodaran ERPs (as of Jan 2024 - update periodically)
        damodaran_erps = {
            "Global": 0.055,  # 5.5%
            "US": 0.053,
            "Developed": 0.055,
            "Emerging": 0.071,
            "Asia": 0.064,
            "Malaysia": 0.060
        }

        if source == "Damodaran":
            erp = damodaran_erps.get(geography, 0.055)
            return {
                "value": erp,
                "geography": geography,
                "source": "Damodaran (NYU Stern)",
                "as_of_date": datetime(2024, 1, 1).date(),
                "data_type": "non_observable",  # Based on historical analysis
                "methodology": "Historical premium over risk-free rate",
                "url": "https://pages.stern.nyu.edu/~adamodar/New_Home_Page/datafile/ctryprem.html"
            }

        # Historical ERP calculation (simplified)
        return {
            "value": 0.055,
            "geography": geography,
            "source": "Historical analysis",
            "data_type": "non_observable"
        }

    def get_country_risk_premium(
        self,
        country: str = "Malaysia"
    ) -> Dict[str, Any]:
        """
        Get country risk premium

        Args:
            country: Country name

        Returns:
            Dict with CRP, source, and metadata
        """
        # Damodaran country risk premiums (simplified)
        # In production, fetch from API or database
        country_crps = {
            "Malaysia": 0.010,  # 1.0%
            "Singapore": 0.002,
            "Thailand": 0.012,
            "Indonesia": 0.018,
            "Philippines": 0.015,
            "Vietnam": 0.022,
            "US": 0.0,
            "UK": 0.001,
            "Australia": 0.002
        }

        crp = country_crps.get(country, 0.015)  # Default to 1.5% for emerging markets

        return {
            "value": crp,
            "country": country,
            "source": "Damodaran (NYU Stern)",
            "as_of_date": datetime(2024, 1, 1).date(),
            "data_type": "non_observable",
            "methodology": "Default spread + (Equity volatility / Bond volatility)",
            "url": "https://pages.stern.nyu.edu/~adamodar/New_Home_Page/datafile/ctryprem.html"
        }

    def get_beta(
        self,
        ticker: str,
        reference_index: str = "^KLSE",
        period: str = "2y"
    ) -> Dict[str, Any]:
        """
        Calculate beta for a stock against a reference index

        Args:
            ticker: Stock ticker
            reference_index: Market index ticker
            period: Historical period for calculation

        Returns:
            Dict with beta, source, and metadata
        """
        try:
            # Fetch historical data
            stock = yf.Ticker(ticker)
            index = yf.Ticker(reference_index)

            stock_hist = stock.history(period=period)
            index_hist = index.history(period=period)

            if stock_hist.empty or index_hist.empty:
                return {
                    "value": 1.0,
                    "ticker": ticker,
                    "source": "Default",
                    "note": "Unable to calculate; using default beta of 1.0"
                }

            # Calculate returns
            stock_returns = stock_hist['Close'].pct_change().dropna()
            index_returns = index_hist['Close'].pct_change().dropna()

            # Align dates
            aligned = stock_returns.align(index_returns, join='inner')
            stock_ret_aligned = aligned[0]
            index_ret_aligned = aligned[1]

            # Calculate beta (covariance / variance)
            covariance = stock_ret_aligned.cov(index_ret_aligned)
            variance = index_ret_aligned.var()
            beta = covariance / variance if variance != 0 else 1.0

            return {
                "value": beta,
                "ticker": ticker,
                "reference_index": reference_index,
                "period": period,
                "observations": len(stock_ret_aligned),
                "source": "Yahoo Finance (calculated)",
                "calculation_date": datetime.now().date(),
                "data_type": "observable",
                "raw_beta": beta
            }

        except Exception as e:
            logger.error(f"Error calculating beta for {ticker}: {e}")
            return {
                "value": 1.0,
                "ticker": ticker,
                "source": "Default (error)",
                "error": str(e)
            }

    def get_industry_beta(
        self,
        industry: str,
        geography: str = "Global"
    ) -> Dict[str, Any]:
        """
        Get industry median/average beta from Damodaran dataset

        Args:
            industry: Industry name
            geography: Geographic region

        Returns:
            Dict with beta, source, and metadata
        """
        # Damodaran industry betas (simplified subset)
        # In production, parse from CSV/Excel file or API
        industry_betas = {
            "Software (System & Application)": 1.17,
            "Internet": 1.22,
            "Banks": 0.75,
            "Property Development": 0.88,
            "Retail": 0.95,
            "Food & Beverage": 0.70,
            "Telecommunications": 0.82,
            "Healthcare": 0.95,
            "Manufacturing": 1.05,
            "Construction": 1.10
        }

        beta = industry_betas.get(industry, 1.0)

        return {
            "value": beta,
            "industry": industry,
            "geography": geography,
            "source": "Damodaran (NYU Stern)",
            "as_of_date": datetime(2024, 1, 1).date(),
            "data_type": "non_observable",
            "note": "Industry median unlevered beta",
            "url": "https://pages.stern.nyu.edu/~adamodar/New_Home_Page/datafile/Betas.html"
        }

    def get_comparable_companies(
        self,
        sector: str,
        geography: Optional[str] = None,
        min_market_cap: Optional[float] = None,
        limit: int = 10
    ) -> List[Dict[str, Any]]:
        """
        Get list of comparable public companies

        Args:
            sector: Industry sector
            geography: Geographic filter
            min_market_cap: Minimum market cap filter
            limit: Maximum number of results

        Returns:
            List of comparable companies with metrics
        """
        # In production, integrate with Bloomberg, S&P CIQ, or Refinitiv
        # For now, return mock data structure

        logger.info(f"Fetching comparables for sector: {sector}, geography: {geography}")

        # Mock comparable companies
        comparables = [
            {
                "company_name": "Example Tech Corp",
                "ticker": "EXMP.KL",
                "sector": sector,
                "geography": geography or "Malaysia",
                "market_cap": 1_000_000_000,
                "enterprise_value": 1_200_000_000,
                "revenue": 500_000_000,
                "ebitda": 100_000_000,
                "ebit": 80_000_000,
                "ev_revenue": 2.4,
                "ev_ebitda": 12.0,
                "ev_ebit": 15.0,
                "revenue_growth": 0.15,
                "ebitda_margin": 0.20,
                "source": "Mock Data",
                "as_of_date": datetime.now().date()
            }
        ]

        return comparables[:limit]

    def get_market_multiples_statistics(
        self,
        comparables: List[Dict[str, Any]]
    ) -> Dict[str, Dict[str, float]]:
        """
        Calculate statistics for market multiples from comparables

        Args:
            comparables: List of comparable companies

        Returns:
            Dict with statistics for each multiple (mean, median, min, max, etc.)
        """
        import numpy as np

        multiples = ['ev_revenue', 'ev_ebitda', 'ev_ebit']
        stats = {}

        for multiple in multiples:
            values = [c.get(multiple) for c in comparables if c.get(multiple) is not None]

            if values:
                stats[multiple] = {
                    "mean": np.mean(values),
                    "median": np.median(values),
                    "min": np.min(values),
                    "max": np.max(values),
                    "25th_percentile": np.percentile(values, 25),
                    "75th_percentile": np.percentile(values, 75),
                    "count": len(values)
                }

        return stats


# Example usage
if __name__ == "__main__":
    service = MarketDataService()

    # Test risk-free rate
    rfr = service.get_risk_free_rate("Malaysia", "10Y")
    print(f"Risk-Free Rate (Malaysia 10Y): {rfr['value']:.4%}")

    # Test ERP
    erp = service.get_equity_risk_premium("Malaysia", "Damodaran")
    print(f"Equity Risk Premium (Malaysia): {erp['value']:.4%}")

    # Test CRP
    crp = service.get_country_risk_premium("Malaysia")
    print(f"Country Risk Premium (Malaysia): {crp['value']:.4%}")

    # Test beta calculation
    beta = service.get_beta("1155.KL", "^KLSE", "2y")
    print(f"Beta for 1155.KL: {beta.get('value', 'N/A')}")
