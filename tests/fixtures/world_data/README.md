# WWO World-data Golden Fixtures — Batch 1

`corpus.json` is a small, self-contained fixture corpus derived from the field
names and representative IDs in `data/world_map/**` at master
`4b738ab8b0a21e8685aae95381717e9efd2327a8`.

The documents are intentionally compact. They are test inputs, not a second
authoritative world dataset. Malformed cases extend a valid fixture through a
single explicit mutation, so the defect remains easy to inspect and reuse.

Coverage:

- valid country / region / city hierarchy;
- port and shipping route;
- road graph, rail graph, and multimodal network;
- historical entity, political unit, flag, and geometry references;
- organization / institution / relationship references;
- geometry metadata;
- historical alias collision as a `WARNING` with `NO_CURRENT_RULE`;
- eight controlled malformed cases covering the required defect classes.

The `expected` field records the fixture-level result. `NO_CURRENT_RULE` means
the repository has no production rule for that condition; the focused checker
does not pretend to turn it into gameplay policy.
