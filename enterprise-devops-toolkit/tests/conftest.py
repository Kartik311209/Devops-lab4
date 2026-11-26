"""
tests/conftest.py
=================
Shared pytest configuration for the EDDT test suite.

This file is automatically loaded by pytest before any test module.
It sets the Python path so all test modules can import from app/app.py
without each file needing its own sys.path manipulation.
"""

import sys
import os

# Add the app directory to the Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))
