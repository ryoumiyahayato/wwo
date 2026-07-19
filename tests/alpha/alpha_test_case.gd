class_name AlphaTestCase
extends RefCounted

var checks: int = 0
var failures: int = 0


func expect(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)


func equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual == expected:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s（实际 %s，预期 %s）" % [label, actual, expected])


func finish(tree: SceneTree, suite: String) -> void:
	print("%s: %d checks, %d failures" % [suite, checks, failures])
	tree.quit(0 if failures == 0 else 1)
