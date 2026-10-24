class_name EconomyAssetMarket
extends RefCounted
## Finite issued ownership, reserved asks, and immediate bilateral delivery.
## Managers are explicit configuration; ownership never grants cash authority.

const CallMarket = preload("res://scripts/world/economy_equity_call_market.gd")
var call_market := CallMarket.new()
const Primary = preload("res://scripts/world/economy_equity_primary.gd")
var primary := Primary.new()
const Distribution = preload("res://scripts/world/economy_shareholder_cash_distribution.gd")
var distribution := Distribution.new()
const Corporate = preload("res://scripts/world/economy_corporate_finance_policy.gd")
var corporate := Corporate.new()
const SCHEMA_ID: String = "economy_asset_market_v1"
const ACTIONS: Array[String] = ["sell_shares", "accept_share_order", "cancel_share_order", "pay_dividend", "bid_shares", "settle_share_bid", "publish_equity_report", "publish_share_issue", "subscribe_share_issue", "cancel_share_issue", "settle_share_issue", "declare_share_distribution", "settle_share_distribution", "review_corporate_finance"]
const CONFIG_FIELDS: Array[String] = ["id", "issuer", "total_shares", "holders", "manager", "known_to"]
const ORDER_FIELDS: Array[String] = ["id", "seller", "asset_id", "quantity", "remaining", "cancelled", "price", "denomination", "offered_minute", "expires_minute", "closed_minute", "closed_action", "status", "action_id"]
const TRADE_FIELDS: Array[String] = ["id", "order_id", "buyer", "seller", "asset_id", "quantity", "price", "denomination", "minute", "action_id"]
const DIVIDEND_FIELDS: Array[String] = ["id", "asset_id", "manager", "budget", "denomination", "minute", "payments", "total_paid", "action_id"]

var error: String = ""
var _ledger: FormalLedgerState
var _configured: Dictionary = {}
var _assets: Dictionary = {}
var _orders: Dictionary = {}
var _trades: Dictionary = {}
var _dividends: Dictionary = {}
var _expiry: Dictionary = {}
var next_order: int = 1
var next_trade: int = 1
var next_dividend: int = 1

func bind(ledger: FormalLedgerState, settings: Dictionary, economy: RefCounted=null) -> void:
	call_market.bind(self,settings,economy)
	primary.bind(self,settings,economy)
	distribution.bind(self,settings,economy)
	corporate.bind(self,settings,economy)
	_ledger = ledger
	_configured.clear()
	for row: Dictionary in settings.get("assets", []):
		_configured[row["id"]] = row.duplicate(true)

func initialize() -> void:
	_assets = _initial_assets()

func _initial_assets() -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in _configured.values():
		result[row["id"]] = {"id": row["id"], "issuer": row["issuer"], "total_shares": row["total_shares"], "holders": row["holders"].duplicate(true), "reserved": {}}
	return result

func _known(actor: String, asset_id: String) -> bool:
	return _configured.has(asset_id) and _configured[asset_id]["known_to"].has(actor)

func sell(actor: String, payload: Dictionary, minute: int, action_id: String) -> Dictionary:
	if not FormalLedgerState.exact_fields(payload, ["asset_id", "quantity", "price", "denomination", "valid_minutes"]) or not payload["asset_id"] is String or not _known(actor, payload["asset_id"]) or not _positive(payload["quantity"]) or not _positive(payload["price"]) or not _positive(payload["valid_minutes"]) or not FormalLedgerState.currency_id(payload["denomination"]):
		return _result(false, "INVALID_OR_UNKNOWN_SHARE_OFFER")
	if call_market.enabled():
		var why: String=call_market.permission(actor,"SELL",payload,minute)
		if not why.is_empty(): return _result(false,why)
	var asset := _assets[payload["asset_id"]] as Dictionary
	var amount := int(payload["quantity"])
	if _ledger.owner_account(actor, payload["denomination"]).is_empty() or amount > int(asset["holders"].get(actor, 0)) - int(asset["reserved"].get(actor, 0)):
		return _result(false, "SHARES_OR_CURRENCY_ACCOUNT_UNAVAILABLE")
	if minute > FormalLedgerState.MAX_AMOUNT - int(payload["valid_minutes"]) or next_order >= FormalLedgerState.MAX_AMOUNT or int(payload["price"]) > FormalLedgerState.MAX_AMOUNT / amount:
		return _result(false, "SHARE_OFFER_BOUNDS")
	var id := "asset_order:" + str(next_order)
	var row := {"id": id, "seller": actor, "asset_id": payload["asset_id"], "quantity": amount, "remaining": amount, "cancelled": 0, "price": payload["price"], "denomination": payload["denomination"], "offered_minute": minute, "expires_minute": minute + int(payload["valid_minutes"]), "closed_minute": -1, "closed_action": "", "status": "OPEN", "action_id": action_id}
	asset["reserved"][actor] = int(asset["reserved"].get(actor, 0)) + amount
	_orders[id] = row
	_index_expiry(row)
	next_order += 1
	return {"accepted": true, "reason": "ACCEPTED", "order_id": id, "quantity": amount}

