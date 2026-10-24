extends RefCounted
## Optional order/notice coordination owned by EconomyAssetMarket.
## Shares live only in the parent's finite registry; money lives only in Ledger.
var parent_ref: WeakRef
var economy_ref: WeakRef
var config: Dictionary = {}
var bids: Dictionary = {}
var reports: Dictionary = {}
var clearings: Array = []
var next_bid: int = 1
var verification_commands: Dictionary = {}
var trade_releases: Dictionary = {}
var error: String = ""

func market() -> EconomyAssetMarket: return parent_ref.get_ref() as EconomyAssetMarket
func economy() -> EconomyR1Slice: return economy_ref.get_ref() as EconomyR1Slice if economy_ref!=null else null
func enabled() -> bool: return not config.is_empty()
func bind(owner: RefCounted,settings: Dictionary,e: RefCounted=null) -> void:
	parent_ref=weakref(owner)
	economy_ref=weakref(e) if e!=null else null
	config=settings.get("equity_call_market",{}).duplicate(true)

static func valid_configuration(settings: Dictionary,spec: Dictionary) -> bool:
	if not settings.has("equity_call_market"): return true
	var c: Variant=settings["equity_call_market"]
	if not c is Dictionary or not FormalLedgerState.exact_fields(c,["basis","asset_id","organization_id","share_class","genesis_basis","notice_days","report_period","max_valid_minutes","participants"]) or c["basis"]!="GENERATED_SIMULATION_ASSUMPTION_EQUITY_CALL" or c["genesis_basis"]!="EXPLICIT_DEVELOPMENT_FOUNDER_ALLOCATION" or c["share_class"]!="ECONOMIC_INTEREST_NO_AUTOMATIC_CONTROL" or not c["participants"] is Array or c["participants"].size()>4: return false
	var asset: Dictionary={}
	for a: Dictionary in settings.get("assets",[]):
		if a["id"]==c["asset_id"]: asset=a
	if asset.is_empty() or not spec["firms"].has(asset["issuer"]) or c["organization_id"]!=spec["firms"][asset["issuer"]].get("host_organization_id","") or str(c["organization_id"]).is_empty(): return false
	for f: String in ["notice_days","report_period","max_valid_minutes"]:
		if not FormalLedgerState.valid_amount(c[f]) or int(c[f])<1: return false
	if c["notice_days"]>7 or c["report_period"]>14 or c["max_valid_minutes"]>14*1440: return false
	var seen: Dictionary={}
	for p: Variant in c["participants"]:
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["actor","buy","sell","start","end","max_quantity","max_position","cash_floor","policy","period","target_cash","target_position","bid_limit","ask_limit","basis"]) or not asset["known_to"].has(p["actor"]) or seen.has(p["actor"]) or p["actor"]==asset["issuer"] or not p["buy"] is bool or not p["sell"] is bool or p["basis"]!="EXPLICIT_DEVELOPMENT_PORTFOLIO_MANDATE" or p["policy"] not in ["PLAYER","LIQUIDITY","HOLDING"]: return false
		if p["actor"]=="HOST_SELECTED_PLAYER":
			if not settings.get("host_personal_accounts",false) or p["policy"]!="PLAYER": return false
		elif not spec["firms"].has(p["actor"]) and (not spec["actors"].has(p["actor"]) or spec["actors"][p["actor"]]["kind"]!="named"): return false
		for f: String in ["start","end","max_quantity","max_position","cash_floor","period","target_cash","target_position","bid_limit","ask_limit"]:
			if not FormalLedgerState.valid_amount(p[f]): return false
		if p["end"]<=p["start"] or p["period"]<1 or p["max_quantity"]<1 or p["max_quantity"]>asset["total_shares"] or p["max_position"]>asset["total_shares"] or p["bid_limit"]<1 or p["ask_limit"]<1: return false
		seen[p["actor"]]=true
	return not seen.is_empty()

func participant(actor: String) -> Dictionary:
	for p: Dictionary in config.get("participants",[]):
		if p["actor"]==actor: return p
	return {}

