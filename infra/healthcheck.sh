#!/usr/bin/env bash
# Health check for the StudyFlow API container. Exits non-zero when the API
# is not reachable so the container runtime can restart it.
set -euo pipefail

url="${1:-http://127.0.0.1:8000/health/live}"

python - "$url" <<'PY'
import sys
import urllib.request

url = sys.argv[1]
try:
    with urllib.request.urlopen(url, timeout=3) as response:
        if response.status != 200:
            sys.exit(1)
        body = response.read().decode("utf-8")
except Exception:
    sys.exit(1)
if '"status":"ok"' not in body.replace(" ", ""):
    sys.exit(1)
PY
