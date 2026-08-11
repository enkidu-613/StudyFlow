from fastapi import FastAPI

from server.app.health.routes import router as health_router

app = FastAPI(title="StudyFlow API")
app.include_router(health_router)