func permission(actor: String,side: String,payload: Dictionary,minute: int,historical: bool=false) -> String:
	if not enabled(): return "EQUITY_CALL_OFF"
	var p:=participant(actor)
	if p.is_empty() or not p["buy" if side=="BUY" else "sell"] or minute<int(p["start"]) or minute>=int(p["end"]): return "NO_CURRENT_SHARE_TRANSFER_MANDATE"
	if payload.get("asset_id")!=config["asset_id"] or payload.get("denomination")!=FormalLedgerState.DENOMINATION: return "UNKNOWN_SHARE_CLASS_OR_CURRENCY"
	for f: String in ["quantity","price","valid_minutes"]:
		if not FormalLedgerState.valid_amount(payload.get(f)) or int(payload[f])<1: return "INVALID_SHARE_ORDER"
	if int(payload["quantity"])>int(p["max_quantity"]) or int(payload["price"])>FormalLedgerState.MAX_AMOUNT/int(payload["quantity"]) or int(payload["valid_minutes"])>int(config["max_valid_minutes"]) or int(payload["valid_minutes"])>int(p["end"])-minute: return "SHARE_ORDER_LIMIT_OR_EXPIRY"
	var e:=economy()
	if not historical and e!=null and e._spec["firms"].has(actor):
		if e.firm_finished(actor) or e._firm_winding_down(actor): return "PORTFOLIO_FIRM_NOT_OPEN_FOR_NEW_COMMITMENTS"
		var organization: String=e._spec["firms"][actor].get("host_organization_id","")
		if not e._world.organization_state.is_organization_active(organization) or e._world.organization_state.organization_kind(organization) not in ["company","enterprise","corporation"]: return "NO_ACTIVE_PORTFOLIO_ORGANIZATION"
	return ""

func bid(actor: String,payload: Dictionary,minute: int,action: String) -> Dictionary:
	var m:=market()
	if not FormalLedgerState.exact_fields(payload,["asset_id","quantity","price","denomination","valid_minutes"]): return m._result(false,"INVALID_SHARE_BID")
	var why:=permission(actor,"BUY",payload,minute)
	if not why.is_empty(): return m._result(false,why)
	var account:=m._ledger.owner_account(actor,payload["denomination"])
	var amount: int=int(payload["quantity"])*int(payload["price"])
	var owned: int=int(m._assets[payload["asset_id"]]["holders"].get(actor,0))
	var pending: int=0
	for b: Dictionary in bids.values():
		if b["buyer"]==actor and b["status"]=="OPEN": pending+=int(b["remaining"])
	if owned+pending+int(payload["quantity"])>int(participant(actor)["max_position"]): return m._result(false,"SHARE_POSITION_LIMIT")
	if next_bid>=FormalLedgerState.MAX_AMOUNT: return m._result(false,"SHARE_BID_SEQUENCE_BOUNDS")
	if account.is_empty() or m._ledger.available_balance(account)<amount: return m._result(false,"SHARE_BUYER_FUNDS_OR_ACCOUNT")
	var id: String="asset_bid:"+str(next_bid)
	if not m._ledger.reserve(id,account,amount): return m._result(false,"SHARE_BID_RESERVATION_FAILED")
	bids[id]={"id":id,"buyer":actor,"asset_id":payload["asset_id"],"quantity":payload["quantity"],"remaining":payload["quantity"],"cancelled":0,"paid":0,"price":payload["price"],"denomination":payload["denomination"],"account_id":account,"offered_minute":minute,"expires_minute":minute+int(payload["valid_minutes"]),"closed_minute":-1,"closed_action":"","status":"OPEN","action_id":action}
	next_bid+=1
	return {"accepted":true,"reason":"CASH_RESERVED_AWAITING_DAILY_CALL","order_id":id,"quantity":payload["quantity"],"reserved":amount}

func close_bid(b: Dictionary,status: String,minute: int,action: String="") -> bool:
	var cash: int=int(b["remaining"])*int(b["price"])
	if cash>0 and not market()._ledger.release(b["id"],cash): return false
	b["cancelled"]=b["remaining"];b["remaining"]=0;b["status"]=status;b["closed_minute"]=minute;b["closed_action"]=action
	return true

