"""WWO world-name inventory and alias staging helpers."""

__all__ = [
    "NORMALIZER_ID",
    "build_artifacts",
    "build_alias_records",
    "build_collision_report",
    "build_search_index",
    "normalize_name",
    "validate_artifacts",
]


def __getattr__(name: str):
    from . import world_names

    if name in __all__:
        return getattr(world_names, name)
    raise AttributeError(name)