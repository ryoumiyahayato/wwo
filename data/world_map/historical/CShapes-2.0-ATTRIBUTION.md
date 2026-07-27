# CShapes 2.0 attribution and license boundary

`cshapes_1900_snapshot.json` is a transformed snapshot of **CShapes 2.0**
for **1900-03-12**. It is kept as an isolated third-party data provider and is
not represented as project-owned historical research.

- Dataset: CShapes 2.0
- Official page: https://icr.ethz.ch/data/cshapes/
- Citation: Schvitz et al. (2022), *Mapping the International System,
  1886-2019: The CShapes 2.0 Dataset*.
- License: Creative Commons Attribution-NonCommercial-ShareAlike 4.0
  International (CC BY-NC-SA 4.0).
- Commercial use: not allowed by this provider's license.
- Transformation: select records active on 1900-03-12, simplify geometry with
  topology preservation at 0.08 degrees, round coordinates to four decimals.

A future commercial build must replace or omit this provider. Runtime code is
therefore required to load historical geometry through a provider boundary and
must not silently fall back to modern Natural Earth polygons.
