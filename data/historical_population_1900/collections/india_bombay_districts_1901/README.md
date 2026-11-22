# Bombay Presidency and Bombay States, 1891–1901

## Published district counts

R. E. Enthoven, *Census of India, 1901, Volume IX-A, Bombay, Part II, Imperial Tables*, Government Central Press, 1902. [Gokhale Institute scan](https://dspace.gipe.ac.in/xmlui/bitstream/handle/10973/18874/GIPE-027715.pdf?isAllowed=y&sequence=3) · [South Asia Open Archives scan](https://www.jstor.org/stable/saoa.crl.25366895) · [Granth Sanjeevani scan record](https://granthsanjeevani.com/jspui/handle/123456789/152911?backquery=%5B%5D&searchWord=00064704).

Table II, printed p. 5, describes the adjustment of earlier censuses to the boundaries of 1 March 1901. The census office used actual counts where available and calculated transferred populations from district density elsewhere. Printed p. 6 gives persons in columns 2 (1901) and 3 (1891), and p. 7 gives males in columns 10 and 11 and females in columns 14 and 15 for those dates. Row 2 is British Districts and row 31 is Native States and Agencies. The 24 disjoint British leaves are rows 3, 5–10, 12–17, 19–24, and 26–30. Aden is separately listed at row 55. Baroda has a separate census volume and All-India account.

The district counts were cross-read against Vol. IX, Part I, p. 43, “Comparison of actual and estimated Population,” actual persons columns 2 and 5. The report gives independent readings for OCR substitutions in the Part II scan, including Kaira, Panch Mahals, Thana, Bijapur, Kanara, Ratnagiri, Shikarpur and Upper Sind Frontier. Central Division closes to the p. 3 Table I 1901 control and the p. 7 Table II 1891 male and female sum. [Part I scan](https://sanipanhwar.com/uploads/books/2024-10-30_04-19-08_ec87ef8b44f804ad6875ace933bc9588.pdf) · [Sind Library Part I scan](https://kitaab.sindh.org/Census_Of_India_1901_%28Vol_9_Part_1%29-R_E_Enthoven-1902-OCR.pdf).

| Table II geography | Leaves | 26 February 1891 | 1 March 1901 |
|---|---:|---:|---:|
| Bombay City | 1 | 821,764 | 776,006 |
| Northern Division | 6 | 3,917,777 | 3,513,532 |
| Central Division | 6 | 6,211,531 | 5,944,447 |
| Southern Division | 6 | 5,008,063 | 5,070,692 |
| Sind | 5 | 2,875,100 | 3,210,910 |
| British Districts | 24 | 18,834,235 | 18,515,587 |

Larkana was created in August 1901 from talukas of Shikarpur and Karachi, after both opening and census. It is outside the selected table rows. Khandesh remains one district because the division into East and West took place in 1906. Hyderabad in the district CSV is the Sind district. The census treats Hyderabad State and Baroda as separate territories. The two verified point bindings are `place:bombay` and `place:karachi`. [Imperial Gazetteer, vol. VIII, Bombay Presidency](https://library.bjp.org/jspui/bitstream/123456789/1941/1/The-Imperial-Gazetteer-Of-India-Vol-8%28Berhampore%20to%20Bombay%29.pdf).

## Reconciliation with All-India Table II-A

All-India Table II-A (Vol. I-A, pp. 9–10), uses the 1891 geography for the comparison. The existing British Presidency account subtracts Aden from row 6. Existing Bombay States uses row 15. The provincial table uses the 1901 geography. Move the two benchmark pairs together. The shift of 22,809 is present at both benchmarks, with the exact opposite change in the other account. Part I, p. 9 records the move of the Mehwás estates from the Khandesh district census treatment to the attached political agency. The 22,809 is a net accounting difference between the two official scopes. [All-India Table II-A](https://archive.org/details/in.ernet.dli.2015.55924/page/n14/mode/1up) · [Part I scan](https://kitaab.sindh.org/Census_Of_India_1901_%28Vol_9_Part_1%29-R_E_Enthoven-1902-OCR.pdf).

| Scope | British Districts, 1891 | British Districts, 1901 | States, 1891 | States, 1901 |
|---|---:|---:|---:|---:|
| All-India comparison | 18,857,044 | 18,538,396 | 8,059,298 | 6,885,839 |
| Bombay provincial census | 18,834,235 | 18,515,587 | 8,082,107 | 6,908,648 |
| Combined, either scope | 26,916,342 | 25,424,235 | | |

The existing method with the new benchmarks gives 18,552,552 for British Districts and 7,044,776 for the States on 1 January 1900. Their combined 25,597,328 retains the existing India control. The January 1900 estimates interpolate the common source boundaries. Census enumeration and intercensal change have no quantified error interval.

## Sex controls and age panel

The companion `bombay_endpoint_sex_controls.csv` gives both sex controls for the two scopes of interest in the provincial table. At the 1901 endpoint, 3,513,003 males and 3,395,645 females in Native States and Agencies exactly match the existing Statistical Abstract panel, `india_abstract_bombay_states_1901`. At the 1891 endpoint, 4,131,770 males and 3,950,337 females match the row's persons and the provincial male and female totals when combined with British Districts. The earlier benchmark supplies a direct sex control. Age shares remain modeled for 1900. [Statistical Abstract for British India, 1905](https://www.jstor.org/site/south-asia-open-archives/statistical-abstracts/).

Bombay City has a separate age table. The other 23 districts use their division's interpolated sex totals, apportioned within each division by modeled district population. Each sex uses the provincial age distribution after deducting the city's observed broad age groups proportionally within each fine band. The remaining provincial age distribution includes Aden, whose population and sex counts are excluded from this ledger. The difference is unquantified. [Bombay City age counts](bombay_city_age_1901.md) · [Division sex counts](bombay_division_sex_controls.csv).