func cancel(actor: String,payload: Dictionary,minute: int,action: String) -> Dictionary:
	var b: Dictionary=bids.get(payload.get("order_id"),{})
	if not FormalLedgerState.exact_fields(payload,["order_id"]) or b.is_empty() or b["buyer"]!=actor or b["status"]!="OPEN" or minute>=int(b["expires_minute"]): return market()._result(false,"NOT_OWN_OPEN_SHARE_BID")
	var released: int=int(b["remaining"])*int(b["price"])
	if not close_bid(b,"CANCELLED",minute,action): return market()._result(false,"SHARE_RELEASE_FAILED")
	return {"accepted":true,"reason":"ACCEPTED","order_id":b["id"],"released":released}

func advance_time(minute: int) -> void:
	for b: Dictionary in bids.values():
		if b["status"]=="OPEN" and int(b["expires_minute"])<=minute: close_bid(b,"EXPIRED",int(b["expires_minute"]))

func reservations(rows: Dictionary={}) -> Dictionary:
	var result: Dictionary={}
	for b: Variant in (bids if rows.is_empty() else rows).values():
		if b is Dictionary and b.get("status")=="OPEN" and FormalLedgerState.valid_amount(b.get("remaining")) and FormalLedgerState.valid_amount(b.get("price")):
			result[b["id"]]={"account_id":b["account_id"],"amount":int(b["remaining"])*int(b["price"])}
	return result

func best_pair(asks: Dictionary,buy_orders: Dictionary,minute: int) -> Dictionary:
	var buyers: Array=buy_orders.values().filter(func(b: Dictionary) -> bool: return b["status"]=="OPEN" and b["remaining"]>0 and b["expires_minute"]>minute)
	var sellers: Array=asks.values().filter(func(a: Dictionary) -> bool: return a["status"]=="OPEN" and a["remaining"]>0 and a["expires_minute"]>minute)
	buyers.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a["price"]>b["price"] if a["price"]!=b["price"] else priority(a,b))
	sellers.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a["price"]<b["price"] if a["price"]!=b["price"] else priority(a,b))
	for b: Dictionary in buyers:
		for a: Dictionary in sellers:
			if a["asset_id"]==b["asset_id"] and a["denomination"]==b["denomination"] and a["seller"]!=b["buyer"] and int(a["price"])<=int(b["price"]): return {"ask":a,"bid":b}
	return {}

func priority(a: Dictionary,b: Dictionary) -> bool:
	if a["offered_minute"]!=b["offered_minute"]: return a["offered_minute"]<b["offered_minute"]
	return int(str(a["id"]).get_slice(":",1))<int(str(b["id"]).get_slice(":",1))

func settle(actor: String,payload: Dictionary,minute: int,action: String) -> Dictionary:
	var m:=market();var e:=economy()
	if not enabled() or actor!=m._configured[config["asset_id"]]["issuer"] or e.phase!="EQUITY_CLEARING" or minute%1440!=0 or not FormalLedgerState.exact_fields(payload,["bid_id","order_id"]): return m._result(false,"NO_DAILY_SHARE_EXECUTION_AUTHORITY")
	var pair:=best_pair(m._orders,bids,minute)
	if pair.is_empty() or payload["bid_id"]!=pair["bid"]["id"] or payload["order_id"]!=pair["ask"]["id"]: return m._result(false,"SHARE_PRICE_TIME_PRIORITY_CONFLICT")
	var b: Dictionary=pair["bid"];var a: Dictionary=pair["ask"]
	var quantity: int=mini(int(a["remaining"]),int(b["remaining"]))
	var result:=m.accept(b["buyer"],{"order_id":a["id"],"quantity":quantity,"max_price":b["price"],"denomination":b["denomination"]},minute,action,b)
	if result.get("accepted",false):
		b["remaining"]-=quantity;b["paid"]+=quantity*int(a["price"])
		if b["remaining"]==0: b["status"]="FILLED";b["closed_minute"]=minute
	return result

func clear_day() -> void:
	if not enabled(): return
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	if now==0 or now%1440!=0 or (not clearings.is_empty() and clearings.back()["minute"]==now): return
	var adopted: Array=[]
	while true:
		var pair:=best_pair(market()._orders,bids,now)
		if pair.is_empty(): break
		var result:=e._npc_submit(market()._configured[config["asset_id"]]["issuer"],"settle_share_bid",{"bid_id":pair["bid"]["id"],"order_id":pair["ask"]["id"]},"equity_call:"+str(market().next_trade),{"basis":"ACCEPTED_INVESTOR_ORDERS_PRICE_TIME_PRIORITY"})
		if not result.get("accepted",false): break
		adopted.append(result["trade_id"])
	clearings.append({"minute":now,"command_count":e._commands.size(),"trade_ids":adopted})

