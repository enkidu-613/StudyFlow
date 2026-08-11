from typing import Protocol

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from server.app.db.engine import DatabaseReadinessResult

router = APIRouter(prefix="/health", tags=["health"])


class DatabaseReadiness(Protocol):
    async def check(self) -> DatabaseReadinessResult: ...


def get_database_readiness(request: Request) -> DatabaseReadiness:
    return request.app.state.database_readiness


@router.get("/live")
def liveness() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/ready")
async def readiness(
    database_readiness: DatabaseReadiness = Depends(get_database_readiness),
) -> JSONResponse:
    result = await database_readiness.check()
    if result.is_ready:
        return JSONResponse(
            status_code=200,
            content={"status": "ok", "database": result.database},
        )

    content = {"status": "not_ready", "database": result.database}
    if result.message:
        content["message"] = result.message

    return JSONResponse(status_code=503, content=content)
