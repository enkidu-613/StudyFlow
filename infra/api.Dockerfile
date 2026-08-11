FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /srv/studyflow

COPY server/pyproject.toml ./server/pyproject.toml
COPY server/poetry.lock ./server/poetry.lock
COPY server/ ./server/

RUN pip install --no-cache-dir poetry==1.8.5 \
    && cd server \
    && poetry config virtualenvs.create false \
    && poetry install --only main --no-interaction --no-ansi

EXPOSE 8000

CMD ["sh", "-c", "cd server && poetry run alembic upgrade head && poetry run uvicorn server.app.main:app --host 0.0.0.0 --port 8000"]
