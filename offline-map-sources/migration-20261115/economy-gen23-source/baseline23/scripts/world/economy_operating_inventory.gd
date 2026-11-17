extends RefCounted
## Own delivery experience changes only an optional procurement buffer.
## No inventory, cash or preference history is held here.
static func valid(settings: Dictionary) -> bool:
	if not settings.has("operating_inventory"):return true
	var p: Variant=settings.operating_inventory
	if not p is Dictionary or not EconomySliceConfig._fields(p,["enabled","window_days","idle_days","trial_units","sales_cover_days","cash_share_percent","basis"],["company_cash_window","stable_holding_age","durable_trial_limit","enquiry_trial_by_buyer","enquiry_response","enquiry_response_goods","turnover_adaptation"]):return false
	if p.has("enquiry_response") and p.enquiry_response not in ["deadline","bounded"]:return false
	if p.has("enquiry_response_goods"):
		if not p.has("enquiry_response") or not p.enquiry_response_goods is Array or p.enquiry_response_goods.is_empty():return false
		for good: Variant in p.enquiry_response_goods:
			if not good is String or not settings.goods.any(func(row: Dictionary):return row.id==good):return false
	for flag: String in ["company_cash_window","stable_holding_age","durable_trial_limit","enquiry_trial_by_buyer","turnover_adaptation"]:
		if p.has(flag) and not p[flag] is bool:return false
	if not p.enabled is bool or p.basis!="DEVELOPMENT_OWN_SALES_INVENTORY_POLICY":return false
	for key: String in ["window_days","idle_days","trial_units","sales_cover_days","cash_share_percent"]:
		if not FormalLedgerState.valid_amount(p[key]) or p[key]<1:return false
	return p.window_days<=30 and p.idle_days<=90 and p.trial_units<=10 and p.sales_cover_days<=30 and p.cash_share_percent<=100

## Only facts received by THIS selling site; no household cash/stock projection.
## A funded refusal is not a reservation, and an ETA is only a lower bound.
static func market_signal(e: RefCounted,site: String,good: String,stock_arrival: Variant=null) -> Dictionary:
	var latest: Dictionary={};var history: Dictionary={};var rows: Array=[]
	var window: int=int(e.config.get("operating_inventory",{}).get("window_days",e._operations_policy(site).demand_window))
	for request: Dictionary in e._request_pressure_records(site,good):
		if int(request.day)<e.day-window+1 and int(request.need_by_day)<e.day:continue
		var prior: Dictionary=latest.get(request.buyer,{})
		if prior.is_empty() or int(e._commands[request.action_id].envelope.command.minute)>=int(e._commands[prior.action_id].envelope.command.minute):latest[request.buyer]=request
		if e._request_supply_pressure(request)>0 and int(request.need_by_day)<e.day:history[request.buyer]=true
	var active: int=0;var timely: int=0;var late: int=0;var unknown: int=0
	for request: Dictionary in latest.values():
		var quantity: int=e._request_supply_pressure(request)
		if quantity<=0:continue
		var expires: int=int(request.need_by_day)
		var delivery: Variant=null
		if stock_arrival!=null:
			var payload: Dictionary=e._commands[request.action_id].envelope.command.payload
			var path: String=str(payload.get("path_id",""))
			if path=="onsite:"+site:delivery=int(stock_arrival)
			else:
				var route: Dictionary=e._route_for(str(request.buyer),e._owner(site),path,str(payload.get("buyer_site","")),site)
				if not route.is_empty() and e._route_available(route)>0:
					delivery=int(stock_arrival)+e._travel_days(e._locked_legs(route,e._sale_currency(e._owner(site))))
		var state: String="EXPIRED_HISTORY" if expires<e.day else "CURRENT_FUNDED_AT_ATTEMPT_NOT_RESERVED"
		if expires>=e.day:
			active+=quantity
			if delivery==null:unknown+=quantity
			elif int(delivery)<=expires:timely+=quantity
			else:late+=quantity;state="EARLIEST_CUSTOMER_RECEIPT_MISSES_REQUEST"
		rows.append({"buyer":request.buyer,"action_id":request.action_id,"observed_day":request.day,"need_by_day":expires,"quantity":quantity,"state":state,"earliest_customer_receipt_day":delivery,"eta_guaranteed":false,"money_reserved":false})
	var contracted: int=0
	for id: String in e._active_sales_by_key.get(site+"|"+good,{}):
		var order: Dictionary=e._orders[id]
		if order.kind=="SALE" and order.seller_site==site and order.good==good:contracted+=int(order.pending)+int(order.transit)
	return {"basis":"OWN_RECEIVED_ATTEMPTS_NOT_COMMITTED_DEMAND","day":e.day,"stock_arrival_lower_bound":stock_arrival,"active_funded_at_attempt":active,"timely_quantity":timely,"late_quantity":late,"unknown_time_quantity":unknown,"expired_buyers":history.size(),"contracted_pending_quantity":contracted,"attempts":rows,"buyer_money_may_change":true,"scope":"NO_BUYER_BALANCE_OR_PRIVATE_PLAN"}

