"""Comparable search index of city observations, with source-specific boundaries."""
import csv
from collections import defaultdict
from datetime import date
from pathlib import Path

def city_index(rows,band):
    path=Path(__file__).resolve().parent/"collections/cities_europe/city_equivalences.csv"
    with path.open(encoding="utf8") as f:
        relationships={r["member_unit_id"]:r["relationship"] for r in csv.DictReader(f)}
    cities=defaultdict(list)
    reference=date(1900,1,1)
    for r in rows:
        if r["kind"]=="city":
            cities[r["city_key"]].append(r)
    output=[]
    for key,observations in sorted(cities.items()):
        candidates=[]
        for r in observations:
            date_string=r["date"]
            try:
                measured=date.fromisoformat(date_string if len(date_string)==10 else date_string+"-07-01" if len(date_string)==4 else date_string+"-15")
            except ValueError:
                continue
            distance=abs((measured-reference).days)
            if distance>5*366 or r.get("quality")=="disputed_geocode" or r["population_value"] is None:continue
            relation=relationships.get(r["unit_id"],"")
            is_secondary=r["source_id"]=="reba_chandler_1900"
            broader="suburb" in relation.lower() or "agglomeration" in relation.lower()
            # Prefer a dated primary municipal return inside +/-5 years. Its
            # census date remains explicit; it is not rebased to opening day.
            candidates.append(((is_secondary,broader,distance,r["unit_id"],r["record_id"]),r))
        preferred=min(candidates,key=lambda x:x[0])[1] if candidates else None
        geographic=next((r for r in observations if r.get("latitude") is not None and r.get("longitude") is not None and r.get("quality")!="disputed_geocode"),{})
        output.append(dict(city_key=key,name=(preferred or observations[0])["name"],representative_record=preferred["record_id"] if preferred else None,
            population_value=preferred["population_value"] if preferred else None,source_date=preferred["date"] if preferred else None,
            source_id=preferred["source_id"] if preferred else None,definition=preferred["definition"] if preferred else None,
            tier=band(preferred["population_value"]) if preferred else None,source_parent_id=preferred["parent_id"] if preferred else None,
            latitude=geographic.get("latitude"),longitude=geographic.get("longitude"),coordinate_record=geographic.get("record_id"),
            evidence=[r["record_id"] for r in observations],observed_tiers=sorted({band(r["population_value"]) or "below_50k_or_unknown" for r in observations}),
            status="dated_reference_nonadditive" if preferred else "unresolved_or_outside_date_window"))
    return output
