"""
IVS Valuation Engine - Main Application
FastAPI application entry point with routers and middleware
"""

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZIPMiddleware
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
import logging
from datetime import datetime

# Import routers (to be created)
# from app.api.v1 import engagements, scope_of_work, data_intake, valuations, reports

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Create FastAPI application
app = FastAPI(
    title="IVS Valuation Engine",
    description="IVS 2022/2025 Compliant Automated Business Valuation Platform",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json"
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:3001"],  # Frontend origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# GZIP compression for responses
app.add_middleware(GZIPMiddleware, minimum_size=1000)


# Exception handlers
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Handle validation errors with detailed error messages"""
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "detail": exc.errors(),
            "body": exc.body if hasattr(exc, 'body') else None,
            "timestamp": datetime.utcnow().isoformat()
        }
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """Handle general exceptions"""
    logger.error(f"Unhandled exception: {str(exc)}", exc_info=True)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "detail": "An internal server error occurred",
            "timestamp": datetime.utcnow().isoformat()
        }
    )


# Middleware for request logging and audit trail
@app.middleware("http")
async def log_requests(request: Request, call_next):
    """Log all requests for audit trail"""
    start_time = datetime.utcnow()

    # Process request
    response = await call_next(request)

    # Calculate processing time
    process_time = (datetime.utcnow() - start_time).total_seconds()

    # Log request
    logger.info(
        f"{request.method} {request.url.path} - "
        f"Status: {response.status_code} - "
        f"Time: {process_time:.3f}s"
    )

    # Add custom headers
    response.headers["X-Process-Time"] = str(process_time)
    response.headers["X-API-Version"] = "1.0.0"

    return response


# Health check endpoint
@app.get("/health", tags=["System"])
async def health_check():
    """Health check endpoint for monitoring"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "IVS Valuation Engine",
        "version": "1.0.0"
    }


# Root endpoint
@app.get("/", tags=["System"])
async def root():
    """Root endpoint with API information"""
    return {
        "service": "IVS Valuation Engine API",
        "version": "1.0.0",
        "ivs_compliance": "IVS 2022/2025",
        "standards_supported": ["IVS 100", "IVS 101", "IVS 102", "IVS 104", "IVS 105", "IVS 200"],
        "documentation": "/api/docs",
        "timestamp": datetime.utcnow().isoformat()
    }


# Include routers (to be created)
# app.include_router(engagements.router, prefix="/api/v1/engagements", tags=["Engagements"])
# app.include_router(scope_of_work.router, prefix="/api/v1/scope-of-work", tags=["Scope of Work"])
# app.include_router(data_intake.router, prefix="/api/v1/data-intake", tags=["Data Intake"])
# app.include_router(valuations.router, prefix="/api/v1/valuations", tags=["Valuations"])
# app.include_router(reports.router, prefix="/api/v1/reports", tags=["Reports"])


# Startup event
@app.on_event("startup")
async def startup_event():
    """Actions to perform on application startup"""
    logger.info("="* 50)
    logger.info("IVS Valuation Engine Starting Up")
    logger.info("="* 50)
    logger.info("Service: IVS-Compliant Automated Business Valuation Platform")
    logger.info("Standards: IVS 2022/2025")
    logger.info("="* 50)


# Shutdown event
@app.on_event("shutdown")
async def shutdown_event():
    """Actions to perform on application shutdown"""
    logger.info("IVS Valuation Engine Shutting Down")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,  # Enable for development
        log_level="info"
    )
