from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID

from server.app.backups.repository import (
    BackupLimitReachedError,
    BackupNotFoundError,
    BackupRecord,
    BackupRepository,
    BackupSizeLimitError,
)
from server.app.db.context import UserContext


@dataclass(frozen=True, slots=True)
class BackupSettings:
    max_backups_per_user: int = 5
    max_backup_bytes: int = 64 * 1024 * 1024
    create_rate_limit_per_hour: int = 10

    @classmethod
    def from_env(cls) -> BackupSettings:
        def _int_env(name: str, default: int) -> int:
            raw = os.getenv(name)
            if not raw:
                return default
            try:
                return max(1, int(raw))
            except ValueError:
                return default

        return cls(
            max_backups_per_user=_int_env(
                "STUDYFLOW_MAX_BACKUPS_PER_USER",
                5,
            ),
            max_backup_bytes=_int_env(
                "STUDYFLOW_MAX_BACKUP_BYTES",
                64 * 1024 * 1024,
            ),
            create_rate_limit_per_hour=_int_env(
                "STUDYFLOW_BACKUP_CREATE_LIMIT_PER_HOUR",
                10,
            ),
        )


class BackupServiceError(RuntimeError):
    def __init__(self, status_code: int, detail: str) -> None:
        self.status_code = status_code
        self.detail = detail
        super().__init__(detail)


class BackupService:
    def __init__(self, repository: BackupRepository, settings: BackupSettings) -> None:
        self._repository = repository
        self._settings = settings
        self._create_timestamps: dict[UUID, list[datetime]] = {}

    async def create(
        self,
        context: UserContext,
        *,
        name: str | None,
    ) -> BackupRecord:
        self._enforce_create_rate_limit(context.user_id)
        count = await self._repository.count_for_user(context.user_id)
        if count >= self._settings.max_backups_per_user:
            raise BackupServiceError(
                409,
                f"每个账户最多可保留 {self._settings.max_backups_per_user} 个备份。"
                "请先删除一个旧备份后再创建。",
            )
        final_name = name or _default_name()
        try:
            return await self._repository.create_snapshot(
                context,
                name=final_name,
                max_backup_bytes=self._settings.max_backup_bytes,
            )
        except BackupLimitReachedError as exc:
            raise BackupServiceError(
                409,
                f"每个账户最多可保留 {exc.max_backups} 个备份。"
                "请先删除一个旧备份后再创建。",
            ) from exc
        except BackupSizeLimitError as exc:
            raise BackupServiceError(422, str(exc)) from exc

    async def list(self, context: UserContext) -> list[BackupRecord]:
        return await self._repository.list_for_user(context.user_id)

    async def rename(
        self,
        context: UserContext,
        backup_id: UUID,
        name: str,
    ) -> BackupRecord:
        try:
            return await self._repository.rename(
                context.user_id,
                backup_id,
                name,
            )
        except BackupNotFoundError as exc:
            raise BackupServiceError(404, "备份不存在。") from exc

    async def delete(self, context: UserContext, backup_id: UUID) -> None:
        try:
            await self._repository.delete(context.user_id, backup_id)
        except BackupNotFoundError as exc:
            raise BackupServiceError(404, "备份不存在。") from exc

    def _enforce_create_rate_limit(self, user_id: UUID) -> None:
        now = datetime.now(UTC)
        window_start = now.replace(minute=0, second=0, microsecond=0)
        timestamps = self._create_timestamps.get(user_id, [])
        recent = [ts for ts in timestamps if ts >= window_start]
        if len(recent) >= self._settings.create_rate_limit_per_hour:
            raise BackupServiceError(
                429,
                "备份创建过于频繁，请稍后再试。",
            )
        recent.append(now)
        self._create_timestamps[user_id] = recent


def _default_name() -> str:
    now = datetime.now(UTC)
    return f"备份 {now.strftime('%Y-%m-%d %H:%M')}"
