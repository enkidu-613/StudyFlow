from fastapi import FastAPI

from server.app.auth.routes import router as auth_router
from server.app.auth.service import AuthService, AuthSettings
from server.app.db.engine import (
    DatabaseConfigurationError,
    DatabaseReadinessProbe,
    MissingDatabaseReadinessProbe,
    create_engine_from_env,
    create_session_factory,
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
        try:
            auth_settings = AuthSettings.from_env()
        except ValueError:
            app.state.auth_service = None
        else:
            app.state.auth_service = AuthService(
                create_session_factory(database_engine),
                auth_settings,
            )

        @app.on_event("shutdown")
        async def dispose_database_engine() -> None:
            await database_engine.dispose()

    app.include_router(health_router)
    app.include_router(auth_router)
    return app


app = create_app()
