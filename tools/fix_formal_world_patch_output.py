from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch(path: str, replacements: list[tuple[str, str]]) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    for old, new in replacements:
        if new in text:
            continue
        if old not in text:
            raise RuntimeError(f"missing corrective anchor in {path}: {old!r}")
        text = text.replace(old, new, 1)
    target.write_text(text, encoding="utf-8", newline="\n")


def main() -> None:
    patch(
        "scripts/alpha/alpha_historical_world_economy_data.gd",
        [
            (
                'summary["bounded_simulation_country_count"] = simulation_countries().size()\n'
                'summary["coverage_registry_country_count"] = coverage_by_entity.size()\n',
                '\tsummary["bounded_simulation_country_count"] = simulation_countries().size()\n'
                '\tsummary["coverage_registry_country_count"] = coverage_by_entity.size()\n',
            ),
        ],
    )
    patch(
        "scripts/alpha/alpha_simulation_service.gd",
        [
            (
                'counts["historical_world_countries"] = historical_world_economy.countries.size()\n'
                'counts["historical_formal_countries"] = historical_world_economy.formal_countries().size()\n',
                '\tcounts["historical_world_countries"] = historical_world_economy.countries.size()\n'
                '\tcounts["historical_formal_countries"] = historical_world_economy.formal_countries().size()\n',
            ),
        ],
    )
    patch(
        "scripts/alpha/alpha_ai_service.gd",
        [
            (
                "\t\t\t\tvar secondary := ordered[index]\n",
                "\t\t\t\tvar secondary: Dictionary = ordered[index] as Dictionary\n",
            ),
        ],
    )
    patch(
        "scripts/alpha/alpha_economy_integration_service.gd",
        [
            (
                '\tvar expanded := _enterprise.expand(\n'
                '\t\t"integration:expand:%s:%d" % [enterprise_id, total_hour],\n'
                '\t\tenterprise_id,\n'
                '\t\tinvestment,\n'
                '\t\ttotal_hour\n'
                '\t)\n',
                '\tvar expanded := _enterprise.expand(\n'
                '\t\t"integration:expand:%s:%d" % [enterprise_id, total_hour],\n'
                '\t\tenterprise_id,\n'
                '\t\tinvestment,\n'
                '\t\tmaxi(1, site_ids.size()),\n'
                '\t\tCAPITAL_SUPPLIER_ID,\n'
                '\t\ttotal_hour\n'
                '\t)\n',
            ),
        ],
    )
    patch(
        "scripts/formal/formal_world_application.gd",
        [
            (
                '\t\t_draw_label(rect.position + Vector2(20.0, rect.size.y - 51.0), _formal_status, 8, Color(0.72, 0.78, 0.72, 0.92), rect.size.x - 40.0)\n',
                '\t\t_draw_label(rect.position + Vector2(20.0, rect.size.y - 51.0), _formal_status, 8, Color(0.72, 0.78, 0.72, 0.92))\n',
            ),
        ],
    )
    patch(
        "scripts/formal/formal_world_simulation.gd",
        [
            (
                '\tvar parsed := JSON.parse_string(file.get_as_text())\n',
                '\tvar parsed: Variant = JSON.parse_string(file.get_as_text())\n',
            ),
        ],
    )
    print("corrected generated formal-world sources")


if __name__ == "__main__":
    main()
