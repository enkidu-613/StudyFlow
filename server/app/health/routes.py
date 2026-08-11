from fastapi import APIRouter
from fastapi.responses import JSONResponse

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/live")
def liveness() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/ready")
def readiness() -> JSONResponse:
    return JSONResponse(
        status_code=503,
        content={"status": "not_ready", "database": "not_configured"},
    )
