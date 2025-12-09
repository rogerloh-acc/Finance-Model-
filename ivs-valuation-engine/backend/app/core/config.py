"""
IVS Valuation Engine - Configuration
Centralized configuration management using Pydantic Settings
"""

from pydantic_settings import BaseSettings
from typing import Optional
import os


class Settings(BaseSettings):
    """Application settings and configuration"""

    # Application
    APP_NAME: str = "IVS Valuation Engine"
    APP_VERSION: str = "1.0.0"
    API_V1_PREFIX: str = "/api/v1"
    DEBUG: bool = False

    # Database
    DATABASE_URL: str = "postgresql+asyncpg://user:password@localhost:5432/ivs_valuation_db"
    DATABASE_ECHO: bool = False  # Set to True for SQL query logging

    # Security
    SECRET_KEY: str = "your-secret-key-here-change-in-production"  # Change in production!
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # CORS
    CORS_ORIGINS: list = ["http://localhost:3000", "http://localhost:3001"]

    # File Upload
    UPLOAD_DIR: str = "./uploads"
    MAX_UPLOAD_SIZE: int = 50 * 1024 * 1024  # 50 MB
    ALLOWED_EXTENSIONS: set = {
        "pdf", "xlsx", "xls", "csv", "docx", "doc", "png", "jpg", "jpeg"
    }

    # Market Data APIs
    YAHOO_FINANCE_ENABLED: bool = True
    BLOOMBERG_API_KEY: Optional[str] = None
    BLOOMBERG_ENABLED: bool = False
    REFINITIV_API_KEY: Optional[str] = None
    REFINITIV_ENABLED: bool = False

    # Damodaran Data (public, no API key needed)
    DAMODARAN_BASE_URL: str = "https://pages.stern.nyu.edu/~adamodar/New_Home_Page/data.html"
    DAMODARAN_ENABLED: bool = True

    # Redis (for caching)
    REDIS_URL: str = "redis://localhost:6379/0"
    REDIS_ENABLED: bool = False

    # Celery (for background tasks)
    CELERY_BROKER_URL: str = "redis://localhost:6379/1"
    CELERY_RESULT_BACKEND: str = "redis://localhost:6379/2"
    CELERY_ENABLED: bool = False

    # Logging
    LOG_LEVEL: str = "INFO"
    LOG_FILE: Optional[str] = None

    # IVS Compliance
    IVS_VERSION: str = "2022/2025"
    IVS_STANDARDS_SUPPORTED: list = ["IVS 100", "IVS 101", "IVS 102", "IVS 104", "IVS 105", "IVS 200"]

    # Valuation Defaults
    DEFAULT_CURRENCY: str = "MYR"
    DEFAULT_RISK_FREE_RATE_SOURCE: str = "Malaysia 10Y Government Bond"
    DEFAULT_EXPLICIT_FORECAST_YEARS: int = 5
    DEFAULT_TERMINAL_GROWTH_RATE: float = 0.02  # 2%

    # Report Generation
    REPORT_TEMPLATE_DIR: str = "./templates/reports"
    REPORT_OUTPUT_DIR: str = "./outputs/reports"
    REPORT_LANGUAGE: str = "British English"

    class Config:
        env_file = ".env"
        case_sensitive = True


# Create global settings instance
settings = Settings()


# Helper functions
def get_database_url() -> str:
    """Get database URL with fallback"""
    return settings.DATABASE_URL


def is_development() -> bool:
    """Check if running in development mode"""
    return settings.DEBUG


def is_production() -> bool:
    """Check if running in production mode"""
    return not settings.DEBUG
