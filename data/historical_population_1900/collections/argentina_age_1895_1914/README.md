# Argentina age and sex at the 1900 opening

The formal opening unit is `argentina_1900`. Its total is 4,624,686 from `ft_argentina` in v29, with 4,338,314–4,911,058 as the existing population sensitivity range. The legacy estimate was 4,700,000. The FT control represents Argentina nationally. It interpolates nominal July population estimates for 1899 and 1900. The 1947 census's own 1900 comparison reports 4.5 million rounded to one decimal in millions. This stage retains the existing FT control.

## Published census observations

The official retrospective in the fourth general census, volume I, national Table 3, printed p. 6, reproduces national age by sex on May 10, 1895 and June 1, 1914. Its footnote attributes differences from the 1914 publication, vol. III pp. 310–313, to summation errors in the older volume. The 1895 age rows sum to 2,088,919 males and 1,865,992 females. The 1914 rows sum to 4,227,023 males and 3,658,214 females. The unknown-age count is 21,637 in 1895 and 6,318 in 1914. The original intervals run from 0–9 to an open 80+ band. [Official census retrospective, Cuadro 3 and Cuadro 5](https://biblioteca.indec.gob.ar/bases/minde/1c1947t1master.pdf)

The age table covers people individually enumerated. The official adjusted counts separately include an estimated 60,000 omissions plus 30,000 Indigenous people in 1895. In 1914 the additions are 118,582 estimated omissions, 18,425 Indigenous people enumerated as groups without personal details, and 20,000 residents of remote areas, mostly in Formosa. The resulting augmented totals are 4,044,911 and 8,042,244. The groups outside individual enumeration have no age or sex marginal in Table 3. [Censos Nacionales, p. XXVIII](https://biblioteca.indec.gob.ar/bases/minde/1c1947t1master.pdf)

The 24 geographic rows from Table 1 on printed p. 1 reproduce the census totals under the publication's historical crosswalk. The 1895 sum is 3,954,911 and the 1914 sum is 7,885,237. Each has one federal capital, 14 provinces and nine national territories. The 1914 census's Los Andes territory appears under Catamarca (378), Jujuy (880) and Salta (1,229) under the later crosswalk. The 16 observatory residents noted in Table 1 refer to 1947. The national age model uses these census tables. The separate regional allocation uses the 1901 estimate for its later geographic weights. [Cuadro 1 and its notes](https://biblioteca.indec.gob.ar/bases/minde/1c1947t1master.pdf)

## Opening allocation at January 1, 1900

1. Set the late endpoint weight to 1,697/6,961 calendar days, about 24.38%. Keep the 4,624,686 opening control.
2. Interpolate the endpoint shares outside individual enumeration, 90,000 / 4,044,911 and 157,007 / 8,042,244, using that weight. Multiply by the opening total and round to the nearest person. The resulting 99,825 people have unknown age and sex. This is a coverage estimate.
3. For each age × sex cell, including age unknown, divide each original count by that year's individually enumerated total. Interpolate the two shares using the same weight. Multiply by the remaining 4,524,861 people. Take integer floors and assign the remainder by descending fractional part. Use source age-band order and the sex key to break ties. The modeled age rows total 4,505,257 with age and sex, and 19,604 with sex and age unknown. Total unknown age is 119,429. The known-sex controls are 2,398,654 males and 2,126,207 females.
4. The opening keeps the 99,825 coverage estimate unclassified. The national age allocation retains the separate age-unknown sex cells.

The selection of two shares is a time interpolation, including for incomplete enumeration. The endpoint coverage fractions alone imply 90,287–102,900 people of unknown age and sex under the same FT total. This is a scenario range for the coverage assumption. Neither the range nor the census shares measure departures from a linear age trend.

## Migration and timing

The official foreign category rose from 1,006,838 people (25.5%) to 2,391,171 (30.3%) under the publication's terms. It included 638,081 males and 368,757 females in 1895, and 1,507,028 males and 884,143 females in 1914. The 1895 census commentary identified an adult concentration among foreigners. The later retrospective reports a net migration balance of 319,882 during 1891–1900 and 1,120,179 during 1901–1910. The pace and age composition of migration can change the modeled adult sex balance between censuses. Among persons aged 20–59, the male share increased from 55.26% to 56.53%. Capital Federal and Buenos Aires province each use local ages. The other accounts use the national residual shares. Nationality remains a separate reference. [1895 original, vol. II, age section](https://biblioteca.indec.gob.ar/bases/minde/1c1895t2.pdf) · [1947 retrospective, Cuadros 24–25](https://biblioteca.indec.gob.ar/bases/minde/1c1947t1master.pdf)

## Files

- `age_sex.csv` reproduces the published age controls and bands. `panels.json` identifies both observations.
- `census_controls.csv` records population, sex and coverage controls. Foreign totals in this file are auxiliary migration context from Table 25.
- `census_geography.csv` records enumerated historical areas under the retrospective geography. These rows are geographic reference.