func summary(minute: int,native: Dictionary={}) -> Dictionary:
	var e:=economy();var issuer: String=market()._configured[config["asset_id"]]["issuer"]
	var orders: Dictionary=native.get("orders",e._orders)
	var receipts: Dictionary=native.get("delivery_receipts",e._delivery_receipts)
	var wages: Dictionary=native.get("wages",e._wages)
	var revenue: int=0;var quantity: int=0;var accrued: int=0
	var refs: Array=[];var work: Array=[]
	for r: Dictionary in receipts.values():
		var order: Dictionary=orders.get(r["order_id"],{})
		var at: int=e._delivery_minute(r)
		if order.get("kind")=="SALE" and order["seller"]==issuer and at<=minute and at>minute-3*1440:
			revenue+=int(order["price"])*int(r["quantity"]);quantity+=int(r["quantity"]);refs.append(r["id"])
	for w: Dictionary in wages.values():
		if w["employer"]==issuer and int(w["work_day"])*1440<=minute and int(w["work_day"])*1440>minute-3*1440: accrued+=int(w["amount"]);work.append(w["id"])
	refs.sort();work.sort()
	return {"window_days":3,"delivered":quantity,"goods_receipts":revenue,"wages_incurred":accrued,"delivery_refs":refs,"work_refs":work,"basis":"LIMITED_DISCLOSURE_NOT_PROFIT_OR_VALUATION"}

func publish(actor: String,payload: Dictionary,minute: int,action: String) -> Dictionary:
	if not enabled() or payload!={"asset_id":config["asset_id"]} or actor!=market()._configured[config["asset_id"]]["issuer"]: return market()._result(false,"NO_ISSUER_DISCLOSURE_AUTHORITY")
	var id: String="equity_report:"+action
	reports[id]={"id":id,"asset_id":config["asset_id"],"issuer":actor,"minute":minute,"action_id":action,"summary":summary(minute)}
	var e:=economy()
	for p: Dictionary in config["participants"]:
		e._messages.append({"id":"notice:"+id+":"+p["actor"],"actor":p["actor"],"kind":"equity_report","candidate":id,"observed_day":e.day,"delivery_day":e.day+int(config["notice_days"])})
	return {"accepted":true,"reason":"LIMITED_REPORT_PUBLISHED","report_id":id}

func report_known(actor: String,receipts: Dictionary={},minute: int=-1) -> Dictionary:
	var e:=economy();var result: Dictionary={}
	if minute<0: minute=e._world.game_clock.total_minutes()
	for m: Dictionary in (e._receipts if receipts.is_empty() else receipts).values():
		if m.get("kind")!="equity_report" or m["actor"]!=actor or int(m["delivery_day"])*1440>minute or not reports.has(m["candidate"]): continue
		var r: Dictionary=reports[m["candidate"]]
		if result.is_empty() or r["minute"]>result["minute"]: result=r
	return result.duplicate(true)

func message_valid(m: Dictionary) -> bool:
	if not enabled() or not FormalLedgerState.exact_fields(m,["id","actor","kind","candidate","observed_day","delivery_day"]) or not reports.has(m["candidate"]) or participant(m["actor"]).is_empty(): return false
	var r: Dictionary=reports[m["candidate"]]
	return m["id"]=="notice:"+r["id"]+":"+m["actor"] and int(m["observed_day"])==int(r["minute"])/1440 and int(m["delivery_day"])==int(m["observed_day"])+int(config["notice_days"])

