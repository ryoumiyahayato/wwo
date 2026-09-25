# Pinned OpenHistoricalMap Planet Byte Verification

This contract governs byte acquisition for the pinned raw source
`territory_source:openhistoricalmap_planet_2026_09_08_0001`. It does not alter
the Territory Source Registry, production admission classifications, Formal
runtime composition, Population, TerritoryUnitCatalog, or territorial
controller ownership.

The authoritative acquisition metadata is
`data/source_acquisition/territory/openhistoricalmap_planet_2026_09_08_0001.json`.
The 1.2 GB planet payload remains external to the repository.

## Verification procedure

1. Fetch exactly `https://s3.amazonaws.com/planet.openhistoricalmap.org/planet/planet-260908_0001.osm.pbf`.
   Do not resolve a latest pointer, wildcard, replication diff, full-history
   dump, or regional extract.
2. Record the downloaded file's exact byte count as `exact_byte_size`.
3. Compute SHA-256 directly over the raw `.osm.pbf` byte stream and record the
   lowercase hexadecimal digest as `raw_sha256`.
4. Read PBF header metadata with a deterministic PBF-aware tool such as
   `osmium fileinfo --extended` and record its UTC dataset/header timestamp as
   `pbf_header_timestamp`.
5. Confirm the object is the normal complete daily planet snapshot. Evidence
   must include the official `planet/planet-YYMMDD_HHMM.osm.pbf` archive
   identity and PBF metadata; replication updates, full-history dumps, and
   extracts do not satisfy this check. Set `complete_planet_verified=true`
   only after this check passes.
6. Confirm timestamp consistency. `snapshot_timestamp` must exactly equal the
   timestamp encoded in the filename. The PBF header timestamp must not be
   later than the pinned filename timestamp and must be no more than 24 hours
   earlier, allowing the dump header to describe the database cutoff that
   immediately precedes publication.
7. Confirm the downloaded bytes came from the exact pinned URL and filename.
   No substitute object may inherit this source identity.
8. Set `acquisition_status=VERIFIED` and `verification_status=PASSED` only when
   every required check passes. Before that point the record remains
   `PINNED_AWAITING_BYTES` or, after a successful download but before complete
   verification, `ACQUIRED`.
9. Recompute `record_fingerprint` using
   `tools/world_data/territory_source_acquisition.py`. The fingerprint is
   SHA-256 over canonical JSON containing stable identity and verification
   fields only. It intentionally excludes `acquired_at`, status fields, and
   free-form notes so wall-clock timing does not affect evidence identity.

## Raw byte commands

A byte-acquisition task may use equivalent tooling, but it must produce the
same facts. Typical commands are:

```text
curl --fail --location --output planet-260908_0001.osm.pbf https://s3.amazonaws.com/planet.openhistoricalmap.org/planet/planet-260908_0001.osm.pbf
python -c "from pathlib import Path; p=Path('planet-260908_0001.osm.pbf'); print(p.stat().st_size)"
python -c "import hashlib; p='planet-260908_0001.osm.pbf'; h=hashlib.sha256(); f=open(p,'rb'); [h.update(b) for b in iter(lambda:f.read(1048576), b'')]; print(h.hexdigest())"
osmium fileinfo --extended planet-260908_0001.osm.pbf
```

The acquired raw file is evidence input, not a repository asset. It must stay
outside Git and must not be treated as production geography until the later
historical extraction, license audit, geometry validation, derivation trace,
and Territory Source Registry admission gates all pass.
