# British Bengal districts, 1891 and 1901

E.A. Gait, Census of India, 1901, Vol. VI-A, The Lower Provinces of Bengal and their Feudatories, Part II, Imperial Tables, 1902. Table II, printed p. 6, gives persons in columns 2 and 3 for 1 March 1901 and 26 February 1891. The printed notes on p. 5 describe the earlier returns adjusted to the 1901 jurisdictions. The block headed British Territory contains 47 districts and Calcutta separately. The 24-Parganas figure includes separately enumerated suburbs and excludes the Calcutta city row. Feudatories and British subjects in French Chandernagore are printed separately and excluded here. [Official scan](https://ignca.gov.in/Asi_data/30991.pdf), [scan mirror](https://archive.org/details/in.ernet.dli.2015.55931), [OCR of printed tables](https://archive.org/stream/in.ernet.dli.2015.55931/2015.55931.Census-Of-India-1901-Vol6-a-lower-Probinces-Of-Bengal-And-Their-Leudatoties-Pt2-imperial-Tables_djvu.txt).

| Division | Rows | 1891 persons | 1901 persons |
|---|---:|---:|---:|
| Burdwan | 6 | 7,689,189 | 8,240,076 |
| Presidency | 6 | 8,535,126 | 8,993,028 |
| Rajshahi | 7 | 8,017,402 | 8,495,159 |
| Dacca | 4 | 9,845,296 | 10,793,988 |
| Chittagong | 4 | 4,190,081 | 4,737,731 |
| Patna | 7 | 15,811,604 | 15,514,987 |
| Bhagalpur | 5 | 8,582,069 | 8,726,318 |
| Orissa | 4 | 4,047,402 | 4,343,150 |
| Chota Nagpur | 5 | 4,628,792 | 4,900,429 |
| British Territory | 48 | 71,346,961 | 74,744,866 |

The district transcription matches all nine printed divisional rows and the British Territory control at both dates. Digits unclear in the OCR were cross-read in the same volume's Tables I or III, the Provincial Tables or the Imperial Gazetteer. Puri's 1891 figure of 944,998 also appears in the contemporary Britannica census table. The two-date CSV keeps the sex columns blank. The companion `bengal_districts_sex_1901.csv` gives total males and females in Imperial Table I, printed pp. 2–3, columns 11 and 14. Table II, printed p. 7, columns 10 and 14 cross-check those counts. All 48 rows and all nine divisional subtotals close. The published British Territory control is 37,376,782 males and 37,368,084 females. Join the files on `unit_id,date`. [Provincial Tables](https://ignca.gov.in/Asi_data/30992.pdf), [Imperial Gazetteer IX](https://library.bjp.org/jspui/bitstream/123456789/1876/1/Imperial-Gazetteer-Of-India-Vol-9.pdf), [Imperial Gazetteer XXI](https://www.burmalibrary.org/sites/burmalibrary.org/files/obl/docs21/Imperial_Gazetteer_of_India-Vol.21-1908-tu.pdf), [1891 Puri cross-reference](https://en.wikisource.org/wiki/Page%3A1902_Encyclop%C3%A6dia_Britannica_-_Volume_26_-_AUS-CHI.pdf/244).

## Reconciliation to the opening account

All-India Vol. I-A Table II-A keeps the area enumerated in 1891 and the 1891 administrative divisions. The opening account `raj_bengal_province` uses its population of 71,346,987 in 1891 and 74,744,892 in 1901. Both exceed the local 1901-boundary series by 26. The Bengal Table II notes identify 590 people transferred from Ghazipur in Agra to Shahabad and 616 from Jalpaiguri to Goalpara in Assam. The net of these published transfer entries is −26. The two books report a difference of geography, and any reconciliation to the current opening control has no verified sex or place. A comparison on a common all-India footprint also requires corresponding treatment of Agra and Assam. [All-India Table II-A note, printed p. 9](https://archive.org/details/in.ernet.dli.2015.55924/page/n13/mode/1up), [All-India Table II-A controls, printed p. 10](https://archive.org/details/in.ernet.dli.2015.55924/page/n14/mode/1up).

The two local endpoints interpolate to 74,350,690.427 on 1 January 1900 using the existing elapsed fraction 3231/3655. The existing control rounds to 74,350,716. An opening split can keep the old control and explicitly report the 26-person scope reconciliation. The source supplies a common March 1901 district geography. Its extent and population on the opening date have interpolation and boundary uncertainty. The CSV binds only the existing Calcutta city point, `place:kolkata`.

## Social attributes

Opening literacy uses the district returns for Calcutta and Dacca. The provincial return and the combined other 46 districts are retained as observations. Opening religion uses the comparable British Bengal aggregate with the mixed minor-religion and nonresponse column unknown. District religion is unassigned. [District literacy](bengal_literacy_1901.md) · [Province literacy and religion](bengal_province_social_1901.md).
