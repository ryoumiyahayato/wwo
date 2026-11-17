from pathlib import Path
import importlib.util
import sys
work=Path(__file__).resolve().parent
prior=work.with_name("terrain-z7-detail-20261116")
spec=importlib.util.spec_from_file_location("capture",prior/"capture_local.py")
cap=importlib.util.module_from_spec(spec)
spec.loader.exec_module(cap)
cap.STAGE=work
cap.NATIVE=prior/"z7-final-native.exe"
cap.OBS=prior/"z7-observe.exe"
cap.CANDIDATE=prior/"candidate-final"
class Host(cap.Host):
    pass
cap.CANDIDATE=None  # Force the same merged native binary for both packages.
cases={name:cap.SHELVES[name] for name in ("ross-front","ross-shelf","ronne-shelf","amery-shelf")}
cases.update({name:cap.SPECIAL[name] for name in ("greenland","sahara","bosten","mascarene")})
if __name__=="__main__":
    label=sys.argv[1]
    pack={"before-original":cap.BASE,
          "before-pr152":prior/"candidate-final",
          "after-refined":work/"candidate"}.get(label)
    with Host(label,pack,fixed=True) as host:
        for name,position in cases.items():
            row=host.still(name,position)
            terrain=row["state"]["terrain"]
            assert terrain["selected_ready"], terrain