func accept(actor: String, payload: Dictionary, minute: int, action_id: String, bid: Dictionary={}) -> Dictionary:
	if call_market.enabled() and bid.is_empty(): return _result(false,"ACCEPTANCE_REQUIRES_DAILY_SHARE_CALL")
	if not FormalLedgerState.exact_fields(payload, ["order_id", "quantity", "max_price", "denomination"]) or not payload["order_id"] is String or not _positive(payload["quantity"]) or not _positive(payload["max_price"]):
		return _result(false, "INVALID_SHARE_ACCEPTANCE")
	var order: Dictionary = _orders.get(payload["order_id"], {})
	if order.is_empty() or not _known(actor, order["asset_id"]) or order["seller"] == actor:
		return _result(false, "UNKNOWN_SHARE_ORDER")
	if order["status"] != "OPEN" or minute >= int(order["expires_minute"]):
		return _result(false, "SHARE_ORDER_CLOSED")
	var amount := int(payload["quantity"])
	var asset := _assets[order["asset_id"]] as Dictionary
	var seller := str(order["seller"])
	if payload["denomination"] != order["denomination"] or int(payload["max_price"]) < int(order["price"]) or amount > int(order["remaining"]) or amount > int(asset["reserved"].get(seller, 0)) or amount > int(asset["holders"].get(seller, 0)) or next_trade >= FormalLedgerState.MAX_AMOUNT:
		return _result(false, "SHARE_LIMIT_OR_RESERVATION")
	var buyer_account := _ledger.owner_account(actor, order["denomination"])
	var seller_account := _ledger.owner_account(seller, order["denomination"])
	var cash := amount * int(order["price"])
	var releases: Dictionary={} if bid.is_empty() else {bid["id"]:amount*int(bid["price"])}
	if buyer_account.is_empty() or seller_account.is_empty() or _ledger.available_balance(buyer_account)+int(releases.get(bid.get("id",""),0)) < cash:
		return _result(false, "SHARE_BUYER_FUNDS_OR_ACCOUNT")
	var id := "asset_trade:" + str(next_trade)
	var trade := {"id": id, "order_id": order["id"], "buyer": actor, "seller": seller, "asset_id": order["asset_id"], "quantity": amount, "price": order["price"], "denomination": order["denomination"], "minute": minute, "action_id": action_id}
	var legs: Array[Dictionary] = [_trade_leg(trade)]
	if not bid.is_empty(): trade["bid_id"]=bid["id"]
	if not _ledger.batch_payment(id, legs, minute, releases):
		return {"accepted": false, "reason": "SHARE_PAYMENT_FAILED", "message": _ledger.error}
	# All ownership and order bounds were resolved before cash commitment.
	asset["holders"][seller] = int(asset["holders"][seller]) - amount
	asset["holders"][actor] = int(asset["holders"].get(actor, 0)) + amount
	asset["reserved"][seller] = int(asset["reserved"][seller]) - amount
	if int(asset["reserved"][seller]) == 0:
		asset["reserved"].erase(seller)
	order["remaining"] = int(order["remaining"]) - amount
	if int(order["remaining"]) == 0:
		order["status"] = "FILLED"
		order["closed_minute"] = minute
	_trades[id] = trade
	next_trade += 1
	return {"accepted": true, "reason": "ACCEPTED", "trade_id": id, "quantity": amount, "cash": cash}

