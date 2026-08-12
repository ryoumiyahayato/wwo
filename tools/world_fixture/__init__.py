"""Small, deterministic world-data golden fixture helpers."""

from .corpus import (
    canonical_hash,
    canonical_json,
    load_corpus,
    materialize_fixture,
    validate_fixture,
)

__all__ = [
    "canonical_hash",
    "canonical_json",
    "load_corpus",
    "materialize_fixture",
    "validate_fixture",
]
