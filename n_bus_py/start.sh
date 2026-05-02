#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo "  N-Bus Power Flow - Start All Services"
echo "============================================"
echo ""

cleanup() {
  echo ""
  echo "Stopping services..."
  kill $BACKEND_PID 2>/dev/null
  kill $FRONTEND_PID 2>/dev/null
  echo "Services stopped."
}

trap cleanup EXIT INT TERM

echo "[1/2] Starting Backend (port 8000)..."
cd "$ROOT/backend"
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload &
BACKEND_PID=$!

echo "[2/2] Starting Frontend (port 3000)..."
cd "$ROOT/frontend"
npm run dev &
FRONTEND_PID=$!

echo ""
echo "Done. Open http://localhost:3000 in your browser."
echo "Press Ctrl+C to stop both services."
echo ""

wait
