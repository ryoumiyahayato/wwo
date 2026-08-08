extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_owner_validation()
	_test_credit_and_debit()
	_test_failed_amounts_are_transactional()
	_test_insufficient_funds_are_transactional()
	_test_snapshot_round_trip()
	_test_json_round_trip()
	_test_restore_rejections_are_transactional()
	_test_large_integer_balance()
	print("VNext personal economy: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_owner_validation() -> void:
	var wallet := VNextPersonalWallet.create("person:player_one")
	_check(wallet != null, "valid person stable ID creates a wallet")
	if wallet != null:
		_equal(wallet.owner_id(), "person:player_one", "wallet owns the person stable ID")
		_equal(wallet.balance_minor(), 0, "new wallet starts with zero balance")
		_equal(typeof(wallet.balance_minor()), TYPE_INT, "wallet balance is an int")

	_check(
		VNextPersonalWallet.create("place:player_one") == null,
		"place stable ID is rejected as a wallet owner"
	)
	_check(
		VNextPersonalWallet.create("organization:player_one") == null,
		"organization stable ID is rejected as a wallet owner"
	)
	_check(
		VNextPersonalWallet.create("person:PlayerOne") == null,
		"invalid person stable ID is rejected as a wallet owner"
	)


func _test_credit_and_debit() -> void:
	var wallet := VNextPersonalWallet.create("person:cash_flow")
	_check(wallet.credit(2500), "positive credit succeeds")
	_equal(wallet.balance_minor(), 2500, "credit increases balance")
	_check(wallet.can_debit(1000), "available balance can be debited")
	_check(wallet.debit(1000), "positive debit with sufficient balance succeeds")
	_equal(wallet.balance_minor(), 1500, "debit decreases balance")
	_equal(typeof(wallet.balance_minor()), TYPE_INT, "credit and debit keep integer balance")


func _test_failed_amounts_are_transactional() -> void:
	var wallet := VNextPersonalWallet.create("person:invalid_amounts")
	_check(wallet.credit(500), "invalid-amount fixture can be funded")
	_expect_credit_failure(wallet, 0, "zero credit")
	_expect_credit_failure(wallet, -1, "negative credit")
	_expect_debit_failure(wallet, 0, "zero debit")
	_expect_debit_failure(wallet, -1, "negative debit")
	_check(not wallet.can_debit(0), "zero amount cannot be debited")
	_check(not wallet.can_debit(-1), "negative amount cannot be debited")


func _test_insufficient_funds_are_transactional() -> void:
	var wallet := VNextPersonalWallet.create("person:insufficient")
	_check(wallet.credit(300), "insufficient-funds fixture can be funded")
	_check(not wallet.can_debit(301), "can_debit rejects insufficient funds")
	_expect_debit_failure(wallet, 301, "insufficient funds")
	_equal(wallet.balance_minor(), 300, "insufficient-funds rejection preserves balance")


func _test_snapshot_round_trip() -> void:
	var source := VNextPersonalWallet.create("person:snapshot_source")
	_check(source.credit(123456), "snapshot source can be funded")
	var saved: Dictionary = source.snapshot()
	_equal(saved.size(), 3, "wallet snapshot contains exactly three fields")
	_equal(saved.get("schema_id"), "vnext_personal_wallet_v1", "wallet snapshot schema is correct")
	_equal(saved.get("owner_person_id"), "person:snapshot_source", "snapshot stores owner person ID")
	_equal(saved.get("balance_minor"), 123456, "snapshot stores balance in minor units")
	_equal(typeof(saved.get("balance_minor")), TYPE_INT, "snapshot balance is an int")

	var restored := VNextPersonalWallet.create("person:restore_target")
	_check(restored.restore(saved), "valid wallet snapshot restore succeeds")
	_equal(restored.snapshot(), saved, "snapshot round trip preserves complete wallet state")


func _test_json_round_trip() -> void:
	var source := VNextPersonalWallet.create("person:json_source")
	_check(source.credit(9000000000000), "JSON fixture accepts a large integer balance")
	var source_snapshot: Dictionary = source.snapshot()
	var serialized: String = JSON.stringify(source_snapshot)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(serialized)
	_equal(parse_error, OK, "wallet snapshot survives JSON serialization")
	if parse_error != OK:
		return
	var parsed_value: Variant = parser.data
	_check(typeof(parsed_value) == TYPE_DICTIONARY, "JSON parser returns wallet snapshot dictionary")
	if typeof(parsed_value) != TYPE_DICTIONARY:
		return
	var parsed_snapshot: Dictionary = parsed_value
	_equal(
		typeof(parsed_snapshot.get("balance_minor")),
		TYPE_FLOAT,
		"Godot JSON boundary exposes numeric balance as transport float"
	)

	var restored := VNextPersonalWallet.create("person:json_target")
	_check(restored.restore(parsed_snapshot), "JSON-parsed wallet snapshot restore succeeds")
	_equal(restored.snapshot(), source_snapshot, "JSON round trip preserves complete wallet state")
	_equal(typeof(restored.balance_minor()), TYPE_INT, "JSON restore normalizes balance back to int")


func _test_restore_rejections_are_transactional() -> void:
	var wallet := VNextPersonalWallet.create("person:restore_guard")
	_check(wallet.credit(700), "restore rejection fixture can be funded")
	_expect_restore_failure(
		wallet,
		{"schema_id": "vnext_personal_wallet_v0", "owner_person_id": "person:other", "balance_minor": 1},
		"wrong schema"
	)
	_expect_restore_failure(
		wallet,
		{"schema_id": "vnext_personal_wallet_v1", "owner_person_id": "place:other", "balance_minor": 1},
		"non-person owner"
	)
	_expect_restore_failure(
		wallet,
		{"schema_id": "vnext_personal_wallet_v1", "owner_person_id": "person:other"},
		"missing balance"
	)
	_expect_restore_failure(
		wallet,
		{"schema_id": "vnext_personal_wallet_v1", "owner_person_id": "person:other", "balance_minor": "700"},
		"string balance"
	)
	_expect_restore_failure(
		wallet,
		{"schema_id": "vnext_personal_wallet_v1", "owner_person_id": "person:other", "balance_minor": -1},
		"negative balance"
	)
	_expect_restore_failure(
		wallet,
		{"schema_id": "vnext_personal_wallet_v1", "owner_person_id": "person:other", "balance_minor": 1.5},
		"fractional balance"
	)
	_expect_restore_failure(
		wallet,
		{"schema_id": "vnext_personal_wallet_v1", "owner_person_id": "person:other", "balance_minor": INF},
		"infinite balance"
	)
	_expect_restore_failure(
		wallet,
		{"schema_id": "vnext_personal_wallet_v1", "owner_person_id": "person:other", "balance_minor": VNextPersonalWallet.MAX_BALANCE_MINOR + 1},
		"balance above JSON-safe range"
	)


func _test_large_integer_balance() -> void:
	var wallet := VNextPersonalWallet.create("person:large_balance")
	var large_amount: int = 4_000_000_000_000_000
	_check(wallet.credit(large_amount), "large integer credit succeeds")
	_equal(wallet.balance_minor(), large_amount, "large balance is preserved exactly")
	_equal(typeof(wallet.balance_minor()), TYPE_INT, "large balance remains an int")
	_check(wallet.debit(1), "large integer balance can be debited")
	_equal(wallet.balance_minor(), large_amount - 1, "large debit remains exact")

	var max_wallet := VNextPersonalWallet.create("person:max_balance")
	_check(max_wallet.credit(VNextPersonalWallet.MAX_BALANCE_MINOR), "maximum JSON-safe integer balance succeeds")
	_expect_credit_failure(max_wallet, 1, "credit overflow beyond JSON-safe integer range")


func _expect_credit_failure(
	wallet: VNextPersonalWallet, amount_minor: int, label: String
) -> void:
	var before: Dictionary = wallet.snapshot()
	_check(not wallet.credit(amount_minor), "%s is rejected" % label)
	_equal(wallet.snapshot(), before, "%s leaves wallet state unchanged" % label)


func _expect_debit_failure(
	wallet: VNextPersonalWallet, amount_minor: int, label: String
) -> void:
	var before: Dictionary = wallet.snapshot()
	_check(not wallet.debit(amount_minor), "%s is rejected" % label)
	_equal(wallet.snapshot(), before, "%s leaves wallet state unchanged" % label)


func _expect_restore_failure(
	wallet: VNextPersonalWallet, rejected: Dictionary, label: String
) -> void:
	var before: Dictionary = wallet.snapshot()
	_check(not wallet.restore(rejected), "%s restore is rejected" % label)
	_equal(wallet.snapshot(), before, "%s restore rejection is transactional" % label)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
