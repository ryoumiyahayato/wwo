class_name AlphaAssetService
extends RefCounted
## Unified Alpha ownership/control registry for cash references and non-cash assets.

const ASSET_TYPES: Array[String] = [
	"cash",
	"claim",
	"enterprise_equity",
	"real_estate",
	"land",
	"equipment",
	"inventory",
	"vehicle",
	"mortgage_right",
	"valuable_contract",
]

var assets: Dictionary = {}
var _next_sequence: int = 1
var _processed_keys: Dictionary = {}
var _ledger: AlphaLedgerService


func configure(ledger: AlphaLedgerService) -> void:
	assets.clear()
	_processed_keys.clear()
	_next_sequence = 1
	_ledger = ledger


func register_cash_asset(owner_id: String) -> Dictionary:
	if _ledger == null:
		return _fail("ledger_missing", "资产服务尚未连接正式账本")
	var account_id: String = _ledger.cash_account_id(owner_id)
	if account_id.is_empty():
		return _fail("account_missing", "现金资产必须引用正式现金账户")
	var asset_id: String = "asset:cash:%s" % owner_id
	if assets.has(asset_id):
		return _ok({"asset": (assets[asset_id] as Dictionary).duplicate(true)})
	return create_asset(
		"asset:register_cash:%s" % owner_id,
		"cash",
		owner_id,
		owner_id,
		0,
		{"account_id": account_id, "liquidity": "cash"},
		asset_id
	)


