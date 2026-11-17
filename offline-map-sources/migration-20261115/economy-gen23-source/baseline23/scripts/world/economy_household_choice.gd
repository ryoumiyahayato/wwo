extends RefCounted
## Opt-in action selection over the ORIGINAL HouseholdTiming projection.
## No wallet, goods, needs, income forecast or settlement is created here.
const Timing=preload("res://scripts/world/economy_household_timing.gd")
static func valid(cfg: Dictionary) -> bool:
	if not cfg.has("household_choice"):return true
	var p: Variant=cfg.household_choice
	return p is Dictionary and EconomySliceConfig._fields(p,["mode","horizon_days","reserve_days","uncertain_days","max_reserve_percent","basis"],[]) and p.mode in ["window","buffer"] and p.horizon_days is int and p.horizon_days>=2 and p.horizon_days<=14 and p.reserve_days is int and p.reserve_days>=1 and p.reserve_days<=3 and p.uncertain_days is int and p.uncertain_days>=0 and p.uncertain_days<=3 and p.max_reserve_percent is int and p.max_reserve_percent>=0 and p.max_reserve_percent<=50 and p.basis=="DEVELOPMENT_ORIGINAL_HOUSEHOLD_TIMING_CHOICE"
static func key(category: String,o: Dictionary) -> String:
	return category+"|"+str(o.seller_site)+"|"+str(o.good)+"|"+str(o.route_id)
static func context(e: RefCounted,actor: String) -> Dictionary:
	var c: Dictionary=Timing._context(e,actor)
	c.horizon=int(e.config.household_choice.horizon_days)
	return c
static func gain(e: RefCounted,actor: String,category: String,o: Dictionary,quantity: int,c: Dictionary,base: Dictionary) -> Dictionary:
	var improved: Dictionary=Timing._project(e,c,"RISK_HOLD",Timing._candidate_batches(e,actor,category,o,quantity))
	var score: float=0.0;var units: int=0;var first: Variant=null
	var categories: Array=e._actor_categories(actor)
	var preference: Array=e._cohort_profile(actor).get("goods_preference",{}).get(category,[])
	var pref: float=1.0
	if not preference.is_empty() and preference.find(o.good)>=0:pref=1.0/(1.0+0.1*preference.find(o.good))
	for cat: String in categories:
		var weight: float=float(categories.size()-categories.find(cat))
		for i: int in base[cat].requirements.size():
			var before: Dictionary=base[cat].requirements[i];var after: Dictionary=improved[cat].requirements[i]
			var benefit: int=maxi(0,int(before.uncovered)-int(after.uncovered))
			if benefit>0:
				units+=benefit
				if first==null:first=before.day
				score+=pref*weight*float(benefit)/maxi(1,int(before.required))/(1.0+0.15*i)
	return {"weighted_service":score,"service_units":units,"need_by_day":first,"eta_guaranteed":false}
static func reserve(e: RefCounted,actor: String,category: String,offers: Array,c: Dictionary,base: Dictionary,cash: int,currency: String) -> Dictionary:
	var p: Dictionary=e.config.household_choice
	var amount: int=0;var uncertain: bool=false;var reasons: Array=[]
	if p.mode!="buffer":return {"amount":0,"reasons":[]}
	for cat: String in e._actor_categories(actor):
		if cat==category or e._spec.categories[cat].mode!="flow":continue
		var gap: int=0
		for row: Dictionary in base[cat].requirements.slice(0,int(p.reserve_days)):gap+=int(row.uncovered)
		if gap<=0:continue
		var best: int=FormalLedgerState.MAX_AMOUNT
		for o: Dictionary in offers:
			if o.denomination!=currency or e._service(o.good,cat)<=0:continue
			if o.reason=="OFFER" and o.price is int:
				var marginal: Dictionary=gain(e,actor,cat,o,1,c,base)
				if marginal.service_units>0:best=mini(best,int(o.price)+int(o.freight_per_unit))
			elif not e._local_quotes.reason(actor,o.seller_site,o.good).is_empty():
				# Only a recently RECEIVED introduction justifies a short uncertainty hold.
				# It expires; no hidden/future quote or wage enters the estimate.
				for receipt: Dictionary in e._receipts.values():
					if receipt.actor==actor and receipt.kind=="supplier" and receipt.candidate==str(o.seller)+"|"+str(o.good)+"|"+str(o.seller_site) and e.day-int(receipt.delivery_day)<=int(p.uncertain_days):uncertain=true
		if best<FormalLedgerState.MAX_AMOUNT:amount+=best*mini(gap,int(p.reserve_days));reasons.append({"category":cat,"basis":"KNOWN_EXECUTABLE_FLOW_OPPORTUNITY","estimated_cash":best*mini(gap,int(p.reserve_days))})
	if uncertain:
		amount=maxi(amount,(cash*int(p.max_reserve_percent)+99)/100)
		reasons.append({"basis":"RECENT_KNOWN_SUPPLIER_QUOTE_WAIT_BOUNDED_NOT_GUARANTEED","expires_after_days":p.uncertain_days})
	return {"amount":mini(amount,cash*int(p.max_reserve_percent)/100),"reasons":reasons}