## Native CostAllocation supplies cost provenance. Opening goods remain unknown.
## This value cannot pay, reserve, write down, or transfer any inventory.
static func stock_cash(e: RefCounted,site: String,good: String) -> Dictionary:
	var known: Dictionary={};var unknown: int=0;var quantity: int=0;var oldest: int=0
	for id: String in e._lots._by_location.get("SITE|"+site+"#"+good,{}):
		var portion: Dictionary=e._lots.portions[id]
		if portion.owner!=e._owner(site) or not str(portion.reserved_for).is_empty() or int(portion.remaining)<=0:continue
		quantity+=int(portion.remaining)
		var ancestor: Dictionary=portion
		while not str(ancestor.parent_portion_id).is_empty():
			var parent: Dictionary=e._lots.portions[ancestor.parent_portion_id]
			if parent.owner!=portion.owner:break
			ancestor=parent
		oldest=maxi(oldest,e.day-int(ancestor.opened_minute)/1440)
		if not e._costs.enabled:unknown+=int(portion.remaining);continue
		var portions: Array[Dictionary]=[{"portion_id":id,"source_id":portion.source_id,"quantity":portion.remaining}]
		var cost: Dictionary=e._costs.cost_of(e._costs.ranges(portions))
		for currency: String in cost.amounts:known[currency]=int(known.get(currency,0))+int(cost.amounts[currency])
		if not cost.unknown.is_empty():unknown+=int(portion.remaining)
	return {"quantity":quantity,"known_cost":known,"unknown_cost_quantity":unknown,"oldest_own_holding_days":oldest,"basis":"ORIGINAL_FREE_PORTIONS_NATIVE_COST_NOT_CURRENT_PRICE_OR_CASH_ACCOUNT"}

static func experience(e: RefCounted,site: String,good: String) -> Dictionary:
	var p: Dictionary=e.config.operating_inventory;var start: int=maxi(0,e.day-int(p.window_days)+1)
	var days: Dictionary={};var buyers: Dictionary={};var deliveries: Array=[];var total: int=0;var last: Variant=null
	var revenue: Dictionary={};var contribution: Dictionary={};var cash_days: int=0;var known_cycle_units: int=0
	# Existing native cost index: this site's finite date window, not regional orders.
	for date: int in range(start,e.day+1):
		for id: String in e._costs._sales_days.get(site,{}).get(date,[]):
			var receipt: Dictionary=e._delivery_receipts[id];var order: Dictionary=e._orders[receipt.order_id]
			if order.good!=good:continue
			days[date]=true;last=date;total+=int(receipt.quantity)
			if not buyers.has(order.buyer):buyers[order.buyer]={}
			buyers[order.buyer][date]=true
			var currency: String=order.denomination;var paid: int=int(order.price)*int(receipt.quantity)
			revenue[currency]=int(revenue.get(currency,0))+paid
			var cost: Dictionary=e._costs.cost_of(e._costs.sales[id])
			if cost.unknown.is_empty() and (cost.amounts.is_empty() or (cost.amounts.size()==1 and cost.amounts.has(currency))):contribution[currency]=int(contribution.get(currency,0))+paid-int(cost.amounts.get(currency,0))
			for part: Dictionary in e._costs.sales[id]:
				var basis: Dictionary=e._costs.bases[part.basis]
				if basis.kind!="ACQUISITION" or not basis.refs.has("receipt"):continue
				var acquired: Dictionary=e._orders[e._delivery_receipts[basis.refs.receipt].order_id]
				if acquired.kind!="SALE" or acquired.buyer!=e._owner(site):continue
				cash_days+=int(part.quantity)*maxi(1,date-int(acquired.accepted_day));known_cycle_units+=int(part.quantity)
			deliveries.append({"receipt_id":id,"order_id":order.id,"buyer":order.buyer,"day":date,"quantity":receipt.quantity,"price":order.price})
	var repeated: int=0
	for dates: Dictionary in buyers.values():
		if dates.size()>1:repeated+=1
	var episodes: Dictionary={};var expired: int=0;var fulfilled: int=0
	for row: Dictionary in e._request_pressure_records(site,good):
		if int(row.day)<start or e._request_supply_pressure(row)<=0:continue
		var identity: String=str(row.buyer)+"|"+str(row.need_by_day)
		if episodes.has(identity):continue
		episodes[identity]=true
		if int(row.need_by_day)>=e.day:continue
		var matched: bool=false
		for sale: Dictionary in deliveries:
			if sale.buyer==row.buyer and int(sale.day)>=int(row.day) and int(sale.day)<=int(row.need_by_day):matched=true;break
		if matched:fulfilled+=1
		else:expired+=1
	return {"window_start_day":start,"window_days":p.window_days,"sale_days":days.size(),"sold_quantity":total,"distinct_buyers":buyers.size(),"repeat_buyers":repeated,"last_sale_day":last,"sales_cash_received":revenue,"known_direct_contribution":contribution,"known_cycle_units":known_cycle_units,"observed_cash_cycle_days":float(cash_days)/known_cycle_units if known_cycle_units>0 else null,"observed_need_episodes":episodes.size(),"expired_without_own_timely_sale":expired,"own_timely_sale_after_attempt":fulfilled,"stock_cash":stock_cash(e,site,good),"recent_deliveries":deliveries.slice(-4),"basis":"OWN_INVOICES_AND_NATIVE_COSTS_NO_PRIVATE_HOUSEHOLD_FORECAST"}

