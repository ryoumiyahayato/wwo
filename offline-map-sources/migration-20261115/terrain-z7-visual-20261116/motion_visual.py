import sys
from capture_visual import Host, cap, prior, work
stage=sys.argv[1]
pack={"before":work/"before-with-z6", "after":work/"candidate"}[stage]
lod=work.with_name("terrain-z6-seams-20261116")
with Host(f"motion-{stage}",pack,replay=True) as host:
    compare=cap.data(lod/"z7-jump-auto/alps-corner.json")["request"]
    host.replay("alps-530-970",compare["lon"],compare["lat"],compare["scales"],compare["moves"])
    host.replay("dateline",179.9999,66.09375,[530]*8+([530]*3+[660]*3+[730]*3+[790]*3+[660]*3)*2+[530]*10)
    host.replay("ross-front",177,-78.55,[155]*12+[190]*4+[232]*4+[283]*4+[345]*12+[283]*4+[232]*4+[190]*4+[155]*22)
    host.replay("polar-budget",17,89.89,[146]*10+[178]*4+[218]*4+[266]*12+[218]*4+[178]*4+[146]*15)
    if stage == "after":
        path=cap.data(prior/"after-jump-v2/pan-rotate.json")["request"]
        host.replay("zoom-pan-rotate",path["lon"],path["lat"],path["scales"],path["moves"])
if stage == "after":
    with Host("motion-cold",pack,replay=True) as host:
        host.replay("cold-alps",11.25,46.40625,[1150]*9+[800]*4+[660]*4+[530]*42,prewarm=False)
with Host(f"motion-{stage}-fixed",pack,fixed=True,replay=True) as host:
    host.replay("ross-ice-corner",-166.2583,-84.4318,[280]*32,moves=[[0,0,0]]*8+[[6,.2,1]]*18+[[0,0,0]]*6)
