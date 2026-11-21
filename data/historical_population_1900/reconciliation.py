"""Parent controls and source conflicts. Dated observations are never balances."""
from collections import defaultdict
from datetime import date
from fractions import Fraction

def comparisons(rows):
    children=defaultdict(list)
    for r in rows:
        if r["parent_id"] and r["kind"] in ("admin","territory","country"):
            children[(r["source_id"],r["date"],r["parent_id"])].append(r)
    out=[]
    for p in rows:
        if p["kind"]=="city" or p["source_id"].startswith("ft_world_"):
            continue
        entries=children.get((p["source_id"],p["date"],p["unit_id"]))
        if not entries:
            continue
        unique=len({c["unit_id"] for c in entries})==len(entries)
        subtotal=sum(c["population_value"] for c in entries) if unique and all(c["population_value"] is not None for c in entries) else None
        diff=subtotal-p["population_value"] if subtotal is not None and p["population_value"] is not None else None
        out.append(dict(parent_id=p["unit_id"],date=p["date"],source_id=p["source_id"],locator=p["locator"],reported=p["population_value"],
                observed_children=[c["record_id"] for c in entries],subtotal=subtotal,children_minus_parent=diff,
                interpretation="alternative values for same child or unknown count" if diff is None else
                "arithmetic closure only; see original enumeration definitions" if diff==0 else
                "incomplete or differently scoped subunits; retain control and observed rows without allocating difference"))
    return out

def asian_estimates(rows):
    # Research-only. Annual Cao dates are represented by a nominal July midpoint.
    # Table 2 for India includes portions retrospectively tabulated under later names.
    grouped=defaultdict(list)
    for r in rows:
        if r["source_id"]=="cao_qing_provincial_reconstruction" or (
                r["source_id"]=="india_statistical_abstract_1905" and r["kind"]!="city" and r["locator"].startswith("Table 2,")
                and r["date"] in {"1891","1901-03-01"}):
            grouped[r["unit_id"]].append(r)
    output=[]
    for key,block in grouped.items():
        if len(block)!=2:continue
        a,b=sorted(block,key=lambda r:r["date"])
        annual=a["source_id"]=="cao_qing_provincial_reconstruction"
        dates=[(r["date"]+"-07-01" if annual else "1891-02-26") if len(r["date"])==4 else r["date"] for r in (a,b)]
        left,right=map(date.fromisoformat,dates)
        f=Fraction((date(1900,1,1)-left).days,(right-left).days)
        if not 0<f<1:continue
        value=round(a["population_value"]+(b["population_value"]-a["population_value"])*f)
        note=("Nominal midyear for year-only endpoints. Source uses retrospective regional names. Cao includes Taiwan within Fujian and excludes Outer Mongolia (Federico–Tena Appendix I, p. 73 nn. 54–55)." if annual else
            "Interpolation of printed columns on the table's reporting geography. Indian Empire includes Aden. Burma enumeration expanded; missing fringe populations and famine timing make this unsuitable as a complete boundary-consistent census.")
        output.append(dict(unit_id=key,name=a["name"],parent_id=a["parent_id"],kind=a["kind"],population_value=value,
            population_lower=None,population_upper=None,date="1900-01-01",source_id=a["source_id"],
            locator=a["locator"]+" / "+b["locator"],source_dates=[a["date"],b["date"]],endpoint_values=[a["population_value"],b["population_value"]],
            interpolation_reference_dates=dates, date_basis="nominal midyear" if annual else "Census of India, General Report 1891, ch. I, opening paragraph; reference night, remote areas differed",
            date_source=None if annual else "https://censusindia.gov.in/nada/index.php/catalog/28412/",fraction=str(f),definition=note,method="linear interpolation of two source totals, rounded once; model error unquantified",
            mapping_status="research_only_original_statistical_scope",quality="derived_estimate_unquantified",region="Asia"))
    return output
