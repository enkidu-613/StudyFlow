from fastapi import FastAPI

from server.app.db.engine import (
    DatabaseConfigurationError,
    DatabaseReadinessProbe,
    MissingDatabaseReadinessProbe,
    create_engine_from_env,
)
from server.app.health.routes import router as health_router


def create_app() -> FastAPI:
    app = FastAPI(title="StudyFlow API")

    try:
        database_engine = create_engine_from_env()
    except DatabaseConfigurationError as exc:
        app.state.database_engine = None
        app.state.database_readiness = MissingDatabaseReadinessProbe(str(exc))
    else:
        app.state.database_engine = database_engine
        app.state.database_readiness = DatabaseReadinessProbe(database_engine)

        @app.on_event("shutdown")
        async def dispose_database_engine() -> None:
            await database_engine.dispose()

    app.include_router(health_router)
    return app


app = create_app()
