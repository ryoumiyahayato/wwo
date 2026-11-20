extends RefCounted
## Finite opt-in regional content, never loaded by ordinary world creation.
const GOODS: Array[String] = ["grain","flour","bread","fiber","cloth","clothes","coal","iron_ore","steel","tools"]
const PARIS = "place:paris"
const LYON = "place:lyon"

static func stock(values: Dictionary = {}) -> Dictionary:
	var s: Dictionary=EconomySliceConfig.zero_stock(GOODS);s.merge(values,true);return s

static func process(output: Dictionary, rejects: Dictionary = {}, unavailable: String = "") -> Dictionary:
	var gross: Dictionary=output.duplicate(true);var waste: Dictionary={}
	for g: String in output:
		waste[g]=int(rejects.get(g,0));gross[g]=int(output[g])+int(waste[g])
	return {"format":"production_process_v1","technology_id":"technology:network:initial","batch_unit":"development_batch","source":{"id":"production_network_opening.gd:v1","basis":"EXPLICIT_DEVELOPMENT_ESTIMATE_NOT_HISTORICAL_RATE","estimated":true,"hours_unit":"person_hour","capacity_unit":"capacity_unit_per_eligible_day"},"gross_outputs":gross,"rejects":waste,"first_day":1,"cycle_days":1,"max_batches_per_cycle":8,"lifetime_batch_limit":10000,"constraints":[] if unavailable.is_empty() else [{"kind":unavailable,"availability":"UNAVAILABLE","source":"No admitted natural-resource or role executor in this experiment","unit":"unconfigured"}]}

