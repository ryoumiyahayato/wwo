# Arabia / Gulf historical source inputs — M2.6

Target map date: 1900-01-01. All new geography is APPROXIMATE, not a surveyed frontier or an exact OHM/CShapes feature.

S. M. Zwemer, *Arabia: The Cradle of Islam* (1900), contemporary observations including a preface written in Bahrain in 1899. [Digitized book and plates](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html).

Pinned source images are unmodified Project Gutenberg JPEGs:

- `arabia_zwemer_1900_map.jpg`: [folding map, graticule, physical coastline and regional names](https://www.gutenberg.org/cache/epub/63928/images/illus-484-thumb.jpg).
- `bahrain_zwemer_1900_map.jpg`: [Bahrain islands map, p.98](https://www.gutenberg.org/cache/epub/63928/images/illus-098.jpg).
- `arabia_zwemer_1900_flags.jpg`: [four Arabian flags illustration, p.217](https://www.gutenberg.org/cache/epub/63928/images/illus-217.jpg).

The original 1900 work is public domain in the United States; Gutenberg supplies its applicable reuse notice in the linked book. These scans are historical references, not a claim that every boundary or flag depicted was precisely valid on January 1.

`arabia_1900_traces.json` is WWO's authored, coarse longitude/latitude interpretation of the historical graticule, coastline, named administrative cores and contemporary descriptions. It is not an automatic georeference or a survey-grade tracing. Interior straight segments are explicitly bounded approximations. No modern Saudi, Yemen, Kuwait, Qatar or Bahrain administrative border data is an input. No modern Bahrain reclamation, airports or causeways are added.

The builder subtracts existing CShapes geography, which always has priority. It preserves the original 151 features and 1604 exteriors. This overlay introduces a dependency on the existing CShapes CC BY-NC-SA 4.0 source: the generated supplement retains that attribution and noncommercial/share-alike restriction. Its existing source-registry license admission remains REFERENCE_ONLY; M2.6 does not alter the project's commercial licensing decision.

Additional authority evidence:

- [India Office treaties, fifth edition, 1933, IOR/L/PS/20/G3/12](https://www.qdl.qa/en/archive/81055/vdc_100023462214.0x000011): dated 1888/1895/1896 Wahidi and Quaiti treaties, and a distinct 1918 Kathiri agreement. The compilation publication date is not the treaty date.
- [Socotra and Qishn protectorate treaty, 23 April 1886](https://qdl.qa/en/archive/81055/vdc_100023462215.0x00000b): Mahra local ruler, not British annexation.
- [Kuwait government historical account](https://e.gov.kw/sites/kgoenglish/Pages/Visitors/AboutKuwait/GoverningBodyOverView.aspx): Mubarak and the exclusive agreement of 23 January 1899; no 1922 Uqair boundary is imported.
- [Qatar Amiri Diwan, Jassim Al Thani](https://www.diwan.gov.qa/about-qatar/qatars-rulers/sheikh-jassim-bin-mohammed-bin-thani): local authority and Ottoman relationship; no 1916 British protectorate is backdated.
- [National Army Museum, NAM.1998-03-21-1](https://collection.nam.ac.uk/detail.php?acc=1998-03-21-1): BSAC administration and company flag context, 1890–1923. Museum photographs are not copied.
- [Derbyshire Record Office D3287/BSA/8/6, 24 April 1899](https://calmview.derbyshire.gov.uk/CalmView/Record.aspx?id=D3287%2FBSA%2F8%2F6&src=calmview.catalog): Codrington's deputy administration at Fort Jameson before the 1900 Order.
- [SR&O 1901 collection, Order No.567](https://upload.wikimedia.org/wikipedia/commons/a/ab/UKSRO_1901.pdf): Barotziland–North-Western Rhodesia Order signed 28 November 1899. Printed collection year is not signature date or proof of the commencement date.

Local registry, pinned-source folders and acquired historical assets were searched first. No existing Arabia/Gulf historical polygon was found. OHM Overpass access returned HTTP 403; that is an access limitation, not evidence that OHM contains no relevant data. The admitted supplement therefore follows the explicitly permitted bounded historical-map approximation route.