static func optional_capital(e: RefCounted,firm: String,currency: String) -> Dictionary:
	var stock_cost: int=0;var held: int=0;var unknown: int=0
	for site: String in e._site_ids():
		if e._owner(site)!=firm or e._retail.has_site(site):continue
		var row: Dictionary=e._spec.sites[site]
		for good: String in row.targets:
			if int(row.targets[good])<=0 or not row.prices.has(good):continue
			var recipe: bool=false
			for activity: Dictionary in row.activities:
				if int(activity.outputs.get(good,0))+int(activity.materials.get(good,0))>0:recipe=true;break
			if recipe:continue
			var stock: Dictionary=stock_cash(e,site,good)
			stock_cost+=int(stock.known_cost.get(currency,0));unknown+=int(stock.unknown_cost_quantity)
	for id: String in e._active_by_buyer.get(firm,[]):
		var order: Dictionary=e._orders[id]
		var decision: Dictionary=e._commands[order.action_id].result.get("decision",{}).get("replenishment",{})
		if decision.is_empty() or int(decision.get("protected_quantity",0))>0 or order.denomination!=currency:continue
		var reservation: Dictionary=e._world.ledger_state._reservations.get(id,{})
		if reservation.get("account_id")==e._account(firm,currency):held+=int(reservation.amount)
	var cash: Dictionary=e._procurement_cash_position(firm,currency)
	var spendable: int=int(cash.spendable)
	# A cash -> reservation -> acquired stock transition must not shrink the
	# concentration base again. Only optional reserves are added back here;
	# protected-purpose reserves and original due protection remain excluded.
	# Book cost measures concentration, never spendable cash or resale proceeds.
	var occupied: int=stock_cost+held
	var capital_base: int=spendable+occupied
	var ceiling: int=capital_base*int(e.config.operating_inventory.cash_share_percent)/100
	var room: int=mini(spendable,maxi(0,ceiling-occupied))
	return {"known_free_resale_cost":stock_cost,"incoming_original_reservations":held,"unknown_cost_quantity":unknown,"occupied_optional_capital":occupied,"concentration_base":capital_base,"exposure_ceiling":ceiling,"risk_room":room,"spendable_now":spendable,"cash_position":cash,"basis":"OPTIONAL_CAPITAL_CONCENTRATION_SEPARATE_FROM_CASH_V2"}

