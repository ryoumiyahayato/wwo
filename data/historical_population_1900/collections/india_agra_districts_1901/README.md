# Agra districts, 1891 and 1901

`agra_districts.csv` contains two returns for each of the 36 districts under N.-W. Provinces, also called Agra. Table II, printed p. 6 (PDF p. 10), rows 1–36, columns 3–4 give the persons on 1 March 1901 and 26 February 1891. The facing note states that the earlier returns were adjusted to the districts as of 1 March 1901. Its uniform-density estimates apply to specified 1872 and 1881 figures. Table I, printed pp. 2–3 (PDF pp. 6–7), rows 1–36, columns 9, 12 and 15 gives 1901 persons, males and females. District sex counts for 1891 are blank. [Table II note](https://censusindia.gov.in/nada/index.php/catalog/31349/download/34530/140099_1901.pdf#page=9), [Table II district rows](https://censusindia.gov.in/nada/index.php/catalog/31349/download/34530/140099_1901.pdf#page=10), [Table I sex columns](https://censusindia.gov.in/nada/index.php/catalog/31349/download/34530/140099_1901.pdf#page=7).

| Division | Districts | 1891 persons | 1901 persons | 1901 males | 1901 females |
|---|---:|---:|---:|---:|---:|
| Meerut | 6 | 5,326,833 | 5,979,711 | 3,187,455 | 2,792,256 |
| Agra | 6 | 4,767,375 | 5,249,542 | 2,834,805 | 2,414,737 |
| Rohilkhand | 6 | 5,344,058 | 5,479,688 | 2,920,879 | 2,558,809 |
| Allahabad | 7 | 5,757,121 | 5,540,702 | 2,837,344 | 2,703,358 |
| Benares | 5 | 5,368,480 | 5,069,020 | 2,483,654 | 2,585,366 |
| Gorakhpur | 3 | 6,508,526 | 6,333,012 | 3,163,339 | 3,169,673 |
| Kumaun | 3 | 1,181,567 | 1,207,030 | 621,309 | 585,721 |
| N.-W. Provinces | 36 | 34,253,960 | 34,858,705 | 18,048,785 | 16,809,920 |

The district sums match all seven printed division rows and the published provincial control. Each of the 36 districts closes to persons in the 1901 male and female columns. Three blurred 1891 entries also reconcile to the printed prior count and change or the printed change into 1901. Muttra totals 713,421, Etáwah 727,629 and Basti 1,785,844. Etáwah totals 806,798 in 1901 in Tables I and II. [Table II district rows](https://censusindia.gov.in/nada/index.php/catalog/31349/download/34530/140099_1901.pdf#page=10), [Table I sex columns](https://censusindia.gov.in/nada/index.php/catalog/31349/download/34530/140099_1901.pdf#page=7).

Use the main Allahabad row 23. It counts 1,489,358 in 1901. Its alternate Ajodhya fair figure is 1,493,755, an addition of 4,397. The main Fyzabad row inside Oudh counts pilgrims at the place of enumeration. Its alternate figure removes 20,407 people, of whom only part are reflected in Allahabad's alternate figure. Oudh districts are rows 37–48. Rampur and Tehri Garhwal are the separately accounted native states at rows 49–50. Garhwál row 36 belongs to British Agra. The 36 district totals include city residents. The three place candidates in the CSV are the existing city points of Agra, Allahabad and Benares in the India strategic shard and dated transport place index. The India strategic shard has no district boundaries. [Table II district rows](https://censusindia.gov.in/nada/index.php/catalog/31349/download/34530/140099_1901.pdf#page=10), [Table VI fair note](https://censusindia.gov.in/nada/index.php/catalog/31349/download/34530/140099_1901.pdf#page=41).

## Reconciliation to the opening account

India-wide Table II-A retains the area enumerated in 1891 and the administrative divisions of 1891. Printed p. 10, row 12, gives the Agra subrow directly as 34,254,254 in 1891 and 34,858,999 in 1901. Oudh has the same persons in both books. This fixes the 294-person net difference between Agra series at each date. India Table II-A's 1901 Agra sex totals are 18,049,159 males and 16,809,840 females. Compared with the provincial total the net differences are +374 males and −80 females. The difference has no verified assignment to a county, sex or place. Its CSV rows use the role `accounting_residual`; their value is a reconciliation and their sex/place fields are blank. [India Table II-A note, printed p. 9](https://archive.org/details/in.ernet.dli.2015.55924/page/n13/mode/1up), [India Table II-A counts, printed p. 10](https://archive.org/details/in.ernet.dli.2015.55924/page/n14/mode/1up).

The v26 opening replaces `raj_agra_remainder` with 36 direct members of `raj_agra_oudh` and one reconciliation account. At the elapsed fraction of 3231/3655 the district control is 34,788,551.271 before rounding. The 36 district accounts total 34,788,551, and the unlocated account retains 294. Version 25 and earlier saves retain their original accounts. Population at 1900 is modeled at the common March 1901 census extent. The source gives no interval for the discrepancy with actual 1900 boundaries or the interpolation error.

The 1901 local sex counts constrain each district's age model. The age-band shares are from the provincial and joint Agra–Oudh reports. `religion.csv` supplies each district's original religion counts. The 294-person reconciliation has no assigned geography, sex, age or religion. [Religion table notes](religion_sources.md)
