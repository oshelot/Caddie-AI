#!/bin/bash
# Bootstrap script for Lambda Web Adapter
# Starts the FastAPI app on port 8000, which Lambda Web Adapter proxies to.
exec python3 -m uvicorn app:app --host 0.0.0.0 --port 8000