static func turnover_response(e: RefCounted,site: String,good: String,offer: Dictionary,need: Dictionary,batch_size: int) -> Dictionary:
	var p: Dictionary=e.config.get("operating_inventory",{})
	if not p.get("turnover_adaptation",false) or need.get("inventory_adaptation",{}).is_empty():return {}
	var own: Dictionary=experience(e,site,good)
	var market: Dictionary=market_signal(e,site,good,offer.get("observed_arrival_day",e._input_offer_arrival(offer)))
	var unit: int=int(offer.price)+int(offer.freight_per_unit)
	var spread: int=e._price(site,good)-unit
	var durable: bool=bool(need.inventory_adaptation.durable_only)
	var target: int=0;var strength: int=0;var why: String="WAIT_NEW_ACTIONABLE_EVIDENCE"
	if int(market.timely_quantity)>0:
		target=mini(batch_size,int(market.timely_quantity));strength=3;why="CURRENT_TIMELY_ATTEMPT_NOT_FUTURE_CONTRACT"
	elif not durable and int(own.sale_days)>=2:
		target=(int(own.sold_quantity)*int(p.sales_cover_days)+int(p.window_days)-1)/int(p.window_days);strength=2;why="REPEATED_FLOW_DELIVERIES_FINITE_COVER"
	elif spread>0 and int(own.stock_cash.oldest_own_holding_days)<int(p.idle_days) and int(own.expired_without_own_timely_sale)==0:
		target=int(p.trial_units);strength=1;why="POSITIVE_SPREAD_FINITE_CAPITAL_TRIAL"
	elif int(own.sale_days)==1 and spread<=0:why="SINGLE_ZERO_SPREAD_SALE_WAIT_NOT_STABLE_TURNOVER"
	if durable:target=mini(target,int(p.trial_units))
	target=mini(target,int(need.inventory_adaptation.configured_buffer))
	var missing: int=maxi(0,target-int(need.on_hand)-int(need.get("accepted_responsibility",need.incoming)))
	var capital: Dictionary=optional_capital(e,e._owner(site),offer.denomination)
	var room: int=mini(missing,int(capital.risk_room)/maxi(1,unit))
	if room<missing:why="OPTIONAL_CAPITAL_OCCUPIED_OR_CASH_DUE"
	var duration: float=float(own.observed_cash_cycle_days) if own.observed_cash_cycle_days!=null else float(p.window_days)+maxi(0,int(need.get("known_lead_days",0)))
	var score: float=float(strength)*1000.0/(maxi(1,unit)*maxf(1.0,duration))
	return {"reason":why,"optional_quantity_limit":room,"desired_optional_stock":target,"landed_unit_cost":unit,"quoted_gross_spread":spread,"strength":strength,"opportunity_score":score,"currency":offer.denomination,"capital":capital,"experience":own,"signal":market,"basis":"LIMITED_OWN_EXPERIENCE_AND_CAPITAL_NOT_PROFIT_MAXIMIZER_OR_GUARANTEED_DEMAND"}

static func arrival_response(e: RefCounted,site: String,good: String,arrival: Variant,need: Dictionary,batch_size: int) -> Dictionary:
	var p: Dictionary=e.config.get("operating_inventory",{})
	if not p.has("enquiry_response") or good not in p.get("enquiry_response_goods",[good]) or need.get("inventory_adaptation",{}).is_empty():return {}
	var adaptation: Dictionary=need.inventory_adaptation
	var market: Dictionary=market_signal(e,site,good,arrival)
	var sales_target: int=mini(int(adaptation.configured_buffer),(int(adaptation.own_delivered_sales)*int(p.sales_cover_days)+int(p.window_days)-1)/int(p.window_days))
	var independent: int=sales_target
	var idle: bool=adaptation.oldest_own_holding_age_days!=null and int(adaptation.oldest_own_holding_age_days)>=int(p.idle_days)
	var trial: bool=p.enquiry_response=="bounded" and not idle and int(adaptation.own_delivered_sales)==0 and adaptation.reason not in ["IDLE_OWN_STOCK_WAIT_NO_RECENT_SALES","DURABLE_TRIAL_CAPITAL_WITHOUT_OWN_SALES"]
	if trial:independent=mini(int(adaptation.configured_buffer),int(p.trial_units))
	# Classify only the original first available transport batch as timely.
	# Later partial dispatches are not silently given the first batch's ETA.
	var desired: int=maxi(independent,mini(batch_size,mini(int(adaptation.configured_buffer),int(market.timely_quantity))))
	if adaptation.durable_only:desired=mini(desired,int(p.trial_units))
	var remaining: int=maxi(0,desired-int(need.on_hand)-int(need.get("accepted_responsibility",need.incoming)))
	return {"mode":p.enquiry_response,"signal":market,"first_batch_quantity_limit":batch_size,"own_delivered_sales_target":sales_target,"independent_risk_trial":trial,"desired_optional_stock":desired,"new_optional_quantity_limit":remaining,"reason":"TIMELY_ATTEMPT_STILL_NOT_GUARANTEED_SALE" if mini(batch_size,int(market.timely_quantity))>independent else "OWN_SALES_CYCLE_ESTIMATE_NOT_BACKLOG" if sales_target>0 else "FINITE_TRIAL_AT_MERCHANT_RISK" if trial else "NO_TIMELY_ATTEMPT_OR_OWN_SALES_WAIT","basis":"ORIGINAL_ORDERS_LOTS_ARRIVAL_LOWER_BOUND_NOT_SECOND_DEMAND_LEDGER"}