static func select(e: RefCounted,actor: String,attempted: Dictionary) -> Dictionary:
	var c: Dictionary=context(e,actor);var base: Dictionary=Timing._project(e,c,"RISK_HOLD")
	var offers: Array=e._offers(actor);var candidates: Array=[];var rejected: Array=[]
	var currency: String=str(e._world.ledger_state.account(e._account(actor)).denomination)
	var cash: int=maxi(0,e._world.ledger_state.available_balance(e._account(actor))-e._npc_cash_floor(e._finance_policy(actor),currency))
	var position: Dictionary=e._household_position(actor,true)
	for category: String in e._actor_categories(actor):
		if position[category].get("procurement_authority")=="NATIVE_PERSONAL_ARRANGEMENT":continue
		for original: Dictionary in offers:
			var o: Dictionary=original.duplicate(true);var id: String=key(category,o)
			if attempted.has(id) or e._service(o.good,category)<=0:continue
			var row: Dictionary={"category":category,"good":o.good,"seller_site":o.seller_site,"reason":o.reason}
			if not o.price is int:rejected.append(row);continue
			if o.denomination!=currency:row.reason="UNSUPPORTED_CHOICE_CURRENCY_USE_ORIGINAL_POLICY";rejected.append(row);continue
			var unit: int=int(o.price)+int(o.freight_per_unit)
			if int(o.price)>e._purchase_limit(actor,o.good,currency,int(o.price)):row.reason="OWN_PRICE_LIMIT";rejected.append(row);continue
			var enquiry: bool=false
			if o.reason=="NO_UNCOMMITTED_STOCK" and not attempted.has("enquiry:"+category) and e.config.get("household_purchase_enquiries",false) and e._local_quotes.reason(actor,o.seller_site,o.good).is_empty():
				var path: Dictionary=e._route_for(actor,o.seller,o.route_id,"",o.seller_site)
				if not path.is_empty() and e._route_available(path)>0:o.transport_quantity=1;enquiry=true
			var useful: Dictionary=Timing.candidate_need(e,actor,category,o,mini(1000000,int(position[category].uncovered)))
			var cap: int=mini(8,mini(int(useful.quantity),cash/maxi(1,unit)))
			if cap<=0:
				row.reason="NO_AVAILABLE_CASH" if cash<unit else str(useful.reason);rejected.append(row);continue
			var held: Dictionary=reserve(e,actor,category,offers,c,base,cash,currency)
			var best: Dictionary={}
			var useful_service: bool=false
			for quantity: int in range(1,cap+1):
				var benefit: Dictionary=gain(e,actor,category,o,quantity,c,base)
				if benefit.service_units<=0:continue
				useful_service=true
				var cost: int=unit*quantity
				if cost>cash-int(held.amount):continue
				var value: float=float(benefit.weighted_service)/maxi(1,cost)
				if best.is_empty() or value>float(best.score)+0.000001 or (is_equal_approx(value,float(best.score)) and int(benefit.service_units)>int(best.benefit.service_units)):
					best={"key":id,"category":category,"offer":o,"quantity":quantity,"score":value,"cost":cost,"benefit":benefit,"enquiry":enquiry,"cash_before":cash,"reserve":held}
			if best.is_empty():
				row.merge({"reason":"WAIT_BOUNDED_OTHER_FLOW_PURCHASING_POWER" if useful_service else "NO_USEFUL_SERVICE_IN_FINITE_WINDOW","unit_cash_cost":unit,"available_cash":cash,"reserve":held},true)
				rejected.append(row)
			else:candidates.append(best)
	candidates.sort_custom(func(a: Dictionary,b: Dictionary):return float(a.score)>float(b.score) if not is_equal_approx(float(a.score),float(b.score)) else str(a.key)<str(b.key))
	return {"selected":candidates[0] if not candidates.is_empty() else {},"candidates":candidates,"not_selected":rejected,"mode":e.config.household_choice.mode,"horizon_days":c.horizon,"cash_available":cash,"income_forecast":0,"basis":"OWN_INFORMATION_ORIGINAL_TIMING_MARGINAL_INTEGER_SERVICE_PER_CASH_NOT_UTILITY_TRUTH"}
static func execute(e: RefCounted,actor: String) -> void:
	var attempted: Dictionary={}
	for iteration: int in range(24):
		var plan: Dictionary=select(e,actor,attempted)
		e._household_choice_observations[actor]={"day":e.day,"minute":e._world.game_clock.total_minutes(),"plan":plan.duplicate(true)}
		if plan.selected.is_empty():return
		var s: Dictionary=plan.selected;var o: Dictionary=s.offer
		attempted[s.key]=true
		if s.enquiry:attempted["enquiry:"+str(s.category)]=true
		var payload: Dictionary={"quote_id":o.quote_id,"seller":o.seller,"seller_site":o.seller_site,"good":o.good,"quantity":s.quantity,"denomination":o.denomination,"max_price":e._purchase_limit(actor,o.good,o.denomination,int(o.price)),"path_id":o.route_id,"need_category":s.category,"need_by_day":clampi(int(s.benefit.need_by_day),e.day,e.day+30)}
		var cmd: Dictionary=e._auto_command(actor,"buy",payload,s.key)
		var result: Dictionary=e._accept(actor,cmd,true)
		if e._commands.has(cmd.action_id):
			var detail: Dictionary={"policy":"ORIGINAL_TIMING_CROSS_CATEGORY_CHOICE","mode":plan.mode,"horizon_days":plan.horizon_days,"selected":s.duplicate(true),"available_cash":plan.cash_available,"forecast_income":0,"alternatives":plan.candidates.map(func(row: Dictionary):return {"category":row.category,"good":row.offer.good,"quantity":row.quantity,"cost":row.cost,"score":row.score}),"basis":plan.basis}
			e._commands[cmd.action_id].result["decision"]={"household_choice":detail}
			if s.enquiry:e._commands[cmd.action_id].result.decision["policy"]="FUNDED_KNOWN_SUPPLIER_STOCK_ENQUIRY"
