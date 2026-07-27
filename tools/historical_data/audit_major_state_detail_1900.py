#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

PROFILE_PATH = Path("data/world_map/historical/major_state_profiles_1900.json")
ADMIN_PATH = Path("data/world_map/historical/historical_admin1_1900.json")

REQUIRED_DETAILED = {
    "german_empire", "austria_hungary", "kingdom_of_spain",
    "kingdom_of_belgium", "kingdom_of_netherlands",
    "grand_duchy_of_luxembourg", "british_isles_1900",
    "russian_empire", "united_states_1900", "dominion_of_canada",
    "cshapes_gw_750", "qing_empire", "empire_of_japan",
    "kingdom_of_italy", "ottoman_empire",
}


def main() -> int:
    profiles = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
    admin = json.loads(ADMIN_PATH.read_text(encoding="utf-8"))
    rows = profiles.get("profiles", [])
    assert len(rows) == 50, f"expected 50 major profiles, got {len(rows)}"
    ranks = [int(row["rank"]) for row in rows]
    assert sorted(ranks) == list(range(1, 51)), "priority ranks must be 1..50"
    assert len({row["entity_id"] for row in rows}) == 50, "profile entity ids must be unique"
    for row in rows:
        brief = str(row.get("brief_zh", ""))
        assert brief.count("。") <= 3, f"brief exceeds three sentences: {row['entity_id']}"
        assert len(brief) >= 20, f"brief too short: {row['entity_id']}"

    countries = admin.get("countries", [])
    by_id = {row["entity_id"]: row for row in countries}
    missing = sorted(REQUIRED_DETAILED - set(by_id))
    assert not missing, f"missing detailed countries: {missing}"
    assert admin.get("policy", {}).get("modern_admin_names_forbidden") is True
    for entity_id, row in by_id.items():
        assert row.get("units"), f"empty administrative unit list: {entity_id}"
        status = str(row.get("geometry_status", ""))
        assert status, f"missing geometry status: {entity_id}"
        assert "modern_fallback" not in status, f"modern fallback forbidden: {entity_id}"
        assert row.get("source_basis"), f"missing source basis: {entity_id}"

    print(json.dumps({
        "profile_count": len(rows),
        "detailed_country_count": len(countries),
        "required_detailed_count": len(REQUIRED_DETAILED),
        "modern_admin_names_forbidden": True,
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
