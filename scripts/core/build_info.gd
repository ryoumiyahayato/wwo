class_name BuildInfo
extends RefCounted
## Single source of truth for the product name and visible build identity.

const GAME_NAME: String = "1900"
const BASE_VERSION: String = "v0.001a"
const BUILD_CODE: String = "dev"


static func display_version() -> String:
	return "%s (%s)" % [BASE_VERSION, BUILD_CODE]


static func window_title() -> String:
	return "%s · %s" % [GAME_NAME, display_version()]
