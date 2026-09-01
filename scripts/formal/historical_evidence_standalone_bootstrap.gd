class_name HistoricalEvidenceStandaloneBootstrap
extends RefCounted
## Builds a detached, immutable historical-political evidence candidate for
## standalone presentation surfaces. This boundary never creates runtime polity
## authority and never falls back to unadmitted source data.


static func build(
	provenance_gate: HistoricalProvenanceGate = null
) -> Dictionary:
	var foundation: HistoricalProvenanceFoundation = null
	var gate := provenance_gate
	if gate == null:
		foundation = HistoricalProvenanceFoundation.new()
		if not foundation.load_current():
			return {
				"success": false,
				"error": foundation.initialization_error,
			}
		gate = foundation.gate()

	var catalog := HistoricalPoliticalEvidenceCatalog.new()
	if not catalog.configure(
		HistoricalPoliticalEvidenceCatalog.DEFAULT_PATH,
		gate
	):
		return {
			"success": false,
			"error": catalog.initialization_error,
		}
	var records := catalog.records()
	if records.size() != HistoricalPoliticalEvidenceCatalog.EXPECTED_RECORD_COUNT:
		return {
			"success": false,
			"error": "历史政治证据 bootstrap 数量错误：%d" % records.size(),
		}
	return {
		"success": true,
		"error": "",
		"foundation": foundation,
		"gate": gate,
		"records": records,
	}
