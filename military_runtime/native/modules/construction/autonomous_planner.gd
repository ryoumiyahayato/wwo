extends RefCounted
## Bounded fictional-game policy, independent of actors and scene-tree side effects.
const INITIAL_DELAY := 12.0
const JOB_COOLDOWN := 35.0
const RETRY_DELAY := 8.0
const MAX_AUTONOMOUS_JOBS := 3
var delay := INITIAL_DELAY
var pending := ""
var jobs := 0
var last_reason := ""
func reset() -> void:
 delay=INITIAL_DELAY
 pending=""
 jobs=0
 last_reason=""
func request(kind: String, active: bool) -> String:
 if not active:return "战斗已经结束，无法联络工程支援"
 if kind not in ["cover","engineering"]:return "只能联络掩护或工程支援"
 if pending!="":return "联络已收到，友军仍在评估；重复请求不会增加任务"
 pending=kind
 return "已联络友军：将根据人员、材料和附近地面自行判断，可能等待或拒绝"
func advance(delta: float, context: Dictionary) -> Dictionary:
 if not bool(context.get("active",false)):
  pending=""
  return {"kind":"inactive"}
 delay=maxf(0.0,delay-maxf(0.0,delta))
 if delay>0.0:return {"kind":"wait"}
 delay=RETRY_DELAY
 if bool(context.get("busy",false)):return _wait("友军正在施工，支援请求等待中")
 if not bool(context.get("worker",false)):return _wait("没有可用的存活友军，暂时无法提供工程支援")
 if int(context.get("materials",0))<1:return _wait("工程材料不足，友军暂缓施工")
 if pending=="" and jobs>=MAX_AUTONOMOUS_JOBS:return {"kind":"wait"}
 var sites: Array=context.get("sites",[])
 var covers: int=int(context.get("cover_count",0))
 var emplacements: int=int(context.get("emplacement_count",0))
 var preference: Array=[]
 if pending=="engineering":preference=["fill","breastwork","mg","dig"]
 elif pending=="cover" or covers==0:preference=["breastwork","dig"]
 elif emplacements==0:preference=["fill","mg"]
 else:preference=["fill"]
 for action in preference:
  if action=="breastwork" and covers>0 and pending!="cover":continue
  if action=="mg" and emplacements>0:continue
  var cost: int=3 if action=="mg" else (2 if action=="breastwork" else 1)
  if int(context.get("materials",0))<cost:continue
  for site in sites:
   if not bool(site.get("safe",false)) or not bool(site.get("reachable",false)):continue
   if not action in site.get("allowed",[]):continue
   return {"kind":"propose","action":action,"position":site.position,"cost":cost}
 return _wait("附近没有合适且可到达的工位，友军暂缓工程支援")
func accepted() -> void:
 jobs+=1
 pending=""
 delay=JOB_COOLDOWN
 last_reason=""
func _wait(reason: String) -> Dictionary:
 var announce: bool=pending!="" and last_reason!=reason
 last_reason=reason
 return {"kind":"wait","message":reason if announce else ""}
