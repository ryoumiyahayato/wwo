"""Deterministic physical coal providers and separate coarse directory metadata."""
from dataclasses import asdict
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "multi_round4b"))
from run_multi_supplier_experiment import make_case as multi_case
from supplier_directory import DirectoryEntry


def supplier_ids(count):
    if type(count) is not int or count < 2:
        raise ValueError("at least two suppliers")
    return ["A", "D"] + (["E"] if count >= 3 else []) + [f"S{i:03d}" for i in range(3, count)]


def generate_pool(count):
    config = multi_case("pool")["config"]
    ids = supplier_ids(count)
    config["available_supplier_ids"] = ids
    config["supplier_routes"] = {"A": "A_B", "D": "D_B"}
    config["supplier_state"] = {supplier: dict(active=True, route_available=True) for supplier in ids}
    entries = []
    for i, supplier in enumerate(ids):
        if supplier not in ("A", "D"):
            capacity = (20, 40, 60, 100)[i % 4]
            lead = (2, 4, 6, 8)[i % 4]
            config["initial_inventory"][supplier] = dict(coal=400, steel=0, machine=0)
            config["production"][supplier] = dict(capacity=(20, 40, 60, 80)[i % 4], coal_target=400)
            route = supplier + "_B"
            config["routes"][route] = dict(supplier=supplier, buyer="B", commodity="coal", capacity=capacity, lead_time=lead)
            config["supplier_routes"][supplier] = route
        spec = config["routes"][config["supplier_routes"][supplier]]
        entries.append(DirectoryEntry(supplier, "coal", "Z0" if supplier in ("A", "D") else f"Z{i % 10}",
                                      "place_"+supplier, True, spec["lead_time"], f"up_to_{spec['capacity']}"))
    config["directory_entries"] = [asdict(e) for e in entries]
    return config