func npc_decisions() -> void:
	if not enabled(): return
	var e:=economy();var now: int=e._world.game_clock.total_minutes()
	var issuer: String=market()._configured[config["asset_id"]]["issuer"]
	if e.day>0 and e.day%int(config["report_period"])==0: e._npc_submit(issuer,"publish_equity_report",{"asset_id":config["asset_id"]},"equity_disclosure",{"basis":"CONFIGURED_LIMITED_ISSUER_DISCLOSURE"})
	for p: Dictionary in config["participants"]:
		var actor: String=p["actor"]
		if p["policy"]=="PLAYER" or e.day==0 or e.day%int(p["period"])!=0 or now<int(p["start"]) or now>=int(p["end"]): continue
		var known:=report_known(actor)
		if known.is_empty(): continue
		var free: int=market()._ledger.available_balance(market()._ledger.owner_account(actor))
		var own: int=int(market()._assets[config["asset_id"]]["holders"].get(actor,0))
		var open: bool=false
		for o: Dictionary in market()._orders.values():
			if o["seller"]==actor and o["status"]=="OPEN": open=true
		for b: Dictionary in bids.values():
			if b["buyer"]==actor and b["status"]=="OPEN": open=true
		if open: continue
		var due: int=int(e._mature_wage_position(actor,FormalLedgerState.DENOMINATION)["amount"])
		for loan: Dictionary in e._credit._loans.values():
			if loan["borrower"]==actor and loan["due_day"]<=e.day: due+=maxi(0,int(loan["principal"])+int(loan["interest"])-int(loan["repaid"])-int(loan["forgiven"]))
		var quantity: int=0;var kind: String="";var price: int=0
		if p["policy"]=="LIQUIDITY" and free<int(p["target_cash"])+due:
			quantity=mini(int(p["max_quantity"]),own-int(market()._assets[config["asset_id"]]["reserved"].get(actor,0)));kind="sell_shares";price=int(p["ask_limit"])
		elif p["policy"]=="HOLDING" and known["summary"]["delivered"]>0 and known["summary"]["goods_receipts"]>=known["summary"]["wages_incurred"] and free>int(p["cash_floor"])+due:
			quantity=mini(2,mini(int(p["target_position"])-own,(free-int(p["cash_floor"])-due)/int(p["bid_limit"])));kind="bid_shares";price=int(p["bid_limit"])
		if quantity<=0: continue
		e._npc_submit(actor,kind,{"asset_id":config["asset_id"],"quantity":quantity,"price":price,"denomination":FormalLedgerState.DENOMINATION,"valid_minutes":mini(7*1440,int(p["end"])-now)},"portfolio:"+config["asset_id"],{"policy":p["policy"],"report_id":known["id"],"own_available":free,"protected_due":due,"own_holdings":own,"basis":p["basis"]})

func visible(actor: String,minute: int) -> Dictionary:
	if not enabled() or participant(actor).is_empty(): return {}
	var m:=market();var own: Dictionary=m._assets[config["asset_id"]]
	var public_trades: Array=m._trades.values().filter(func(t: Dictionary) -> bool: return t["asset_id"]==config["asset_id"])
	var own_bids: Array=bids.values().filter(func(b: Dictionary) -> bool: return b["buyer"]==actor)
	var book_bids: Array=bids.values().filter(func(b: Dictionary) -> bool: return b["status"]=="OPEN")
	var book_asks: Array=m._orders.values().filter(func(a: Dictionary) -> bool: return a["status"]=="OPEN" and a["asset_id"]==config["asset_id"])
	book_bids=book_bids.duplicate(true);book_asks=book_asks.duplicate(true)
	book_bids.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a["price"]>b["price"] if a["price"]!=b["price"] else priority(a,b))
	book_asks.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a["price"]<b["price"] if a["price"]!=b["price"] else priority(a,b))
	for row: Dictionary in book_bids:
		for private_field: String in ["account_id","action_id","closed_action","paid"]: row.erase(private_field)
	for row: Dictionary in book_asks:
		for private_field: String in ["action_id","closed_action"]: row.erase(private_field)
	var account:=m._ledger.owner_account(actor)
	var payments: Dictionary={}
	for t: Dictionary in public_trades: payments[t["id"]]=m._ledger.transaction(t["id"])
	var company_receipts: int=0
	for tx: Dictionary in m._ledger.transactions():
		if tx["kind"]=="asset_trade" and tx["to_account_id"]==m._ledger.owner_account(own["issuer"]): company_receipts+=int(tx["amount"])
	return {"asset_id":config["asset_id"],"issuer":own["issuer"],"organization_id":config["organization_id"],"share_class":config["share_class"],"genesis_basis":config["genesis_basis"],"total_shares":own["total_shares"],"holdings":own["holders"].get(actor,0),"locked_shares":own["reserved"].get(actor,0),"cash":m._ledger.available_balance(account),"reserved_cash":m._ledger.reserved_balance(account),"own_bids":own_bids.slice(-20),"own_asks":m._orders.values().filter(func(a: Dictionary)->bool: return a["seller"]==actor).slice(-20),"bids":book_bids.slice(-30),"asks":book_asks.slice(-30),"trades":public_trades.slice(-30),"payments":payments,"clearings":clearings.slice(-30),"report":report_known(actor),"permission":participant(actor).duplicate(true),"last_price":public_trades.back()["price"] if not public_trades.is_empty() else null,"company_secondary_receipts":company_receipts,"information_basis":"FINITE_PUBLIC_ORDER_BOOK_AND_ACTUALLY_RECEIVED_REPORTS_NO_PRIVATE_COUNTERPARTY_CASH"}.duplicate(true)

