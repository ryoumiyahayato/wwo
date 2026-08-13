"""WWO world-name inventory and alias staging helpers."""

from importlib import import_module

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
    if name == "world_names":
        return import_module(".world_names", __name__)

    if name in __all__:
        world_names = import_module(".world_names", __name__)
        return getattr(world_names, name)
    raise AttributeError(name)
