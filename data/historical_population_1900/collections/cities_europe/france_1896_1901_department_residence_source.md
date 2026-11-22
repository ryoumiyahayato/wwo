# France, 1896 and 1901 departmental urban and rural population

Statistique générale de la France, censuses of 29 March 1896 and 24 March 1901. INSEE's official release supplies [REC_T256.dbf](https://www.insee.fr/fr/statistiques/fichier/2653233/REC_T256.dbf) and the [SGF variable dictionary](https://www.insee.fr/fr/statistiques/fichier/2653233/libelles_var_rec.xls). The [SGF 1936 census retrospective, volume I, pp. 32–33](https://www.bnsp.insee.fr/ark:/12148/bc6p06z2rd0.pdf) records the published residence definition and the Seine exception. The [UN Demographic Yearbook 1952, Table 6](https://unstats.un.org/unsd/demographic-social/products/dyb/dybsets/1952%20DYB.pdf) repeats the 1901 national urban, rural and total legal counts.

The census classed the entire legal population of a commune as urban when more than 2,000 people lived in a concentrated settlement at the communal administrative seat. The entire legal population of other communes was rural. Beginning in 1891 the published split assigned all of the Seine département to urban, including communes below the normal threshold. Retain the historical publication's rule for the department and national totals.

| Census | Urban field | Rural field | Urban | Rural | Legal population |
| --- | --- | --- | ---: | ---: | ---: |
| 1896-03-29 | V43 | V66 | 15,025,812 | 23,491,520 | 38,517,332 |
| 1901-03-24 | V118 | V119 | 15,957,190 | 23,004,755 | 38,961,945 |

The 87 rows are the existing metropolitan opening departments, including Belfort territory, matched by the historical two-digit `V3` code. Filter `V1=1,V4=00,V5=00`. The national row, earlier territorial labels and any overseas totals are excluded. Each pair sums to the corresponding department's independently archived legal population in `france_opening.json`. The assessment is at the statistical department scope, including the parent where opening geography splits the department. The source supplies no distribution to use directly for those smaller constituent units.

For 1896 the repeated V112 entry differs from V43 in Maine-et-Loire (142,838 versus 142,888) and Seine-Inférieure (470,826 versus 470,326). V43 closes to each department control and to the national urban subtotal. For 1901 the repeated V84 for Vosges gives 294,688 rural. V119 gives 294,088, which closes to the Vosges control and the national rural subtotal.

To calculate the modeled 1 January 1900 distribution, use the opening population's daily interpolation weights for both categories, 447/1820 from 1896 and 1373/1820 from 1901. Allocate proportionally within each department using largest remainder to keep its existing integer opening population. This yields 15,728,441 urban, 23,124,307 rural and zero unknown across 38,852,748 people.