static func configuration(condition: String) -> Dictionary:
	var cfg: Dictionary={"format":"R2","case_id":"PRODUCTION_NETWORK_V1_"+condition,"host_personal_accounts":true,"actors":[],"firms":[],"jobs":[],"information":[],"production_enabled":true,"player_choice":"substitute","stock_horizon":2,"route":{"id":"edge:network:paris","place_id":PARIS,"capacity":40,"delay":1,"basis":"SYNTHETIC"},"goods":[],"need_categories":[{"id":"food","mode":"flow","priority":0},{"id":"clothing","mode":"durable","priority":1},{"id":"household","mode":"durable","priority":2}],"firm_operations":[],"carriers":[{"id":"carrier:network","place_id":PARIS,"account_id":"account:network:carrier","cash":10}],"routes":[],"transport_nodes":[{"place_id":PARIS,"capacity":40},{"place_id":LYON,"capacity":40}],"cost_accounting":{"freight_treatment":"BUYER_ACQUISITION","joint_allocations":[],"npc_policies":[],"basis":"EXPLICIT_DEVELOPMENT_COST_POLICY"}}
	for g: String in GOODS:
		cfg.goods.append({"id":g,"needs":{"food":1} if g=="bread" else {"clothing":1} if g in ["cloth","clothes"] else {"household":1} if g=="tools" else {},"unit_id":"kg" if g in ["grain","flour","fiber","coal","iron_ore","steel"] else "m" if g=="cloth" else "piece","unit_name_zh":"千克" if g in ["grain","flour","fiber","coal","iron_ore","steel"] else "米" if g=="cloth" else "件"})
	# Four finite primary suppliers and sixteen separate processors/traders.
	var definitions: Array=[
		["grain",LYON,{"grain":160},{"grain":1},{},"LAND"],
		["fiber",LYON,{"fiber":120},{"fiber":2},{},"BIOLOGICAL_CYCLE"],
		["coal",LYON,{"coal":120},{"coal":2},{},"MINERAL_DEPOSIT"],
		["ore",LYON,{"iron_ore":120},{"iron_ore":2},{},"MINERAL_DEPOSIT"]]
	for i: int in range(1,3):
		definitions.append_array([
			["mill"+str(i),PARIS,{}, {"flour":4},{"flour":2,"in:grain":3},""],
			["bakery"+str(i),PARIS,{}, {"bread":4},{"bread":2,"in:flour":1},""],
			["weave"+str(i),PARIS,{}, {"cloth":5},{"cloth":2,"in:fiber":2},""],
			["steel"+str(i),LYON,{}, {"steel":8},{"steel":2,"in:coal":2,"in:iron_ore":3},""],
			["tools"+str(i),PARIS,{}, {"tools":12},{"tools":2,"in:steel":2},""],
			["tailor"+str(i),PARIS,{}, {"clothes":8},{"clothes":2,"in:cloth":2},""],
			["wholesale"+str(i),PARIS,{}, {"bread":5,"clothes":9,"tools":13},{},""],
			["retail"+str(i),PARIS,{}, {"bread":6,"clothes":10,"tools":14},{},""]])
	if condition=="scale10": definitions=definitions.slice(0,10)
	if condition=="scale30":
		for i: int in range(3,13): definitions.append(["retail"+str(i),PARIS,{}, {"bread":6,"clothes":10,"tools":14},{},""])
	var present: Dictionary={}
	for d: Array in definitions:present[d[0]]=true
	var worker_index: int=0
	for d: Array in definitions:
		var name: String=d[0];var firm: String="firm:network:"+name;var site: String="site:network:"+name
		var outputs: Dictionary={};var inputs: Dictionary={}
		for g: String in d[4]:
			if g.begins_with("in:"):inputs[g.trim_prefix("in:")]=d[4][g]
			else:outputs[g]=d[4][g]
		# Primary extraction is explicitly unavailable, while finite opening lots can be sold.
		if not str(d[5]).is_empty():
			for g: String in d[3]:outputs[g]=1
		var activities: Array=[]
		var capacity: int=2 if not outputs.is_empty() else 0
		var targets: Dictionary={}
		for g: String in d[3]:targets[g]=4 if str(d[5]).is_empty() else 0
		var rejects: Dictionary={}
		if name.begins_with("mill"):rejects={"flour":1}
		if name=="mill1":
			if condition in ["equipment","fixed_equipment"]: capacity=4
			if condition in ["materials_efficiency","fixed_materials","same_output_materials"]:inputs.grain=2;rejects.flour=0
			if condition=="fixed_rejects":outputs.flour=3;rejects.flour=0
		if not outputs.is_empty():
			var a: Dictionary={"id":"activity:network:"+name,"place_id":d[1],"outputs":outputs,"materials":stock(inputs),"hours":2,"capacity_units":1,"enabled":true,"basis":"DEVELOPMENT_CONFIGURATION","process":process(outputs,rejects,d[5])}
			if name=="mill1":
				if condition in ["productivity","fixed_productivity","same_output_productivity","technology_no_materials","technology_low_demand"]:a.hours=1;a.process.technology_id="technology:network:half_labor"
				if condition=="process_cycle":a.process.cycle_days=3;a.process.max_batches_per_cycle=1;a.process.lifetime_batch_limit=2
				if condition=="unavailable":a.process.constraints=[{"kind":"SPECIFIC_EQUIPMENT","availability":"UNAVAILABLE","source":"No installed matching machine","unit":"machine"}]
			if name.begins_with("bakery"):a.process.technology_id="technology:network:dry_ration_approximation"
			activities.append(a)
		var opening: Dictionary=stock(d[2])
		if condition in ["materials","technology_no_materials"] and name=="grain":opening.grain=0
		var cash: int=100 if condition!="cash" else 2
		var prices: Dictionary=d[3].duplicate(true)
		if condition=="upstream_price" and name=="grain":prices.grain=3
		if condition.begins_with("paid_price_") and name.begins_with("mill"):prices.flour=5
		if condition=="paid_price_high" and name=="grain":prices.grain=2
		if condition.begins_with("same_output_") and name=="mill1":
			opening.grain=12;targets.flour=4;capacity=4
		if condition in ["capacity_base","capacity_high"] and name=="mill1":
			opening.grain=12;targets.flour=8;capacity=1 if condition=="capacity_base" else 2
		if condition.begins_with("fixed_") and name=="mill1":
			opening.grain=12;targets.flour=8;capacity=4 if condition!="fixed_equipment" else 8
		var suppliers: Array=[]
		var known_names: Array=[]
		if name.begins_with("mill"):known_names=["grain"]
		elif name.begins_with("bakery"):known_names=["mill1","mill2"]
		elif name.begins_with("weave"):known_names=["fiber"]
		elif name.begins_with("steel"):known_names=["coal","ore"]
		elif name.begins_with("tools"):known_names=["steel1","steel2"]
		elif name.begins_with("tailor"):known_names=["weave1","weave2"]
		elif name.begins_with("wholesale"):known_names=["bakery1","bakery2","tailor1","tailor2","tools1","tools2"]
		elif name.begins_with("retail"):known_names=["wholesale1","wholesale2"]
		for other: Array in definitions:
			if other[0] not in known_names:continue
			for g: String in other[3]:
				var candidate: String="firm:network:"+other[0]+"|"+g+"|site:network:"+other[0]
				suppliers.append(candidate);cfg.information.append({"actor":site,"kind":"supplier","candidate":candidate,"delivery_day":0})
		var row: Dictionary={"id":site,"place_id":d[1],"roles":["production","storage","sales"],"stock":opening,"capacity":capacity,"targets":stock(targets),"prices":prices,"activities":activities,"suppliers":suppliers,"enabled":true,"production_enabled":true,"accepting_business":true,"basis":"DEVELOPMENT_CONFIGURATION","coordination_delay":0}
		cfg.firms.append({"id":firm,"place_id":d[1],"account_id":"account:network:"+name,"cash":cash,"sites":[row]})
		cfg.firm_operations.append({"firm":firm,"planning_horizon":1 if condition.begins_with("fixed_") or condition.begins_with("capacity_") or condition.begins_with("same_output_") else 3,"buffer_days":1,"demand_window":7,"manage_jobs":false})
		if not inputs.is_empty():
			var worker: String="cohort:network:"+name;var job: String="job:network:"+name
			var members: int=1
			cfg.actors.append({"id":worker,"kind":"cohort","control":"automatic","members":members,"account_id":"account:worker:"+name,"cash":0 if condition in ["demand","technology_low_demand","cash"] else 30,"stock":stock(),"skill":1,"daily_need":0 if condition in ["demand","technology_low_demand"] else 1,"needs":{"food":0,"clothing":0,"household":0} if condition in ["demand","technology_low_demand"] else {"food":1,"clothing":1,"household":1},"population_start":worker_index,"place_id":d[1]})
			worker_index+=1
			var wage: int=3 if condition=="wage" else 1
			cfg.jobs.append({"id":job,"employer":firm,"site_id":site,"positions":0 if condition=="labor" and name.begins_with("mill") else 1,"skill":1,"hours":4,"place":d[1],"wage_per_hour":wage,"wage_delay":3 if condition=="cash" else 1})
			cfg.information.append({"actor":worker,"kind":"job","candidate":job,"delivery_day":0})
			if condition not in ["demand","technology_low_demand"]:
				for n: String in ["retail1","retail2"] if present.has("retail1") else ["bakery1","tailor1","tools1"]:
					for other: Array in definitions:
						if other[0]!=n:continue
						for g: String in other[3]:cfg.information.append({"actor":worker,"kind":"supplier","candidate":"firm:network:"+n+"|"+g+"|site:network:"+n,"delivery_day":0})
	# Legal player account is reused; it is outside this finite demand sample.
	cfg.actors.append({"id":WorldBootstrap.DEFAULT_FORMAL_PERSON_ID,"kind":"named","control":"player","members":1,"account_id":FormalPersonalEconomyState.personal_account_id(WorldBootstrap.DEFAULT_FORMAL_PERSON_ID),"cash":0,"stock":stock(),"skill":1,"daily_need":0,"needs":{"food":0},"population_start":0,"place_id":PARIS})
	var known: Array=[]
	for f: Dictionary in cfg.firms:known.append(f.id)
	for a: Dictionary in cfg.actors:known.append(a.id)
	for endpoints: Array in [[PARIS,LYON],[LYON,PARIS],[LYON,LYON]]:
		cfg.routes.append({"id":"edge:network:"+endpoints[0].trim_prefix("place:")+":"+endpoints[1].trim_prefix("place:"),"from_place_id":endpoints[0],"to_place_id":endpoints[1],"capacity":20,"delay":1,"carrier":"carrier:network","freight_per_unit":1,"known_to":known.duplicate(),"basis":"SYNTHETIC","capacity_manager":"firm:network:mill1"})
	return cfg
