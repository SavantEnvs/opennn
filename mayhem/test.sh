#!/usr/bin/env bash
#
# mayhem/test.sh — RUN upstream's JSON and string-utility GoogleTest suites (built by mayhem/build.sh).
# The assertions live in tests/core/json_test.cpp and string_utilities_test.cpp. The runner is a
# dynamically linked binary, so a neutered program prints no gtest summary and this script fails.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

RUNNER="$SRC/build-tests/opennn_core_tests"
[ -x "$RUNNER" ] || { echo "missing test runner $RUNNER (mayhem/build.sh builds it)" >&2; emit_ctrf gtest 0 1; exit 1; }

OUT="$("$RUNNER" 2>&1)"; rc=$?
printf '%s\n' "$OUT"

total="$(printf '%s\n' "$OUT" | sed -n 's/^\[==========\] \([0-9][0-9]*\) tests\? from .* ran\..*/\1/p' | tail -1)"
passed="$(printf '%s\n' "$OUT" | sed -n 's/^\[  PASSED  \] \([0-9][0-9]*\) tests\?\./\1/p' | tail -1)"
skipped="$(printf '%s\n' "$OUT" | sed -n 's/^\[  SKIPPED \] \([0-9][0-9]*\) tests\?, listed below:/\1/p' | tail -1)"
failed="$(printf '%s\n' "$OUT" | sed -n 's/^\[  FAILED  \] \([0-9][0-9]*\) tests\?, listed below:/\1/p' | tail -1)"
: "${total:=0}" "${passed:=0}" "${skipped:=0}" "${failed:=0}"

# A real run executes at least the 31 tests in the two files; a missing summary means the runner did not run.
if [ "$total" -lt 31 ] || [ "$passed" -lt 1 ]; then
  echo "gtest summary missing or too few tests (total=$total passed=$passed)" >&2
  emit_ctrf gtest "$passed" 1 "$skipped"
  exit 1
fi
[ "$rc" -eq 0 ] || [ "$failed" -gt 0 ] || failed=1
emit_ctrf gtest "$passed" "$failed" "$skipped"
