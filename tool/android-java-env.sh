#!/usr/bin/env bash

# Select a JDK that is compatible with Android Gradle's JdkImageTransform.
#
# Priority:
#   1. Explicit STUDYFLOW_JAVA_HOME supplied by the user/CI.
#   2. A standard JDK installed and selected by mise.
#   3. Standard Homebrew OpenJDK on macOS.
#
# GraalVM and JDK 26 are intentionally skipped: they are the cause of the
# core-for-system-modules.jar -> jlink failure in this project.

studyflow_is_android_jdk() {
  local candidate="$1"
  [[ -x "$candidate/bin/java" && -x "$candidate/bin/jlink" ]] || return 1

  local version_output
  version_output="$("$candidate/bin/java" -version 2>&1 || true)"
  [[ "$version_output" != *GraalVM* ]] || return 1
  [[ "$version_output" != *'version "26.'* ]] || return 1
}

if [[ -n "${STUDYFLOW_JAVA_HOME:-}" ]]; then
  export JAVA_HOME="$STUDYFLOW_JAVA_HOME"
elif [[ -n "${JAVA_HOME:-}" ]] && studyflow_is_android_jdk "$JAVA_HOME"; then
  : # Keep an already selected standard JDK.
else
  # The shell may have inherited GraalVM or Java 26 from a global mise
  # configuration. Do not let that stale value block the resolver below.
  unset JAVA_HOME
  if command -v mise >/dev/null 2>&1; then
    mise_java_home="$(mise where java 2>/dev/null || true)"
    if [[ -n "$mise_java_home" ]] && studyflow_is_android_jdk "$mise_java_home"; then
      export JAVA_HOME="$mise_java_home"
    fi
  fi
fi

if [[ -z "${JAVA_HOME:-}" ]] && [[ "$(uname -s)" == "Darwin" ]]; then
  for java_candidate in \
    "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home" \
    "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" \
    "/usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home" \
    "/usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"; do
    if studyflow_is_android_jdk "$java_candidate"; then
      export JAVA_HOME="$java_candidate"
      break
    fi
  done
fi

if [[ -n "${JAVA_HOME:-}" ]]; then
  export PATH="$JAVA_HOME/bin:$PATH"
fi
