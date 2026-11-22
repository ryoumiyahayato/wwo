# Egypt 1907 age and literacy observations

The Ministry of Finance Census Department published the 1907 census in Cairo in 1909. The two census dates used for existing opening controls are 1 June 1897 and 29 April 1907. The Arabic edition is held by Princeton and digitized by Arabic Collections Online. [Census volume](https://sites.dlib.nyu.edu/viewer/books/princeton_aco003741/display?lang=ar)

## Source columns and scope

- `table_xi_opening_age_sex.csv` records the five reported age bands (0–4, 5–9, 10–14, 15–19 and 20+) and a control for each of the 16 v34 opening accounts. The table gives four cells by age, sex and census literacy status. Male equals columns 3 plus 5. Female equals columns 4 plus 6. Page 121 refers to reading and says the 1897 census lacked literacy by age for the provinces and districts. [Explanation p. 121](https://sites.dlib.nyu.edu/viewer/api/image/books/princeton_aco003741/149/full/1600,/0/default.jpg) [Table XI starts p. 123](https://sites.dlib.nyu.edu/viewer/api/image/books/princeton_aco003741/151/full/1600,/0/default.jpg)
- `table_xi_province_markaz_source_rows.csv` preserves the 60 disjoint district rows used for ten province totals. Match Table V and Table XI by the printed serial number. The Table XI scan is 28 sequence numbers after its print page. Nag Hammadi (p. 141, row 91) gives printed person totals 28,978 and 18,726 at ages 5–9 and 10–14. The four printed sex-and-literacy cells yield 28,976 and 18,727. Those cells close to each printed sex-and-literacy total and to the printed all-age total of 188,047. The CSV preserves both the cell sum and the printed person total. [Table XI p. 141](https://sites.dlib.nyu.edu/viewer/api/image/books/princeton_aco003741/169/full/1600,/0/default.jpg)
- `table_5_sex_scope_controls.csv` gives the full comparison population, Table XI age coverage, and the difference by sex. Table V columns 2, 5 and 7 report the 1897 comparison total, males and females. Columns 3, 6 and 8 give the respective 1907 counts. The asterisk footnote on p. 32 identifies rows including estimated nomadic tribes. The six marked districts below account for all 24,561 omissions across the v34 accounts. Table V Cairo and Alexandria are separate urban governorates. Faiyum has three disjoint district rows in the opening. The province aggregate carries no additional count. Asyut includes Kharga, Dakhla and Mallawi. [Table V p. 30](https://sites.dlib.nyu.edu/viewer/api/image/books/princeton_aco003741/56/full/1600,/0/default.jpg) [p. 31](https://sites.dlib.nyu.edu/viewer/api/image/books/princeton_aco003741/57/full/1600,/0/default.jpg) [p. 32](https://sites.dlib.nyu.edu/viewer/api/image/books/princeton_aco003741/58/full/1600,/0/default.jpg)
- `table_viii_national_age_sex.csv` is a separate national age distribution. Its 12 age bins close to 5,616,640 males and 5,573,338 females for 11,189,978 people. The 1907 total of 11,287,359 includes 97,381 further people from the estimated nomadic population. Do not use the national shape to fill local ages. [Table VIII p. 116](https://sites.dlib.nyu.edu/viewer/api/image/books/princeton_aco003741/144/full/1600,/0/default.jpg)

| Region | Missing 1907 males | Missing 1907 females | Marked Table V rows |
| --- | ---: | ---: | --- |
| Menufiya | 220 | 215 | p. 31, row 47, Tala |
| Asyut | 2,309 | 1,791 | p. 31, row 57, Dirut |
| Jirja | 2,838 | 2,131 | p. 32, row 81, Balyana |
| Qena | 4,416 | 3,941 | p. 32, row 88, Dishna (148 male, 124 female), and row 90, Qus (4,268 male, 3,817 female) |
| Sharqiya | 3,100 | 3,600 | p. 30, row 27, Faqus |

## Applying the observations to the opening

Use Table V's same-scope population and sex counts at both dates. Interpolate each sex to 1 January 1900. For each sex, calculate the Table V minus Table XI share against the same Table V sex denominator. Treat the omitted share as an age-unknown category. Use largest remainders within each opening sex control across the five age bands and any age-unknown category. Keep ages 20 and above in one open interval. Literacy shares may use the jointly observed local sex and age cells if required. Keep the omitted age and literacy coverage unknown.

The age census is 2,674 days after the opening. This model assumes stable local age shares within each sex over 7.32 years. The census describes adult age misstatement and heaping. Migration, reported adult age and changes below province boundaries have no quantified error interval. The existing city controls also carry urban boundary uncertainty. [Age discussion p. 115](https://sites.dlib.nyu.edu/viewer/api/image/books/princeton_aco003741/143/full/1600,/0/default.jpg)

| Opening version | Local accounts | Located population | Opening ages modeled | Local ages unknown | National unlocated population |
| --- | ---: | ---: | ---: | ---: | ---: |
| v33 | 11 | 5,814,464 | 5,798,089 | 16,375 | 4,185,536 |
| v34 | 16 | 8,546,656 | 8,524,349 | 22,307 | 1,453,344 |

Cairo and Alexandria also have a separate literacy distribution from age five. The under-five share remains unknown for literacy.

## Provinces added in v34

`observations.jsonl` records the two Table V endpoints for the five provinces. Page 29 compares the original 1897 counts with the 1897 counts restated for the 1907 areas. The opening uses the restated counts. Daqahliya includes Damietta markaz. Qalyubiya includes the Cairo suburbs listed outside the separate city governorate. Giza's restated count drops by 400, consistent with the table's explanation of the transfer of Wadi el Natrun to Lower Egypt. Beni Suef's restated count drops by 2,339 and Minya's rises by the same amount. The table gives the net difference at province level. [Table V p. 29](https://sites.dlib.nyu.edu/viewer/api/image/books/princeton_aco003741/55/full/1600,/0/default.jpg)

| Province | Original 1897 | Adjusted 1897 | 1907 | Table V rows | Table XI pages |
| --- | ---: | ---: | ---: | --- | --- |
| Daqahliya | 736,708 | 780,480 | 912,428 | p. 30, 19–24 | 126–127 |
| Sharqiya | 749,130 | 748,972 | 886,346 | p. 30, 25–30 | 127–128 |
| Qalyubiya | 371,465 | 371,602 | 434,575 | p. 31, 42–45 | 131 |
| Giza | 401,634 | 401,234 | 460,080 | p. 32, 63–66 | 135–136 |
| Beni Suef | 314,454 | 312,115 | 372,412 | p. 32, 77–79 | 138 |

## Alexandria and Ramleh

Table V p. 30 separates Alexandria row 2 from Ramleh row 11 in Beheira. Preserve the two rows and both dates separately when revising geography. The legacy Alexandria endpoint 319,766 is exactly the sum of the two 1897 Table V rows, while the legacy 1907 endpoint 332,246 equals only the Alexandria row. Their two 1907 returns are disjoint. The linearly interpolated populations are 308,541 for Alexandria and 24,335 for Ramleh. The country control remains 10,000,000. The two accounts reduce the unlocated balance by 9,854. Ramleh must be excluded from any future separate Beheira parent balance or accounted for as a child only.

| Scope | 1897 male | 1897 female | 1897 total | 1907 male | 1907 female | 1907 total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Cairo | 302,857 | 267,205 | 570,062 | 346,965 | 307,511 | 654,476 |
| Alexandria | 158,390 | 141,782 | 300,172 | 175,862 | 156,384 | 332,246 |
| Ramleh | 10,209 | 9,385 | 19,594 | 19,461 | 18,302 | 37,763 |

`table_xi_opening_age_sex.csv` includes the census age and literacy profile for Ramleh. Ramleh literacy remains in the research table. Both sex totals close to Table V. Its common statistical entry is available in both returns. A geometric boundary crosswalk has not been verified. [Table V p. 30](https://sites.dlib.nyu.edu/viewer/api/image/books/princeton_aco003741/56/full/1600,/0/default.jpg) [Table XI p. 125](https://sites.dlib.nyu.edu/viewer/api/image/books/princeton_aco003741/153/full/1600,/0/default.jpg)
