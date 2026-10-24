"""Retired R3 political-difference repair entrypoint.

Syvash is now an input of the common independent physical derivation. The
original Natural Earth land and lake files are retained. This historical
entrypoint must not recreate two legacy difference shards over R27 data.
"""
if __name__ == '__main__':
 raise SystemExit('R27 replaces the Syvash difference repair. Use tools/map/build_geographic_foundation.py --independent --political-ink --apply; omit --political-ink for a physical-only derivation.')