static func observe(e: RefCounted,site: String,good: String) -> Dictionary:
	var p: Dictionary=e.config.get("operating_inventory",{})
	if not p.get("enabled",false) or not e._npc_timing_adoption(e._owner(site)):return {}
	var row: Dictionary=e._spec.sites[site]
	var configured: int=int(row.targets[good])
	if configured<=0 or not row.prices.has(good) or "sales" not in row.roles or e._retail.has_site(site):return {}
	for activity: Dictionary in row.activities:
		if int(activity.outputs.get(good,0))>0:return {} # Existing production planning keeps its own purpose.
	var sold: int=0;var receipts: int=0
	var start: int=maxi(0,e.day-int(p.window_days)+1)
	for date: Variant in e._delivery_days.get(site+"|"+good,{}):
		if int(date)>=start and int(date)<=e.day:
			var fact: Dictionary=e._delivery_days[site+"|"+good][date]
			sold+=int(fact.quantity);receipts+=int(fact.count)
	var oldest: Variant=null
	var source_age: Variant=null
	var holding_age: Variant=null
	for id: String in e._lots._by_location.get("SITE|"+site+"#"+good,{}):
		var portion: Dictionary=e._lots.portions[id]
		if portion.owner!=e._owner(site) or not str(portion.reserved_for).is_empty() or int(portion.remaining)<=0:continue
		var age: int=maxi(0,e.day-int(portion.opened_minute)/1440)
		oldest=age if oldest==null else maxi(int(oldest),age)
		var formed: int=int(e._lots.sources[portion.source_id].formed_minute)
		var stable_age: int=maxi(0,e.day-formed/1440)
		source_age=stable_age if source_age==null else maxi(int(source_age),stable_age)
		var ancestor: Dictionary=portion
		while not str(ancestor.parent_portion_id).is_empty():
			var parent: Dictionary=e._lots.portions[ancestor.parent_portion_id]
			if parent.owner!=portion.owner:break
			ancestor=parent
		var held_days: int=maxi(0,e.day-int(ancestor.opened_minute)/1440)
		holding_age=held_days if holding_age==null else maxi(int(holding_age),held_days)
	var durable_only: bool=false
	for category: String in e._spec.categories:
		if e._service(good,category)<=0:continue
		if e._spec.categories[category].mode=="flow":durable_only=false;break
		durable_only=true
	var target: int=mini(configured,int(p.trial_units));var reason: String="FINITE_TRIAL_WITHOUT_SALES_EVIDENCE"
	if sold>0:
		target=mini(configured,maxi(1,(sold*int(p.sales_cover_days)+int(p.window_days)-1)/int(p.window_days)))
		reason="OWN_DELIVERED_SALES_COVER"
	elif (holding_age if p.get("stable_holding_age",false) else oldest)!=null and int(holding_age if p.get("stable_holding_age",false) else oldest)>=int(p.idle_days):
		target=0;reason="IDLE_OWN_STOCK_WAIT_NO_RECENT_SALES"
	if durable_only and p.get("durable_trial_limit",false):
		target=mini(target,int(p.trial_units))
		var acquired: int=0;var disposed_by_sales: int=0
		for id: String in e._orders_by_buyer.get(e._owner(site),[]):
			var order: Dictionary=e._orders[id]
			if order.kind=="SALE" and order.good==good and order.buyer_site==site:acquired+=int(order.delivered)
		for fact: Dictionary in e._delivery_receipts.values():
			var order: Dictionary=e._orders[fact.order_id]
			if order.kind=="SALE" and order.seller_site==site and order.good==good:disposed_by_sales+=int(fact.quantity)
		# Transfers/losses are not evidence of successful terminal sales.
		if acquired-disposed_by_sales>=int(p.trial_units) and sold==0:
			target=0;reason="DURABLE_TRIAL_CAPITAL_WITHOUT_OWN_SALES"
	var funded_enquiries: int=e._received_pressure(site,good) if e.config.get("household_purchase_enquiries",false) else 0
	if funded_enquiries>0 and p.get("enquiry_trial_by_buyer",false):
		var buyers: Dictionary={}
		for request: Dictionary in e._request_pressure_records(site,good):
			if int(request.day)<e.day-int(e._operations_policy(site).demand_window)+1 or int(request.need_by_day)<e.day:continue
			if e._request_supply_pressure(request)>0:buyers[request.buyer]=mini(int(p.trial_units),maxi(int(buyers.get(request.buyer,0)),e._request_supply_pressure(request)))
		funded_enquiries=0
		for quantity: int in buyers.values():funded_enquiries+=quantity
	if funded_enquiries>target and not durable_only:
		target=mini(configured,funded_enquiries);reason="OWN_RECEIVED_FUNDED_STOCK_ENQUIRY_OPTIONAL_TRIAL"
	var result: Dictionary={"basis":p.basis,"reason":reason,"configured_buffer":configured,"optional_buffer_target":target,"window_start_day":start,"window_end_day":e.day,"window_days":p.window_days,"own_delivered_sales":sold,"receipt_count":receipts,"own_received_funded_stock_enquiries":funded_enquiries,"oldest_current_portion_age_lower_bound":oldest,"oldest_own_holding_age_days":holding_age,"oldest_source_formation_age_days":source_age,"age_basis":"ORIGINAL_SOURCE_FORMATION_INCLUDING_OPENING_NOT_MANUFACTURING_DATE","durable_only":durable_only,"trial_units":p.trial_units,"sales_cover_days":p.sales_cover_days,"cash_share_percent":p.cash_share_percent,"scope":"OWN_SITE_GOOD_NO_BUYER_SECRETS_NOT_PROFIT_OR_CREDIT_SCORE"}
	if p.has("enquiry_response") and good in p.get("enquiry_response_goods",[good]):result["market_time_signal"]=market_signal(e,site,good)
	if e._costs.enabled:result["turnover_experience"]=experience(e,site,good)
	return result