func cancel(actor: String, payload: Dictionary, minute: int, action_id: String) -> Dictionary:
	if call_market.enabled() and call_market.bids.has(payload.get("order_id","")): return call_market.cancel(actor,payload,minute,action_id)
	if not FormalLedgerState.exact_fields(payload, ["order_id"]) or not payload["order_id"] is String:
		return _result(false, "INVALID_SHARE_CANCELLATION")
	var order: Dictionary = _orders.get(payload["order_id"], {})
	if order.is_empty() or order["seller"] != actor or order["status"] != "OPEN" or minute >= int(order["expires_minute"]):
		return _result(false, "NOT_OWN_OPEN_SHARE_ORDER")
	_close(order, "CANCELLED", minute, action_id)
	return {"accepted": true, "reason": "ACCEPTED", "order_id": order["id"], "released": order["cancelled"]}

func _close(order: Dictionary, status: String, minute: int, action_id: String = "") -> void:
	var asset := _assets[order["asset_id"]] as Dictionary
	var seller := str(order["seller"])
	asset["reserved"][seller] = int(asset["reserved"][seller]) - int(order["remaining"])
	if int(asset["reserved"][seller]) == 0:
		asset["reserved"].erase(seller)
	order["cancelled"] = order["remaining"]
	order["remaining"] = 0
	order["status"] = status
	order["closed_minute"] = minute
	order["closed_action"] = action_id

func advance_time(minute: int) -> void:
	if call_market.enabled(): call_market.advance_time(minute)
	for expires: int in _expiry.keys():
		if expires > minute:
			continue
		for id: String in _expiry[expires]:
			if _orders[id]["status"] == "OPEN":
				_close(_orders[id], "EXPIRED", expires)
		_expiry.erase(expires)

func _index_expiry(order: Dictionary) -> void:
	if order["status"] != "OPEN":
		return
	var minute := int(order["expires_minute"])
	if not _expiry.has(minute):
		_expiry[minute] = []
	_expiry[minute].append(order["id"])

func _payments(asset: Dictionary, budget: int) -> Dictionary:
	var result: Dictionary = {}
	for holder: String in asset["holders"]:
		if holder == asset["issuer"]:
			continue
		var divided := FormalLedgerState.ratio(budget, int(asset["holders"][holder]), int(asset["total_shares"]))
		if divided.is_empty():
			return {"valid": false}
		if int(divided["quotient"]) > 0:
			result[holder] = int(divided["quotient"])
	return {"valid": true, "amounts": result}

func dividend(actor: String, payload: Dictionary, minute: int, action_id: String) -> Dictionary:
	if call_market.enabled(): return _result(false,"DIVIDENDS_NOT_ENABLED_IN_CALL_EXPERIMENT")
	if not FormalLedgerState.exact_fields(payload, ["asset_id", "budget", "denomination"]) or not payload["asset_id"] is String or not _configured.has(payload["asset_id"]) or not _positive(payload["budget"]) or not FormalLedgerState.currency_id(payload["denomination"]):
		return _result(false, "INVALID_DIVIDEND")
	var spec := _configured[payload["asset_id"]] as Dictionary
	if spec["manager"] != actor:
		return _result(false, "NOT_ISSUER_MANAGER")
	var asset := _assets[payload["asset_id"]] as Dictionary
	var source := _ledger.owner_account(asset["issuer"], payload["denomination"])
	if source.is_empty() or _ledger.available_balance(source) < int(payload["budget"]) or next_dividend >= FormalLedgerState.MAX_AMOUNT:
		return _result(false, "ISSUER_FREE_FUNDS_OR_ID_LIMIT")
	var payments := _payments(asset, int(payload["budget"]))
	if not payments["valid"]:
		return _result(false, "DIVIDEND_AMOUNT_BOUNDS")
	var id := "dividend:" + str(next_dividend)
	var row := {"id": id, "asset_id": payload["asset_id"], "manager": actor, "budget": payload["budget"], "denomination": payload["denomination"], "minute": minute, "payments": payments["amounts"], "total_paid": 0, "action_id": action_id}
	var legs := _dividend_legs(row)
	for amount: int in row["payments"].values():
		row["total_paid"] = int(row["total_paid"]) + amount
	if not _ledger.batch_payment(id, legs, minute):
		return {"accepted": false, "reason": "DIVIDEND_PAYMENT_FAILED", "message": _ledger.error}
	_dividends[id] = row
	next_dividend += 1
	return {"accepted": true, "reason": "ACCEPTED", "dividend_id": id, "total_paid": row["total_paid"], "retained": int(row["budget"]) - int(row["total_paid"])}