func create_asset(
	idempotency_key: String,
	asset_type: String,
	owner_id: String,
	controller_id: String,
	value_centimes: int,
	attributes: Dictionary = {},
	requested_id: String = ""
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		var existing_id: String = str(_processed_keys[idempotency_key])
		return _ok({
			"asset": (assets.get(existing_id, {}) as Dictionary).duplicate(true),
			"duplicate": true,
		})
	if (
		idempotency_key.is_empty()
		or asset_type not in ASSET_TYPES
		or owner_id.is_empty()
		or controller_id.is_empty()
		or value_centimes < 0
	):
		return _fail("invalid_asset", "资产类型、所有者、控制者或价值无效")
	var asset_id: String = requested_id
	if asset_id.is_empty():
		asset_id = "asset:alpha:%d" % _next_sequence
	if assets.has(asset_id):
		return _fail("asset_conflict", "资产 ID 已存在")
	var asset: Dictionary = {
		"asset_id": asset_id,
		"asset_type": asset_type,
		"owner_shares_bp": {owner_id: 10000},
		"controller_id": controller_id,
		"value_centimes": value_centimes,
		"condition_bp": 10000,
		"status": "active",
		"mortgage_contract_ids": [],
		"lease_contract_id": "",
		"attributes": attributes.duplicate(true),
		"history": [{
			"event": "created",
			"owner_id": owner_id,
			"idempotency_key": idempotency_key,
		}],
	}
	_next_sequence += 1
	assets[asset_id] = asset
	_processed_keys[idempotency_key] = asset_id
	return _ok({"asset": asset.duplicate(true), "duplicate": false})


func value(asset_id: String) -> int:
	var asset: Dictionary = assets.get(asset_id, {}) as Dictionary
	if str(asset.get("asset_type", "")) == "cash" and _ledger != null:
		var attributes: Dictionary = asset.get("attributes", {}) as Dictionary
		return _ledger.balance(str(attributes.get("account_id", "")))
	return int(asset.get("value_centimes", 0))


func owner_share(asset_id: String, owner_id: String) -> int:
	var asset: Dictionary = assets.get(asset_id, {}) as Dictionary
	var shares: Dictionary = asset.get("owner_shares_bp", {}) as Dictionary
	return int(shares.get(owner_id, 0))


func update_contract_value(
	idempotency_key: String, asset_id: String, contract_id: String, value_centimes: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"asset": (assets.get(asset_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var asset: Dictionary = assets.get(asset_id, {}) as Dictionary
	var attributes: Dictionary = asset.get("attributes", {}) as Dictionary
	if (
		asset.is_empty()
		or str(asset.get("asset_type", "")) not in ["claim", "mortgage_right", "valuable_contract"]
		or str(attributes.get("contract_id", "")) != contract_id
		or value_centimes < 0
	):
		return _fail("invalid_contract_asset", "合同资产价值更新引用无效")
	asset["value_centimes"] = value_centimes
	if value_centimes == 0:
		asset["status"] = "fulfilled"
	_append_history(asset, "contract_value_updated", idempotency_key, {
		"contract_id": contract_id,
		"value_centimes": value_centimes,
	})
	assets[asset_id] = asset
	_processed_keys[idempotency_key] = asset_id
	return _ok({"asset": asset.duplicate(true)})


func transfer_share(
	idempotency_key: String,
	asset_id: String,
	from_owner_id: String,
	to_owner_id: String,
	share_bp: int,
	new_controller_id: String = ""
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"asset": (assets.get(asset_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var asset: Dictionary = assets.get(asset_id, {}) as Dictionary
	var shares: Dictionary = asset.get("owner_shares_bp", {}) as Dictionary
	if (
		asset.is_empty()
		or str(asset.get("status", "")) not in ["active", "leased", "mortgaged"]
		or from_owner_id == to_owner_id
		or share_bp <= 0
		or int(shares.get(from_owner_id, 0)) < share_bp
	):
		return _fail("invalid_transfer", "资产份额转让条件不成立")
	shares[from_owner_id] = int(shares[from_owner_id]) - share_bp
	if int(shares[from_owner_id]) == 0:
		shares.erase(from_owner_id)
	shares[to_owner_id] = int(shares.get(to_owner_id, 0)) + share_bp
	asset["owner_shares_bp"] = shares
	if not new_controller_id.is_empty():
		asset["controller_id"] = new_controller_id
	_append_history(asset, "ownership_transferred", idempotency_key, {
		"from_owner_id": from_owner_id,
		"to_owner_id": to_owner_id,
		"share_bp": share_bp,
	})
	assets[asset_id] = asset
	_processed_keys[idempotency_key] = asset_id
	return _ok({"asset": asset.duplicate(true), "duplicate": false})


func sell(
	idempotency_key: String,
	total_hour: int,
	asset_id: String,
	seller_id: String,
	buyer_id: String,
	price_centimes: int,
	share_bp: int = 10000
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"asset": (assets.get(asset_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	if _ledger == null or price_centimes < 0:
		return _fail("invalid_sale", "资产出售缺少账本或价格无效")
	var payment: Dictionary = _ledger.transfer(
		"ledger:%s" % idempotency_key,
		total_hour,
		buyer_id,
		seller_id,
		price_centimes,
		"asset_sale",
		"fact:%s" % idempotency_key,
		"资产出售"
	)
	if not bool(payment.get("success", false)):
		return payment
	var transfer: Dictionary = transfer_share(
		idempotency_key, asset_id, seller_id, buyer_id, share_bp, buyer_id
	)
	if not bool(transfer.get("success", false)):
		return _fail("post_payment_transfer_failed", "资产付款后所有权转让失败")
	return transfer


func mortgage(
	idempotency_key: String, asset_id: String, contract_id: String, creditor_id: String
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"asset": (assets.get(asset_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var asset: Dictionary = assets.get(asset_id, {}) as Dictionary
	if asset.is_empty() or contract_id.is_empty() or creditor_id.is_empty():
		return _fail("invalid_mortgage", "抵押必须引用资产、借款合同和债权人")
	var mortgages: Array = asset.get("mortgage_contract_ids", []) as Array
	if contract_id not in mortgages:
		mortgages.append(contract_id)
	asset["mortgage_contract_ids"] = mortgages
	asset["status"] = "mortgaged"
	var attributes: Dictionary = asset.get("attributes", {}) as Dictionary
	attributes["mortgage_creditor_id"] = creditor_id
	asset["attributes"] = attributes
	_append_history(asset, "mortgaged", idempotency_key, {"contract_id": contract_id})
	assets[asset_id] = asset
	_processed_keys[idempotency_key] = asset_id
	return _ok({"asset": asset.duplicate(true)})


func lease(
	idempotency_key: String, asset_id: String, contract_id: String, controller_id: String
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"asset": (assets.get(asset_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var asset: Dictionary = assets.get(asset_id, {}) as Dictionary
	if asset.is_empty() or contract_id.is_empty() or controller_id.is_empty():
		return _fail("invalid_lease", "租赁必须引用资产、合同和实际控制者")
	asset["lease_contract_id"] = contract_id
	asset["controller_id"] = controller_id
	asset["status"] = "leased"
	_append_history(asset, "leased", idempotency_key, {"contract_id": contract_id})
	assets[asset_id] = asset
	_processed_keys[idempotency_key] = asset_id
	return _ok({"asset": asset.duplicate(true)})


func depreciate(
	idempotency_key: String, asset_id: String, depreciation_bp: int
) -> Dictionary:
	return _reduce_condition_and_value(
		idempotency_key, asset_id, depreciation_bp, "depreciated"
	)


func damage(idempotency_key: String, asset_id: String, damage_bp: int) -> Dictionary:
	return _reduce_condition_and_value(idempotency_key, asset_id, damage_bp, "damaged")


func confiscate(
	idempotency_key: String, asset_id: String, authority_id: String
) -> Dictionary:
	var asset: Dictionary = assets.get(asset_id, {}) as Dictionary
	if asset.is_empty():
		return _fail("asset_missing", "待没收资产不存在")
	var shares: Dictionary = asset.get("owner_shares_bp", {}) as Dictionary
	var prior_owners: Array = shares.keys()
	asset["owner_shares_bp"] = {authority_id: 10000}
	asset["controller_id"] = authority_id
	asset["status"] = "confiscated"
	_append_history(asset, "confiscated", idempotency_key, {"prior_owners": prior_owners})
	assets[asset_id] = asset
	_processed_keys[idempotency_key] = asset_id
	return _ok({"asset": asset.duplicate(true)})


func dispose_in_bankruptcy(
	idempotency_key: String, asset_id: String, creditor_id: String
) -> Dictionary:
	var result: Dictionary = confiscate(idempotency_key, asset_id, creditor_id)
	if bool(result.get("success", false)):
		var asset: Dictionary = assets[asset_id] as Dictionary
		asset["status"] = "bankruptcy_disposed"
		assets[asset_id] = asset
		result["data"] = {"asset": asset.duplicate(true)}
	return result


func close_asset(idempotency_key: String, asset_id: String, reason: String) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"asset": (assets.get(asset_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var asset: Dictionary = assets.get(asset_id, {}) as Dictionary
	if asset.is_empty() or str(asset.get("asset_type", "")) == "cash":
		return _fail("invalid_close", "现金账户资产不能由普通生命周期关闭")
	asset["status"] = "closed"
	asset["controller_id"] = ""
	_append_history(asset, "closed", idempotency_key, {"reason": reason})
	assets[asset_id] = asset
	_processed_keys[idempotency_key] = asset_id
	return _ok({"asset": asset.duplicate(true)})


func validate_references() -> Dictionary:
	for raw_asset: Variant in assets.values():
		var asset: Dictionary = raw_asset as Dictionary
		var shares: Dictionary = asset.get("owner_shares_bp", {}) as Dictionary
		var total_shares: int = 0
		for raw_share: Variant in shares.values():
			total_shares += int(raw_share)
		if total_shares != 10000:
			return _fail("asset_share_mismatch", "资产所有权份额不闭合")
		if str(asset.get("asset_type", "")) == "cash":
			var attributes: Dictionary = asset.get("attributes", {}) as Dictionary
			if _ledger == null or not _ledger.accounts.has(str(attributes.get("account_id", ""))):
				return _fail("cash_reference_missing", "现金资产未引用正式账本账户")
	return _ok({"asset_count": assets.size()})


func get_persistent_state() -> Dictionary:
	return {
		"assets": assets.duplicate(true),
		"processed_keys": _processed_keys.duplicate(true),
		"next_sequence": _next_sequence,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("assets", {}) is Dictionary
		or not state.get("processed_keys", {}) is Dictionary
	):
		return false
	assets = (state["assets"] as Dictionary).duplicate(true)
	_processed_keys = (state["processed_keys"] as Dictionary).duplicate(true)
	_next_sequence = int(state.get("next_sequence", 0))
	return _next_sequence >= 1 and bool(validate_references().get("success", false))


func _reduce_condition_and_value(
	idempotency_key: String, asset_id: String, reduction_bp: int, event_name: String
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"asset": (assets.get(asset_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var asset: Dictionary = assets.get(asset_id, {}) as Dictionary
	if asset.is_empty() or reduction_bp <= 0 or reduction_bp > 10000:
		return _fail("invalid_asset_change", "资产损坏或贬值比例无效")
	asset["condition_bp"] = maxi(0, int(asset.get("condition_bp", 10000)) - reduction_bp)
	asset["value_centimes"] = (
		int(asset.get("value_centimes", 0)) * (10000 - reduction_bp) / 10000
	)
	if int(asset["condition_bp"]) == 0:
		asset["status"] = "destroyed"
	_append_history(asset, event_name, idempotency_key, {"reduction_bp": reduction_bp})
	assets[asset_id] = asset
	_processed_keys[idempotency_key] = asset_id
	return _ok({"asset": asset.duplicate(true)})


static func _append_history(
	asset: Dictionary, event_name: String, idempotency_key: String, details: Dictionary
) -> void:
	var history: Array = asset.get("history", []) as Array
	history.append({
		"event": event_name,
		"idempotency_key": idempotency_key,
		"details": details.duplicate(true),
	})
	while history.size() > 24:
		history.pop_front()
	asset["history"] = history


static func _ok(data: Dictionary = {}) -> Dictionary:
	return {"success": true, "code": "ok", "message": "", "data": data}


static func _fail(code: String, message: String) -> Dictionary:
	return {"success": false, "code": code, "message": message, "data": {}}