## A decision ceiling reconstructed from today's original adopted buy orders.
## It cannot reserve/pay money. Formal cash, due claims and admission still apply.
static func cash_window(e: RefCounted,firm: String,currency: String) -> Dictionary:
	var p: Dictionary=e.config.get("operating_inventory",{})
	if not p.get("enabled",false) or not (p.get("company_cash_window",false) or p.get("turnover_adaptation",false)):return {}
	var spendable: int=int(e._procurement_cash_position(firm,currency).spendable)
	var ceiling: int=spendable*int(p.cash_share_percent)/100
	var used: int=0;var first_minute: int=FormalLedgerState.MAX_AMOUNT
	for id: String in e._orders_by_buyer.get(firm,[]):
		var o: Dictionary=e._orders[id]
		if o.kind!="SALE" or int(o.accepted_day)!=e.day or o.denomination!=currency:continue
		var decision: Dictionary=e._commands.get(o.action_id,{}).get("result",{}).get("decision",{})
		var original: Dictionary=decision.get("company_cash_window",{})
		if original.is_empty():continue
		var protected: int=int(decision.get("replenishment",{}).get("protected_quantity",0))
		var unit_cost: int=int(o.price)+e._freight(o.route_legs)
		used+=maxi(0,int(o.quantity)-protected)*unit_cost
		if int(o.accepted_minute)<first_minute:
			first_minute=int(o.accepted_minute);ceiling=int(original.ceiling)
	# A later loss of cash/due wages still reduces executable spending.
	return {"basis":"OWN_COMPANY_DAY_OPTIONAL_CEILING_NOT_ACCOUNT","day":e.day,"ceiling":ceiling,"used":used,"remaining":mini(maxi(0,ceiling-used),spendable),"spendable_now":spendable,"cash_share_percent":p.cash_share_percent}
