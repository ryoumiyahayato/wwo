class_name OrganizationPage
extends RefCounted

var _rows: Array[Dictionary] = []
var _memberships: Array[Dictionary] = []
var page: int = 0
const PAGE_SIZE: int = 10

func refresh(organizations: FormalWorldOrganizationView, evidence: FormalWorldOrganizationEvidenceView, responsibilities: FormalWorldOrganizationResponsibilityView, person_id: String) -> void:
	_rows.clear()
	_memberships = organizations.memberships_for_person(person_id)
	for organization_id: String in organizations.organization_ids():
		var row := organizations.organization(organization_id)
		row["represented_polity_id"] = evidence.represented_polity_id(organization_id)
		row["responsibility_status"] = responsibilities.responsibility_status(organization_id)
		_rows.append(row)
	page = clampi(page, 0, maxi(0, int(ceil(float(_rows.size()) / PAGE_SIZE)) - 1))

func draw(shell: MainShell, rect: Rect2) -> void:
	shell.heading(rect, "组织", "当前组织记录与人物成员关系")
	var y := rect.position.y + 122.0
	shell.label(Vector2(rect.position.x + 30.0, y), "人物组织记录 %d    当前组织 %d" % [_memberships.size(), _rows.size()], 13)
	y += 36.0
	for index: int in range(page * PAGE_SIZE, mini(_rows.size(), (page + 1) * PAGE_SIZE)):
		if y > rect.end.y - 62.0:
			break
		var row := _rows[index]
		var row_rect := Rect2(rect.position.x + 28.0, y - 17.0, rect.size.x - 56.0, 30.0)
		shell.panel(row_rect, Color(0.033, 0.057, 0.059, 0.90), Color(0.28, 0.39, 0.35, 0.25))
		shell.label(Vector2(row_rect.position.x + 12.0, y + 3.0), str(row.get("organization_id", "")), 10, Color(0.88, 0.89, 0.81), row_rect.size.x * 0.52)
		shell.label(Vector2(rect.position.x + rect.size.x * 0.55, y + 3.0), "%s  ·  %s  ·  %s" % [str(row.get("organization_kind", "")), "有效" if bool(row.get("active", false)) else "非活跃", str(row.get("responsibility_status", ""))], 10)
		y += 34.0
	shell.button(Rect2(rect.position.x + 28.0, rect.end.y - 40.0, 82.0, 26.0), "上一页", "organization:previous", page > 0)
	shell.label(Vector2(rect.position.x + 128.0, rect.end.y - 22.0), str(page + 1), 12)
	shell.button(Rect2(rect.position.x + 168.0, rect.end.y - 40.0, 82.0, 26.0), "下一页", "organization:next", (page + 1) * PAGE_SIZE < _rows.size())
