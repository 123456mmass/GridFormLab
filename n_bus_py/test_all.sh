#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo "  N-Bus Power Flow - Run All Tests"
echo "============================================"
echo ""

echo "[1/2] Running pytest (85 unit tests)..."
echo ""
cd "$ROOT"
python -m pytest tests/ -v
PYTEST_RESULT=$?

echo ""
echo "[2/2] Running Playwright E2E (54 tests)..."
echo ""
cd "$ROOT/frontend"
PW_OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/nbus-pw-output.XXXXXX")"
export PLAYWRIGHT_BACKEND_PORT=8001
export PLAYWRIGHT_FRONTEND_PORT=3000
export PLAYWRIGHT_REUSE_BACKEND=1
export PLAYWRIGHT_REUSE_FRONTEND=1
export NEXT_PUBLIC_API_URL="http://127.0.0.1:${PLAYWRIGHT_BACKEND_PORT}"
npx playwright test --reporter=list --output="$PW_OUTPUT"
PLAYWRIGHT_RESULT=$?

echo ""
echo "============================================"
if [ $PYTEST_RESULT -eq 0 ]; then echo "  pytest:     PASSED"; else echo "  pytest:     FAILED"; fi
if [ $PLAYWRIGHT_RESULT -eq 0 ]; then echo "  Playwright: PASSED"; else echo "  Playwright: FAILED"; fi
echo "============================================"
