"""Extract published demographic tables without reducing source categories to modern identities."""
import csv
import re
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.request import urlopen
from lxml import html

HERE=Path(__file__).resolve().parent
BASE="https://www.demoscope.ru/weekly/ssp/"
TABLES={
    "rus_rel_97":("religion","XII","Вероисповедание"),
    "rus_sos_97":("legal_estate","VIII","Сословие"),
    "rus_lan_97":("mother_tongue","XIII","Язык"),
    "rus_age_97":("age_literacy","sex, age and literacy","Возраст"),
}

def read(table, reg):
    with urlopen(f"{BASE}{table}.php?reg={reg}",timeout=45) as r:
        return html.fromstring(r.read().decode("cp1251"))

def options(table):
    doc=read(table,0)
    opts=doc.xpath("//select/option")[1:]
    selected=[]
    for o in opts:
        n=int(o.get("value"))
        label=" ".join((o.text or "").split())
        # Empire and its five regional reporting divisions, plus their urban/rural
        # strata. Province reports begin later and have table-specific identifiers.
        if n<24 or (n>=24 and table!="rus_age_97" and label and "," not in label
                    and "в т.ч." not in label and "в уезд" not in label and "в город" not in label):
            selected.append((table,n,label))
        if n>=24 and ("в городах" in label or "в уездах" in label): break
    return selected

def extract(item):
    table,n,scope=item
    doc=read(table,n)
    target=next(t for t in doc.xpath("//table") if len(t.xpath("./tr"))>8 and TABLES[table][2] in t.xpath("./tr")[0].text_content())
    carry={}
    rows=[]
    for i,tr in enumerate(target.xpath("./tr"),1):
        expanded={}
        nextcarry={}
        for col,(text,left) in carry.items():
            expanded[col]=text
            if left>1: nextcarry[col]=(text,left-1)
        col=0
        for c in tr.xpath("./td|./th"):
            while col in expanded:col+=1
            text=" ".join(c.text_content().split())
            width=int(c.get("colspan","1"));height=int(c.get("rowspan","1"))
            for j in range(col,col+width):
                expanded[j]=text
                if height>1:nextcarry[j]=(text,height-1)
            col+=width
        carry=nextcarry
        cells=[expanded[k] for k in sorted(expanded)]
        if not any(re.fullmatch(r"[0-9]+",s) for s in cells[-3:]): continue
        label_count={"rus_lan_97":3,"rus_age_97":1}.get(table,1)
        labels=cells[:label_count]
        numbers=cells[label_count:]
        if table=="rus_age_97" and len(numbers)!=6 or table!="rus_age_97" and len(numbers)!=3:
            raise ValueError((table,n,i,cells))
        rows.append([table,n,scope,i,*labels,*([""]*(3-len(labels))),*numbers,*([""]*(6-len(numbers)))])
    if not rows:raise ValueError((table,n,scope))
    return rows

if __name__=="__main__":
    work=[item for table in TABLES for item in options(table)]
    with ThreadPoolExecutor(max_workers=4) as pool:blocks=list(pool.map(extract,work))
    with (HERE/"structure.csv").open("w",encoding="utf-8",newline="") as f:
        writer=csv.writer(f)
        writer.writerow(["source_table","region_parameter","published_scope","row","category","subcategory","dialect","male","female","both","literate_male","literate_female","literate_both"])
        for block in blocks: writer.writerows(block)
