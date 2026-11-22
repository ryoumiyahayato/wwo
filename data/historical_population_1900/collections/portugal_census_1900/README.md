# Portuguese kingdom census observations, 1890 and 1900

The censuses count people present on December 1 of each census year. Their territory includes mainland Portugal, the Azores and Madeira. Overseas possessions are outside the totals. The original tables place Setúbal within Lisboa district.

| Census | Present | Male | Female | Age unknown |
| --- | ---: | ---: | ---: | ---: |
| 1890-12-01 | 5,049,729 | 2,430,339 | 2,619,390 | 19,165 |
| 1900-12-01 | 5,423,132 | 2,591,600 | 2,831,532 | 12,119 |

- `district_population_sex_1890_1900.csv` records the 21 districts as published at both dates. Vol. I, Quadro I, printed p. 2. PDF page 121 in the 1890 facsimile and page 12 in the 1900 facsimile. Counts close by sex to the mainland, adjacent islands and kingdom total. Districts are paired by name across censuses. Administrative changes may affect individual district boundaries.
- `age_sex.csv` gives six census panels for the kingdom, Lisboa district and Porto district at both dates. Vol. II, Quadro I, printed p. 2, kingdom. Vol. II, Quadro II, printed pp. 28 and 32, Lisboa and Porto districts. PDF pages 464, 490 and 494 for 1890 and pages 362, 388 and 392 for 1900. Both years use the common classes of ages 0–14 by single year, 15–99 in five-year groups, 100 or older, and age unknown. The 1890 source also prints 15–20 by single year and 21–24 as a group.
- `national_marital_status.csv` records the published all-age counts by sex. Vol. II, Quadro I, printed pp. 2–3, PDF pages 464–465 for 1890 and 362–363 for 1900. The 1900 census adds a category for judicial separation. Male and female counts close to the census controls at each date.

In the 1890 national age panel, the published totals for ages 50–54, 75–79 and 85–89 disagree with their male and female columns. The CSV sets these totals to 259,298, 43,699 and 8,032 from the source sex columns, which close to the independently published national totals. The 1900 age proportions also agree with the totals transcribed in the EDU20c raw workbook after using its 85+ grouping.

Both censuses are observations at different dates from the opening. Using either census alone or combining them at 1900-01-01 yields an estimate. The same applies to allocating the 19 districts without a transcribed age panel using a wider age distribution.

The v26 opening interpolates the two district populations. The Lisboa and Porto opening age cells use both local tables. For the other 19 districts, subtract Lisboa and Porto from each national age-by-sex table. Combine those residual age profiles with each district's census sex counts at both dates and then interpolate. The model retains unknown ages. Use the district IDs in F7. No district boundaries or point bindings are supplied by these returns.

The 1900 `literacy.csv`, `marital_status.csv`, `religion.csv` and `district_occupation.csv` supply local resident marginals. Opening shares are apportioned within each district. Judicially separated residents are their own marital category. Literacy measures reading. The occupation table separately identifies family members without gainful occupation and domestic servants. The nonproductive or occupation-unknown category remains unknown. Each dimension is independent of age and the other social tables.

[Official 1890 facsimile](https://estatistica.madeira.gov.pt/biblioteca-digital/send/591-biblioteca-digital-social-censos/10257-censo-da-populacao-do-reino-de-portugal-no-1-de-dezembro-de-1890-3-volumes.html)

[Official 1900 facsimile](https://estatistica.madeira.gov.pt/biblioteca-digital/send/591-biblioteca-digital-social-censos/10271-censo-da-populacao-do-reino-de-portugal-no-1-de-dezembro-de-1900-3-volumes.html)

[EDU20c Portugal documentation](https://edu20c.org/portugal/)