func snapshot() -> Dictionary:
	return {"format":"EQUITY_CALL_EXPERIMENT_V1","bids":bids.duplicate(true),"reports":reports.duplicate(true),"clearings":clearings.duplicate(true),"next_bid":next_bid}

func prepare(value: Variant) -> bool:
	if not enabled(): return value==null
	if not value is Dictionary or not FormalLedgerState.exact_fields(value,["format","bids","reports","clearings","next_bid"]) or value["format"]!="EQUITY_CALL_EXPERIMENT_V1" or not value["bids"] is Dictionary or not value["reports"] is Dictionary or not value["clearings"] is Array or not FormalLedgerState.valid_amount(value["next_bid"]): return fail("Invalid equity call containers")
	bids=value["bids"].duplicate(true);reports=value["reports"].duplicate(true)
	for r: Variant in reports.values():
		if not r is Dictionary or not FormalLedgerState.exact_fields(r,["id","asset_id","issuer","minute","action_id","summary"]) or not r["id"] is String or not r["action_id"] is String or not FormalLedgerState.valid_amount(r["minute"]) or not r["summary"] is Dictionary: return fail("Invalid issuer report shape")
	for b: Variant in bids.values():
		if not b is Dictionary or not FormalLedgerState.exact_fields(b,["id","buyer","asset_id","quantity","remaining","cancelled","paid","price","denomination","account_id","offered_minute","expires_minute","closed_minute","closed_action","status","action_id"]): return fail("Invalid bid shape")
		for f: String in ["quantity","remaining","cancelled","paid","price","offered_minute","expires_minute"]:
			if not FormalLedgerState.valid_amount(b[f]): return fail("Invalid bid amount")
		if b["quantity"]<1 or b["price"]<1 or b["price"]>FormalLedgerState.MAX_AMOUNT/b["quantity"] or not b["id"] is String or not b["buyer"] is String or not b["account_id"] is String or not b["action_id"] is String: return fail("Invalid bid bounds")
	return true