func _trade_leg(row: Dictionary) -> Dictionary:
	return {"transaction_id": row["id"], "from_account_id": _ledger.owner_account(row["buyer"], row["denomination"]), "to_account_id": _ledger.owner_account(row["seller"], row["denomination"]), "amount": int(row["quantity"]) * int(row["price"]), "kind": "asset_trade", "reference_id": row["id"]}

func _dividend_legs(row: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var holders: Array = row["payments"].keys()
	holders.sort()
	for holder: String in holders:
		result.append({"transaction_id": str(row["id"]) + ":" + holder, "from_account_id": _ledger.owner_account(_configured[row["asset_id"]]["issuer"], row["denomination"]), "to_account_id": _ledger.owner_account(holder, row["denomination"]), "amount": row["payments"][holder], "kind": "dividend", "reference_id": row["id"]})
	return result

func visible(actor: String, minute: int) -> Dictionary:
	var companies: Array[Dictionary] = []
	var holdings: Array[Dictionary] = []
	for row: Dictionary in _assets.values():
		if _known(actor, row["id"]):
			companies.append({"asset_id": row["id"], "issuer": row["issuer"], "total_shares": row["total_shares"]})
		if int(row["holders"].get(actor, 0)) > 0:
			holdings.append({"asset_id": row["id"], "quantity": row["holders"][actor], "reserved": int(row["reserved"].get(actor, 0))})
	var offers: Array[Dictionary] = []
	var own: Array[Dictionary] = []
	for row: Dictionary in _orders.values():
		if row["seller"] == actor:
			own.append(row.duplicate(true))
		if row["status"] == "OPEN" and minute < int(row["expires_minute"]) and _known(actor, row["asset_id"]):
			var view := row.duplicate(true)
			view.erase("action_id")
			view.erase("closed_action")
			offers.append(view)
	var trades: Array[Dictionary] = []
	for row: Dictionary in _trades.values():
		if row["buyer"] == actor or row["seller"] == actor:
			trades.append(row.duplicate(true))
	var dividends: Array[Dictionary] = []
	for row: Dictionary in _dividends.values():
		if row["manager"] == actor:
			dividends.append(row.duplicate(true))
		elif row["payments"].has(actor):
			dividends.append({"id": row["id"], "asset_id": row["asset_id"], "denomination": row["denomination"], "minute": row["minute"], "received": row["payments"][actor]})
	var result: Dictionary={"companies": companies, "holdings": holdings, "offers": offers, "own_orders": own, "trades": trades, "dividends": dividends}
	if call_market.enabled(): result["call_market"]=call_market.visible(actor,minute)
	if primary.enabled(): result["primary"]=primary.visible(actor)
	if distribution.enabled(): result["distribution"]=distribution.visible(actor)
	return result

func snapshot() -> Dictionary:
	var result: Dictionary={"schema_id": SCHEMA_ID, "assets": _assets.duplicate(true), "orders": _orders.duplicate(true), "trades": _trades.duplicate(true), "dividends": _dividends.duplicate(true), "next_order": next_order, "next_trade": next_trade, "next_dividend": next_dividend}
	if call_market.enabled(): result["call_market"]=call_market.snapshot()
	if primary.enabled(): result["primary"]=primary.snapshot()
	if distribution.enabled(): result["distributions"]=distribution.snapshot()
	return result

func restore(value: Variant, commands: Dictionary, minute: int, native: Dictionary={}) -> bool:
	var root_fields: Array[String]=["schema_id", "assets", "orders", "trades", "dividends", "next_order", "next_trade", "next_dividend"]
	if call_market.enabled():
		root_fields.append("call_market")
	if primary.enabled(): root_fields.append("primary")
	if distribution.enabled(): root_fields.append("distributions")
	if value == null:
		value = {"schema_id": SCHEMA_ID, "assets": {}, "orders": {}, "trades": {}, "dividends": {}, "next_order": 1, "next_trade": 1, "next_dividend": 1}
	if not value is Dictionary or not FormalLedgerState.exact_fields(value, root_fields) or value["schema_id"] != SCHEMA_ID:
		return _fail("Unsupported saved assets")
	for key: String in ["assets", "orders", "trades", "dividends"]:
		if not value[key] is Dictionary:
			return _fail("Invalid asset state container")
	for id: Variant in value["assets"]:
		var asset: Variant = value["assets"][id]
		if not id is String or not _configured.has(id) or not asset is Dictionary or not FormalLedgerState.exact_fields(asset, ["id", "issuer", "total_shares", "holders", "reserved"]) or asset["id"] != id or asset["issuer"] != _configured[id]["issuer"] or not _positive(asset["total_shares"]) or (asset["total_shares"] != _configured[id]["total_shares"] if not primary.enabled() else asset["total_shares"]>int(_configured[id]["total_shares"])+int(primary.config["max_new_shares"])) or not asset["holders"] is Dictionary or not asset["reserved"] is Dictionary:
			return _fail("Invalid finite share registry")
		for field: String in ["holders", "reserved"]:
			for holder: Variant in asset[field]:
				if not holder is String or _ledger.owner_account(holder).is_empty() or not FormalLedgerState.valid_amount(asset[field][holder]):
					return _fail("Invalid share owner or quantity")
	var by_action: Dictionary = {}
	for key: String in ["order", "trade", "dividend"]:
		var collection := "orders" if key == "order" else "trades" if key == "trade" else "dividends"
		var fields: Array[String] = (ORDER_FIELDS if key == "order" else TRADE_FIELDS if key == "trade" else DIVIDEND_FIELDS).duplicate()
		if key=="trade" and call_market.enabled(): fields.append("bid_id")
		if not _positive(value["next_" + key]) or value[collection].size() != int(value["next_" + key]) - 1:
			return _fail("Missing asset settlement IDs")
		for number: int in range(1, int(value["next_" + key])):
			var id := ("dividend:" if key == "dividend" else "asset_" + key + ":") + str(number)
			var row: Variant = value[collection].get(id)
			if not row is Dictionary or not FormalLedgerState.exact_fields(row, fields) or row["id"] != id or not row["action_id"] is String or by_action.has(row["action_id"]) or not _configured.has(row["asset_id"]):
				return _fail("Invalid asset record or duplicate action")
			if not FormalLedgerState.currency_id(row["denomination"]):
				return _fail("Unknown asset settlement currency")
			var amounts: Array[String] = []
			amounts.assign(["quantity", "remaining", "cancelled", "price", "offered_minute", "expires_minute"] if key == "order" else ["quantity", "price", "minute"] if key == "trade" else ["budget", "total_paid", "minute"])
			for field: String in amounts:
				if not FormalLedgerState.valid_amount(row[field]):
					return _fail("Invalid asset amount or date")
			if key == "order" and (typeof(row["closed_minute"]) != TYPE_INT or int(row["closed_minute"]) < -1 or int(row["closed_minute"]) > FormalLedgerState.MAX_AMOUNT or not row["closed_action"] is String or not row["status"] is String):
				return _fail("Invalid share order closure")
			by_action[row["action_id"]] = {"kind": key, "record": row}
	if not primary.validate(value.get("primary"),commands,minute,native): return _fail(primary.error)
	if not distribution.validate(value.get("distributions"),commands,minute,native): return _fail(distribution.error)
	if not corporate.validate(native):return _fail(corporate.error)
	if call_market.enabled():
		if not call_market.validate_history(value,commands,minute,native): return _fail(call_market.error)
		commands=call_market.verification_commands
	# Derive actual ownership from genesis and accepted deliveries in saved action
	# order. This is load reconciliation, and never executes a cash payment.
	var assets := _initial_assets()
	var orders: Dictionary = {}
	var receipts: Dictionary = {}
	var seen: Dictionary = {}
	var cancellations: Dictionary = {}
	var next_ids := {"order": 1, "trade": 1, "dividend": 1}
	var last_minute: int = 0
	for action_id: String in commands:
		var entry := commands[action_id] as Dictionary
		var command := entry["envelope"]["command"] as Dictionary
		var kind := str(command["kind"])
		if kind=="review_corporate_finance":continue # Validated against original facts by corporate policy.
		if kind in Distribution.ACTIONS:
			if entry["result"]["accepted"] and kind=="declare_share_distribution" and not distribution.registration_valid(action_id,assets[distribution.config["asset_id"]]): return _fail(distribution.error)
			continue
		if kind in Primary.ACTIONS:
			if entry["result"]["accepted"] and kind=="settle_share_issue": primary.ownership_effect(action_id,assets,receipts)
			continue
		if kind not in ACTIONS or not entry["result"]["accepted"]:
			continue
		var actor := str(entry["envelope"]["actor"])
		var payload := command["payload"] as Dictionary
		var at := int(command["minute"])
		if at > minute or at < last_minute:
			return _fail("Future financial action")
		last_minute = at
		if kind == "cancel_share_order":
			if not FormalLedgerState.exact_fields(payload, ["order_id"]) or not orders.has(payload["order_id"]):
				return _fail("Share cancellation lacks an order")
			var order := orders[payload["order_id"]] as Dictionary
			if order["seller"] != actor or int(order["remaining"]) <= 0 or at >= int(order["expires_minute"]) or cancellations.has(order["id"]) or entry["result"].get("released") != order["remaining"] or entry["result"].get("order_id") != order["id"]:
				return _fail("Invalid remaining share cancellation")
			order["cancelled"] = order["remaining"]
			order["remaining"] = 0
			order["status"] = "CANCELLED"
			order["closed_minute"] = at
			order["closed_action"] = action_id
			cancellations[order["id"]] = true
			continue
		if not by_action.has(action_id):
			return _fail("Accepted financial action lost its record")
		var row := by_action[action_id]["record"] as Dictionary
		var record_kind := str(by_action[action_id]["kind"])
		var expected_id := ("dividend:" if record_kind == "dividend" else "asset_" + record_kind + ":") + str(next_ids[record_kind])
		if row["id"] != expected_id:
			return _fail("Asset creation order conflicts with saved actions")
		next_ids[record_kind] = int(next_ids[record_kind]) + 1
		var asset := assets[row["asset_id"]] as Dictionary
		seen[action_id] = true
		if kind == "sell_shares":
			if by_action[action_id]["kind"] != "order" or not FormalLedgerState.exact_fields(payload, ["asset_id", "quantity", "price", "denomination", "valid_minutes"]) or not _known(actor, row["asset_id"]) or row["seller"] != actor or payload["asset_id"] != row["asset_id"] or payload["quantity"] != row["quantity"] or payload["price"] != row["price"] or payload["denomination"] != row["denomination"] or not _positive(row["quantity"]) or not _positive(row["price"]) or not _positive(payload["valid_minutes"]) or row["offered_minute"] != at or at > FormalLedgerState.MAX_AMOUNT - int(payload["valid_minutes"]) or row["expires_minute"] != at + int(payload["valid_minutes"]) or int(row["price"]) > FormalLedgerState.MAX_AMOUNT / int(row["quantity"]) or _ledger.owner_account(actor, str(row["denomination"])).is_empty() or entry["result"].get("order_id") != row["id"] or entry["result"].get("quantity") != row["quantity"]:
				return _fail("Saved share offer conditions conflict")
			var reserved: int = 0
			for existing: Dictionary in orders.values():
				if existing["seller"] == actor and existing["asset_id"] == row["asset_id"] and int(existing["expires_minute"]) > at:
					reserved += int(existing["remaining"])
			if int(row["quantity"]) > int(asset["holders"].get(actor, 0)) - reserved:
				return _fail("Share offers exceed owned shares")
			var opened := row.duplicate(true)
			opened.merge({"remaining": row["quantity"], "cancelled": 0, "status": "OPEN", "closed_minute": -1, "closed_action": ""}, true)
			orders[row["id"]] = opened
		elif kind == "accept_share_order":
			if by_action[action_id]["kind"] != "trade" or not FormalLedgerState.exact_fields(payload, ["order_id", "quantity", "max_price", "denomination"]) or not orders.has(row["order_id"]) or not _known(actor, row["asset_id"]) or not _positive(row["quantity"]) or not _positive(payload["max_price"]):
				return _fail("Invalid saved share acceptance")
			var order := orders[row["order_id"]] as Dictionary
			if row["buyer"] != actor or row["seller"] != order["seller"] or row["seller"] == actor or row["asset_id"] != order["asset_id"] or row["price"] != order["price"] or row["denomination"] != order["denomination"] or payload["denomination"] != row["denomination"] or payload["order_id"] != row["order_id"] or payload["quantity"] != row["quantity"] or int(payload["max_price"]) < int(row["price"]) or row["minute"] != at or at < int(order["offered_minute"]) or at >= int(order["expires_minute"]) or int(row["quantity"]) > int(order["remaining"]) or int(row["quantity"]) > int(asset["holders"].get(row["seller"], 0)) or entry["result"].get("trade_id") != row["id"] or entry["result"].get("quantity") != row["quantity"] or entry["result"].get("cash") != int(row["quantity"]) * int(row["price"]):
				return _fail("Share delivery conditions conflict")
			asset["holders"][row["seller"]] = int(asset["holders"][row["seller"]]) - int(row["quantity"])
			asset["holders"][actor] = int(asset["holders"].get(actor, 0)) + int(row["quantity"])
			order["remaining"] = int(order["remaining"]) - int(row["quantity"])
			if int(order["remaining"]) == 0:
				order["status"] = "FILLED"
				order["closed_minute"] = at
			var legs: Array[Dictionary] = [_trade_leg(row)]
			if not _saved_payment(str(row["id"]), legs, at, receipts):
				return false
		elif kind == "pay_dividend":
			if by_action[action_id]["kind"] != "dividend" or not FormalLedgerState.exact_fields(payload, ["asset_id", "budget", "denomination"]) or _configured[row["asset_id"]]["manager"] != actor or row["manager"] != actor or payload["asset_id"] != row["asset_id"] or payload["budget"] != row["budget"] or payload["denomination"] != row["denomination"] or not _positive(row["budget"]) or row["minute"] != at or _ledger.owner_account(asset["issuer"], row["denomination"]).is_empty():
				return _fail("Dividend lacks manager authority")
			var computed := _payments(asset, int(row["budget"]))
			if not computed["valid"] or computed["amounts"] != row["payments"]:
				return _fail("Dividend differs from ownership at acceptance")
			var paid: int = 0
			for amount: int in row["payments"].values():
				paid += amount
			if paid != row["total_paid"] or entry["result"].get("dividend_id") != row["id"] or entry["result"].get("total_paid") != paid or entry["result"].get("retained") != int(row["budget"]) - paid or not _saved_payment(str(row["id"]), _dividend_legs(row), at, receipts):
				return _fail("Dividend cash receipt conflict")
	if seen.size() != by_action.size():
		return _fail("Orphan financial records")
	for row: Dictionary in orders.values():
		if row["status"] == "OPEN" and int(row["expires_minute"]) <= minute:
			row["cancelled"] = row["remaining"]
			row["remaining"] = 0
			row["status"] = "EXPIRED"
			row["closed_minute"] = row["expires_minute"]
		if row["status"] == "OPEN":
			var reserved := assets[row["asset_id"]]["reserved"] as Dictionary
			reserved[row["seller"]] = int(reserved.get(row["seller"], 0)) + int(row["remaining"])
	if orders != value["orders"] or assets != value["assets"]:
		return _fail("Saved ownership or share reservations conflict")
	distribution.explain_payments(receipts)
	for row: Dictionary in _ledger.transactions():
		if row["kind"] in ["asset_trade", "dividend", "equity_issue"] and not receipts.has(row["transaction_id"]):
			return _fail("Unexplained asset cash payment")
	_assets = assets
	_orders = orders
	_trades = value["trades"].duplicate(true)
	_dividends = value["dividends"].duplicate(true)
	next_order = int(value["next_order"])
	next_trade = int(value["next_trade"])
	next_dividend = int(value["next_dividend"])
	_expiry.clear()
	for row: Dictionary in _orders.values():
		_index_expiry(row)
	return true

func _saved_payment(id: String, legs: Array[Dictionary], minute: int, receipts: Dictionary) -> bool:
	var ids: Array[String] = []
	for leg: Dictionary in legs:
		var expected := leg.duplicate(true)
		expected.merge({"denomination": _ledger.account(leg["from_account_id"]).get("denomination"), "effective_minute": minute, "basis": "GENERATED_SIMULATION_ASSUMPTION"})
		if _ledger.transaction(leg["transaction_id"]) != expected or receipts.has(leg["transaction_id"]):
			return _fail("Asset payment differs from Ledger")
		receipts[leg["transaction_id"]] = true
		ids.append(leg["transaction_id"])
	if _ledger.payment_batch(id) != {"transactions": ids, "releases": call_market.trade_releases.get(id,{}), "minute": minute}:
		return _fail("Asset payment lacks atomic settlement")
	return true

static func _positive(value: Variant) -> bool:
	return FormalLedgerState.valid_amount(value) and int(value) > 0

static func _result(accepted: bool, reason: String) -> Dictionary:
	return {"accepted": accepted, "reason": reason}

func _fail(message: String) -> bool:
	error = message
	return false
