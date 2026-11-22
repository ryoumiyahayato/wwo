# France, 1901 departmental occupations

Statistique générale de la France, census of 24 March 1901. INSEE's official release of the historical SGF censuses includes [REC_T257.dbf](https://www.insee.fr/fr/statistiques/fichier/2653233/REC_T257.dbf), [REC_T256.dbf](https://www.insee.fr/fr/statistiques/fichier/2653233/REC_T256.dbf), and the [variable dictionary](https://www.insee.fr/fr/statistiques/fichier/2653233/libelles_var_rec.xls). The contemporary [published census report, pp. 369–370, 379–380](https://www.numdam.org/item/JSFS_1906__47__368_0.pdf) describes the population bases and the national occupational summary.

## Scope and population

The CSV contains the 87 metropolitan department records in REC_T257, with `V1=1`, `V4=00` and `V5=00`. Join to REC_T256 and to `france_opening.json` by the two-digit department code `V3`. The coordinates match each opening department, including departments represented by a statistical parent over smaller opening units. Allocate the occupation distribution only once at each department's scope. T257's French national record and any colonial or nonmetropolitan records are excluded. Codes 57, 67 and 68 are outside the relevant French national returns. Code 99 is the earlier Meurthe label and has no matching T257 department. Meurthe-et-Moselle is included at code 54.

REC_T256 `V21` and `V22` are the published legal (usual) populations, with the same Ardèche and Vendée substitutions already used by `france_opening.json`. For Ardèche in 1901 use `V120=353564` in place of `V22=353464`; `V107`, `V183` and `V191` independently repeat 353564. For Vendée in 1896 use `V114=441735` in place of `V21=441783`; `V89` repeats 441735. The departmental controls sum to 38,517,332 in 1896 and 38,961,945 in 1901. Their opening populations sum to 38,852,748. The contemporary report gives an actual present population of 38,466,924 nationally. The CSV applies the report's legal-population base for occupational rates.

## Variables

T257 groups an individual's reported occupational branch with their employment position. Each record has five broad mutually exclusive branch totals. The published French national table uses nine groups. Departmental branches cannot be split into the nine national groups from T257.

| CSV branch | SGF sections or groups | T257 fields | Of these, `sans emploi` |
| --- | --- | --- | --- |
| Pêches, forêts et agriculture | Sections 1 and 2 | V9–V14 | V13 |
| Industrie | Sections 3, 4 and 5, plus group 9b | V15–V20 | V19 |
| Commerce | Section 6 and group 8a | V21–V26 | V25 |
| Service domestique | Group 8b | V27–V28 | V28 |
| Professions libérales | Section 7 and group 9a, including public services | V29–V34 | V33 |

- `active_population` is V7. `occupation_unspecified` is V8. The five branch totals include the corresponding published `sans emploi` positions where an occupational branch was identified.
- `unemployed_*` are the corresponding `sans emploi` subtotals. Their sum is `unemployed_total`. They are already counted in the five branch totals. A distribution limited to census-classified workers can subtract each subtotal from its corresponding branch and retain it in the unallocated count.
- `occupation_total` sums the five branch totals. `unknown_legal_proxy` is the legal population less that sum. It contains those outside the recorded active population, V8, and any unreconciled active count. The source gives no occupational breakdown of their dependants.
- `active_unreconciled` is V7 less V8 and the five branch totals. Indre and Manche each retain one person unknown. The national detailed branch total is 19,696,255. The comparable departmental total is 19,696,253, including 303,883 with an identified branch and `sans emploi`. The five branches after those 303,883 are omitted total 19,392,370.

When a T257 department's occupation entries do not close to V7, T256 repeats the detailed fields by sex. A T257 field `Vn` for `9 <= n <= 34` corresponds to T256 male `V(n+190)` and female `V(n+218)`. Replace a T257 figure with this independently reported split only when the resulting detail closes to independently reported active totals. Each replacement is indexed in the row's locator.

| Department code | Corrected T257 field(s), original → sex sum |
| --- | --- |
| 15 | V17 605 → 606 |
| 16 | V20 12,901 → 12,903 |
| 19 | V13 273 → 373 |
| 44 | V14 20,855 → 30,855 |
| 47 | V14 12,305 → 12,306 |
| 53 | V20 9,385 → 9,386 |
| 55 | V13 45 → 145, V27 3,881 → 3,884 |
| 58 | V20 12,995 → 12,996 |
| 64 | V10 59,659 → 52,659 |
| 70 | V19 256 → 266 |
| 73 | V18 11,857 → 11,867 |
| 75 | V20 206,755 → 206,756 |
| 84 | V20 8,941 → 8,944 |
| 88 | V13 393 → 396 |

For code 44, only V14 is replaced. T256 separately disagrees by 30 with T257 V34, whose replacement would contradict both active totals and the independently published national subtotal. For code 70, T257 repeats the Saône-et-Loire label of code 71. T256 identifies code 70 as Haute-Saône and its active totals and detailed figures match that T257 code. For code 84 the numeric code resolves the T256 label spelling `VANCLUSE`.

Proportional allocation of the five branch totals and unknown to each 1900 opening department produces 19,637,865 people with a reported branch (50.5443%). If each branch excludes its `sans emploi` subtotal first, the 1900 count is 19,336,735 (49.7693%). These are alternative views of the same census records.