func validate_history(value: Dictionary,commands: Dictionary,minute: int,native: Dictionary) -> bool:
	if not prepare(value.get("call_market")): return false
	var saved: Dictionary=value["call_market"]
	verification_commands=commands.duplicate(true);trade_releases.clear()
	var working: Dictionary={};var asks: Dictionary={};var owned: Dictionary={}
	owned=market()._configured[config["asset_id"]]["holders"].duplicate(true)
	var reports_seen: Dictionary={};var trades_seen: Dictionary={};var n: int=1
	var boundaries: Dictionary={};var clearing_by_trade: Dictionary={}
	if saved["clearings"].size()!=minute/1440: return fail("Missing daily share call boundaries")
	var previous_count: int=0
	var trade_positions: Dictionary={}
	var execution_order: Dictionary={}
	for i: int in saved["clearings"].size():
		var c: Variant=saved["clearings"][i]
		if not c is Dictionary or not FormalLedgerState.exact_fields(c,["minute","command_count","trade_ids"]) or c["minute"]!=(i+1)*1440 or not FormalLedgerState.valid_amount(c["command_count"]) or c["command_count"]>commands.size() or c["command_count"]<previous_count or not c["trade_ids"] is Array: return fail("Invalid clearing boundary or adoption cursor")
		var start_count: int=previous_count
		previous_count=c["command_count"]
		if not boundaries.has(c["command_count"]): boundaries[c["command_count"]]=[]
		boundaries[c["command_count"]].append(c)
		execution_order[c["minute"]]=[]
		for id: Variant in c["trade_ids"]:
			if not id is String or clearing_by_trade.has(id): return fail("Repeated daily share execution")
			clearing_by_trade[id]=c["minute"]
			trade_positions[id]=[start_count,c["command_count"]]
	var index: int=0
	var last_cleared_minute: int=0
	for c: Dictionary in boundaries.get(0,[]):
		if not c["trade_ids"].is_empty(): return fail("Empty adoption cursor contains a trade")
		last_cleared_minute=int(c["minute"])
	for action: String in commands:
		index+=1
		var entry: Variant=commands[action]
		if not entry is Dictionary or not entry.get("envelope") is Dictionary or not entry["envelope"].get("command") is Dictionary or not entry.get("result") is Dictionary: return fail("Malformed financial action")
		var cmd: Dictionary=entry["envelope"]["command"];var result: Dictionary=entry["result"]
		var kind: String=cmd.get("kind","");var actor: String=entry["envelope"].get("actor","")
		var payload: Dictionary=cmd.get("payload",{});var at: int=int(cmd.get("minute",-1))
		if at<last_cleared_minute: return fail("Action precedes an already adopted daily call")
		if kind in ["bid_shares","publish_equity_report"]: verification_commands.erase(action)
		if result.get("accepted",false):
			if kind=="settle_share_issue":
				var registry: Dictionary={config["asset_id"]:{"holders":owned,"total_shares":0}}
				market().primary.ownership_effect(action,registry,{})
			elif kind=="sell_shares":
				var why:=permission(actor,"SELL",payload,at,true)
				if not why.is_empty() or not value["orders"].has(result.get("order_id","")): return fail("Share ask lacks portfolio mandate or record")
				var a: Dictionary=value["orders"][result["order_id"]].duplicate(true)
				a.merge({"remaining":a["quantity"],"cancelled":0,"status":"OPEN","closed_minute":-1,"closed_action":""},true);asks[a["id"]]=a
			elif kind=="bid_shares":
				var id: String="asset_bid:"+str(n);n+=1
				if not bids.has(id) or not permission(actor,"BUY",payload,at,true).is_empty(): return fail("Bid lost its accepted mandate or sequence")
				var b: Dictionary=bids[id]
				if not FormalLedgerState.exact_fields(payload,["asset_id","quantity","price","denomination","valid_minutes"]) or b["id"]!=id or b["buyer"]!=actor or b["action_id"]!=action or b["offered_minute"]!=at or b["expires_minute"]!=at+int(payload["valid_minutes"]) or b["account_id"]!=market()._ledger.owner_account(actor,payload["denomination"]): return fail("Bid source, account or dates conflict")
				for f: String in ["asset_id","quantity","price","denomination"]:
					if b[f]!=payload[f]: return fail("Bid terms differ from original action")
				if result.get("order_id")!=id or result.get("quantity")!=b["quantity"] or result.get("reserved")!=int(b["quantity"])*int(b["price"]): return fail("Bid commitment differs from accepted result")
				var pending: int=0
				for prior: Dictionary in working.values():
					if prior["buyer"]==actor and prior["status"]=="OPEN" and prior["expires_minute"]>at: pending+=int(prior["remaining"])
				if int(owned.get(actor,0))+pending+int(b["quantity"])>int(participant(actor)["max_position"]): return fail("Bid exceeded ownership exposure limit")
				working[id]=b.duplicate(true);working[id].merge({"remaining":b["quantity"],"cancelled":0,"paid":0,"status":"OPEN","closed_minute":-1,"closed_action":""},true)
			elif kind=="cancel_share_order" and working.has(payload.get("order_id","")):
				var b: Dictionary=working[payload["order_id"]]
				if b["buyer"]!=actor or b["status"]!="OPEN" or at>=int(b["expires_minute"]) or result.get("order_id")!=b["id"] or result.get("released")!=int(b["remaining"])*int(b["price"]): return fail("Invalid cash reservation cancellation")
				b["cancelled"]=b["remaining"];b["remaining"]=0;b["status"]="CANCELLED";b["closed_minute"]=at;b["closed_action"]=action
				verification_commands.erase(action)
			elif kind=="cancel_share_order" and asks.has(payload.get("order_id","")):
				var a: Dictionary=asks[payload["order_id"]]
				a["status"]="CANCELLED";a["remaining"]=0
			elif kind=="publish_equity_report":
				var id: String="equity_report:"+action
				var expected: Dictionary={"id":id,"asset_id":config["asset_id"],"issuer":market()._configured[config["asset_id"]]["issuer"],"minute":at,"action_id":action,"summary":summary(at,native)}
				if payload!={"asset_id":config["asset_id"]} or actor!=expected["issuer"] or reports.get(id)!=expected or result.get("report_id")!=id: return fail("Invalid issuer disclosure source or facts")
				reports_seen[id]=true
			elif kind=="settle_share_bid":
				var pair:=best_pair(asks,working,at)
				var t: Dictionary=value["trades"].get(result.get("trade_id",""),{})
				if pair.is_empty() or not FormalLedgerState.exact_fields(payload,["bid_id","order_id"]) or actor!=market()._configured[config["asset_id"]]["issuer"] or at%1440!=0 or t.is_empty(): return fail("Execution lacks accepted counterparties or daily authority")
				var b: Dictionary=pair["bid"];var a: Dictionary=pair["ask"]
				var quantity: int=mini(int(a["remaining"]),int(b["remaining"]))
				if payload["bid_id"]!=b["id"] or payload["order_id"]!=a["id"] or t.get("bid_id")!=b["id"] or t["order_id"]!=a["id"] or t["buyer"]!=b["buyer"] or t["seller"]!=a["seller"] or t["quantity"]!=quantity or t["price"]!=a["price"] or t["minute"]!=at or clearing_by_trade.get(t["id"])!=at: return fail("Share counterpart, quantity or price-time priority conflict")
				if index<=int(trade_positions[t["id"]][0]) or index>int(trade_positions[t["id"]][1]): return fail("Execution is outside its daily adoption boundary")
				execution_order[at].append(t["id"])
				trade_releases[t["id"]]={b["id"]:quantity*int(b["price"])}
				b["remaining"]-=quantity;b["paid"]+=quantity*int(a["price"])
				if b["remaining"]==0: b["status"]="FILLED";b["closed_minute"]=at
				a["remaining"]-=quantity
				if a["remaining"]==0: a["status"]="FILLED"
				owned[a["seller"]]=int(owned.get(a["seller"],0))-quantity;owned[b["buyer"]]=int(owned.get(b["buyer"],0))+quantity
				var normalized: Dictionary=verification_commands[action]
				normalized["envelope"]["actor"]=b["buyer"]
				normalized["envelope"]["command"]["kind"]="accept_share_order"
				normalized["envelope"]["command"]["payload"]={"order_id":a["id"],"quantity":quantity,"max_price":b["price"],"denomination":b["denomination"]}
				trades_seen[t["id"]]=true
			elif kind in ["accept_share_order","pay_dividend"]: return fail("Call experiment cannot bypass orders or enable dividends")
		for c: Dictionary in boundaries.get(index,[]):
			if execution_order[c["minute"]]!=c["trade_ids"]: return fail("Daily execution sequence differs from adopted actions")
			if at>int(c["minute"]) or not best_pair(asks,working,int(c["minute"])).is_empty(): return fail("Daily call omitted an executable counterparty")
			last_cleared_minute=int(c["minute"])
	if n!=saved["next_bid"] or working.size()!=bids.size() or reports_seen.size()!=reports.size() or trades_seen.size()!=value["trades"].size() or trades_seen.size()!=clearing_by_trade.size(): return fail("Orphan equity orders, reports or trades")
	for b: Dictionary in working.values():
		if b["status"]=="OPEN" and b["expires_minute"]<=minute:
			b["cancelled"]=b["remaining"];b["remaining"]=0;b["status"]="EXPIRED";b["closed_minute"]=b["expires_minute"]
	if working!=bids: return fail("Saved bid remainder, payment or release conflict")
	for r: Dictionary in reports.values():
		for p: Dictionary in config["participants"]:
			var id: String="notice:"+r["id"]+":"+p["actor"]
			var found: Variant=native.get("receipts",{}).get(id)
			if found==null:
				for pending: Dictionary in native.get("messages",[]):
					if pending["id"]==id: found=pending;break
			if not found is Dictionary or not message_valid(found): return fail("Issuer report lost a directed notice")
	clearings=saved["clearings"].duplicate(true);next_bid=n
	return true

func fail(why: String) -> bool:
	error=why
	return false
