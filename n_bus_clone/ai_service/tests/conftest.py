"""Pytest configuration for AI service tests."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("LLM_API_KEY", "test-key")
os.environ.setdefault("API_AUTH_TOKEN", "")
