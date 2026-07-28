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


def insert_before(path: str, anchor: str, insertion: str, marker: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if marker in text:
        return
    if anchor not in text:
        raise RuntimeError(f"missing insertion anchor in {path}: {anchor!r}")
    text = text.replace(anchor, insertion.rstrip() + "\n\n\n" + anchor, 1)
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
            (
                'func _capture_economy_day_state() -> Dictionary:\n'
                '\treturn {\n'
                '\t\t"economy": economy.get_persistent_state(),\n'
                '\t\t"commodity_market": commodity_market.get_persistent_state(),\n'
                '\t\t"economy_integration": economy_integration.get_persistent_state(),\n'
                '\t\t"enterprise": enterprise.get_persistent_state(),\n'
                '\t\t"labor": labor.get_persistent_state(),\n'
                '\t}\n\n\n'
                'func _restore_economy_day_state(snapshot: Dictionary) -> bool:\n'
                '\tvar ok := economy.restore_persistent_state(snapshot.get("economy", {}) as Dictionary)\n'
                '\tok = commodity_market.restore_persistent_state(snapshot.get("commodity_market", {}) as Dictionary) and ok\n'
                '\tok = enterprise.restore_persistent_state(snapshot.get("enterprise", {}) as Dictionary) and ok\n'
                '\tok = labor.restore_persistent_state(snapshot.get("labor", {}) as Dictionary) and ok\n'
                '\tok = economy_integration.restore_persistent_state(snapshot.get("economy_integration", {}) as Dictionary) and ok\n'
                '\treturn ok\n',
                'func _capture_economy_day_state() -> Dictionary:\n'
                '\treturn {\n'
                '\t\t"ledger": economy.ledger.create_transaction_checkpoint(),\n'
                '\t\t"assets": economy.assets.get_persistent_state(),\n'
                '\t\t"contracts": economy.contracts.get_persistent_state(),\n'
                '\t\t"markets": economy.markets.duplicate(true),\n'
                '\t\t"external_events": economy.external_events.duplicate(true),\n'
                '\t\t"commodity_market": commodity_market.get_persistent_state(),\n'
                '\t\t"economy_integration": economy_integration.get_persistent_state(),\n'
                '\t\t"enterprise": enterprise.get_persistent_state(),\n'
                '\t\t"labor": labor.get_persistent_state(),\n'
                '\t}\n\n\n'
                'func _restore_economy_day_state(snapshot: Dictionary) -> bool:\n'
                '\tvar ok := economy.ledger.restore_transaction_checkpoint(\n'
                '\t\tsnapshot.get("ledger", {}) as Dictionary\n'
                '\t)\n'
                '\tok = economy.assets.restore_persistent_state(snapshot.get("assets", {}) as Dictionary) and ok\n'
                '\tok = economy.contracts.restore_persistent_state(snapshot.get("contracts", {}) as Dictionary) and ok\n'
                '\teconomy.markets = (snapshot.get("markets", {}) as Dictionary).duplicate(true)\n'
                '\teconomy.external_events = DataRecordUtils.to_dictionary_array(\n'
                '\t\tsnapshot.get("external_events", [])\n'
                '\t)\n'
                '\tok = commodity_market.restore_persistent_state(snapshot.get("commodity_market", {}) as Dictionary) and ok\n'
                '\tok = enterprise.restore_persistent_state(snapshot.get("enterprise", {}) as Dictionary) and ok\n'
                '\tok = labor.restore_persistent_state(snapshot.get("labor", {}) as Dictionary) and ok\n'
                '\tok = economy_integration.restore_persistent_state(snapshot.get("economy_integration", {}) as Dictionary) and ok\n'
                '\treturn ok\n',
            ),
        ],
    )
    insert_before(
        "scripts/alpha/alpha_ledger_service.gd",
        "func get_persistent_state() -> Dictionary:",
        '''func create_transaction_checkpoint() -> Dictionary:
\t# Transaction dictionaries are immutable after posting, so the transaction
\t# array and key index only need shallow copies. Account balances are mutable
\t# and therefore retain an independent deep copy.
\treturn {
\t\t"accounts": accounts.duplicate(true),
\t\t"transactions": transactions.duplicate(),
\t\t"transactions_by_key": _transactions_by_key.duplicate(),
\t\t"processed_key_order": _processed_key_order.duplicate(),
\t\t"next_sequence": _next_sequence,
\t}


func restore_transaction_checkpoint(checkpoint: Dictionary) -> bool:
\tif (
\t\tnot checkpoint.get("accounts", {}) is Dictionary
\t\tor not checkpoint.get("transactions", []) is Array
\t\tor not checkpoint.get("transactions_by_key", {}) is Dictionary
\t\tor not checkpoint.get("processed_key_order", []) is Array
\t):
\t\treturn false
\taccounts = (checkpoint.get("accounts", {}) as Dictionary).duplicate(true)
\ttransactions = DataRecordUtils.to_dictionary_array(
\t\tcheckpoint.get("transactions", [])
\t)
\t_transactions_by_key = (
\t\tcheckpoint.get("transactions_by_key", {}) as Dictionary
\t).duplicate()
\t_processed_key_order = DataRecordUtils.to_string_array(
\t\tcheckpoint.get("processed_key_order", [])
\t)
\t_next_sequence = maxi(1, int(checkpoint.get("next_sequence", 1)))
\treturn bool(validate_balances().get("success", false))''',
        "func create_transaction_checkpoint()",
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
