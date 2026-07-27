#!/usr/bin/env python3
"""Run the deterministic flag builder with conservative Commons throttling."""

from __future__ import annotations

import time

import build_1900_flag_registry_fast as builder

_original_fetch_bytes = builder.fetch_bytes
_last_request_time = 0.0


def throttled_fetch_bytes(url: str, retries: int = 10) -> bytes:
    global _last_request_time
    elapsed = time.monotonic() - _last_request_time
    if elapsed < 2.0:
        time.sleep(2.0 - elapsed)
    try:
        return _original_fetch_bytes(url, retries=max(retries, 10))
    finally:
        _last_request_time = time.monotonic()


builder.fetch_bytes = throttled_fetch_bytes


if __name__ == "__main__":
    raise SystemExit(builder.main())
