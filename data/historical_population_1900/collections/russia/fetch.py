"""Retrieve numerical extracts of the 1897 census. The last column is both sexes."""
import csv
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.request import urlopen
from lxml import html

BASE = "https://www.demoscope.ru/weekly/ssp/rus_gub_97.php?reg="
HERE = Path(__file__).resolve().parent
def table(number):
    with urlopen(BASE + str(number), timeout=40) as response:
        return html.fromstring(response.read().decode("cp1251"))

def extract(item):
    number, province = item
    page = table(number)
    data = next(t for t in page.xpath("//table") if t.xpath("./tr[td[5]]"))
    rows = []
    for index, tr in enumerate(data.xpath("./tr"), 1):
        cells = [" ".join(c.text_content().split()) for c in tr.xpath("./td")]
        if len(cells) == 5 and any(cells[2:]):
            rows.append([number, province, index, cells[0], *cells[2:]])
    if not rows:
        raise ValueError(f"Missing census table {number}")
    return rows

if __name__ == "__main__":
    options = [(int(o.get("value")), o.text.strip()) for o in table(0).xpath("//select[@name='reg']/option") if o.get("value") != "0"]
    with ThreadPoolExecutor(max_workers=4) as pool:
        blocks = list(pool.map(extract, options))
    with (HERE / "census_facts.csv").open("w", newline="", encoding="utf-8") as out:
        writer = csv.writer(out)
        writer.writerow(["table", "province", "row", "label", "male", "female", "both"])
        for block in blocks:
            writer.writerows(block)
