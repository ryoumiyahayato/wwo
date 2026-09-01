class_name VNextOrganizationKindCatalog
extends RefCounted

## Controlled organization taxonomy. State/polity and military formations are
## intentionally absent because their identities belong to other domains.

const _KIND_IDS: Array[String] = [
	"association",
	"company",
	"corporation",
	"enterprise",
	"faction",
	"government_body",
	"guild",
	"military_institution",
	"party",
	"union",
]


static func ids() -> Array[String]:
	return _KIND_IDS.duplicate()


static func is_known(organization_kind: String) -> bool:
	return _KIND_IDS.has(organization_kind)


static func fingerprint() -> String:
	return JSON.stringify(_KIND_IDS).sha256_text()
