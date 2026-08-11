#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_sdk="$repo_root/tool/test-fixtures/flutter-sdk"

output="$(
  cd "$repo_root"
  STUDYFLOW_FLUTTER_ROOT="$test_sdk" \
    bash "$repo_root/tool/flutter" --version
)"

[[ "$output" == "fake flutter --version" ]]
printf '%s\n' 'flutter wrapper test passed'
