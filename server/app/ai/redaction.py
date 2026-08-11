from __future__ import annotations

import json

from server.app.ai.models import AiInputSummary


def build_prompt(summary: AiInputSummary) -> str:
    """Build the only text ever sent to an AI provider.

    Only the declared whitelist fields of ``AiInputSummary`` are serialized.
    Raw activity data, window titles, browser URLs, and secrets never enter
    the prompt because the input model forbids extra fields and this function
    selects an explicit allowlist.
    """
    prompt_payload = {
        "permissionLevel": summary.permission_level,
        "taskIds": [str(task_id) for task_id in summary.task_ids],
        "taskTitles": summary.task_titles,
        "scheduleMetrics": summary.schedule_metrics,
        "focusCompletionMetrics": summary.focus_completion_metrics,
        "sleepAggregates": summary.sleep_aggregates,
    }
    return json.dumps(prompt_payload, ensure_ascii=True, sort_keys=True)
