class_name OrganizationPage
extends RefCounted
var _rows: Array[Dictionary] = []
var _by_id: Dictionary = {}
var _memberships: Array[Dictionary] = []
var _own_rows: Array[Dictionary] = []
var selected_id: String = ""
var page: int = 0
var own_only: bool = false
var country_id: String = ""
const PAGE_SIZE: int = 9

func refresh(rows: Array[Dictionary], memberships: Array[Dictionary]) -> void:
	_rows = rows
	_memberships = memberships
	_by_id.clear()
	_own_rows.clear()
	for row: Dictionary in rows:
		_by_id[str(row.organization_id)] = row
		if row.has("player_roles"): _own_rows.append(row)
	if not selected_id.is_empty() and not _by_id.has(selected_id): selected_id = ""

func _records() -> Array[Dictionary]:
	if own_only: return _own_rows
	if country_id.is_empty(): return _rows
	var result: Array[Dictionary] = []
	for row: Dictionary in _rows:
		if str(row.get("country_id",""))==country_id: result.append(row)
	# Actual child references retain their known national ancestry.
	var changed := true
	while changed:
		changed = false
		for row: Dictionary in _rows:
			if row in result: continue
			if not str(row.get("country_id","")).is_empty() and str(row.country_id)!=country_id: continue
			for parent: Dictionary in result.duplicate():
				if str(row.get("parent_organization_id",""))==str(parent.organization_id):
					result.append(row)
					changed = true
					break
	return result

func draw(shell: MainShell, rect: Rect2) -> void:
	var records := _records()
	if not selected_id.is_empty() and _by_id.has(selected_id):
		_draw_detail(shell,rect,_by_id[selected_id] as Dictionary)
		return
	var title := "人物组织关系" if own_only else "组织架构" if not country_id.is_empty() else "组织词条"
	shell.heading(rect,title,"")
	if records.is_empty():
		shell.label(rect.position+Vector2(22,120),"暂无成员或任职记录。" if own_only else "暂无明确关联的组织资料。",13)
		return
	var positions: Dictionary = {}
	var depth_by_id: Dictionary = {}
	var ids: Dictionary = {}
	for row: Dictionary in records: ids[str(row.organization_id)] = true
	var has_edges := false
	for row: Dictionary in records:
		var depth := 0
		var parent := str(row.get("parent_organization_id",""))
		var visited: Dictionary = {str(row.organization_id):true}
		while ids.has(parent) and not visited.has(parent):
			has_edges = true
			visited[parent] = true
			depth += 1
			parent = str((_by_id[parent] as Dictionary).get("parent_organization_id",""))
		depth_by_id[str(row.organization_id)] = depth
	records.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(depth_by_id[str(a.organization_id)]) < int(depth_by_id[str(b.organization_id)]) if int(depth_by_id[str(a.organization_id)])!=int(depth_by_id[str(b.organization_id)]) else str(a.label)<str(b.label))
	var count := mini(PAGE_SIZE,maxi(1,int((rect.size.y-160)/66)))
	page = clampi(page,0,maxi(0,(records.size()-1)/count))
	var visible := records.slice(page*count,mini(records.size(),(page+1)*count))
	var rows_by_depth: Dictionary = {}
	var max_depth := 0
	for row: Dictionary in visible:
		var depth := int(depth_by_id[str(row.organization_id)])
		max_depth = maxi(max_depth,depth)
		if not rows_by_depth.has(depth): rows_by_depth[depth] = []
		(rows_by_depth[depth] as Array).append(row)
	var top := rect.position.y+112
	var lane := 0
	for depth: int in rows_by_depth:
		var row_nodes := rows_by_depth[depth] as Array
		var cols := mini(3,row_nodes.size())
		var col_width := (rect.size.x-44)/cols
		for index: int in range(row_nodes.size()):
			var row := row_nodes[index] as Dictionary
			positions[str(row.organization_id)] = Rect2(rect.position.x+22+(index%cols)*col_width,top+(lane+index/cols)*66,minf(270,col_width-12),42)
		lane += int(ceil(float(row_nodes.size())/cols))
	for row: Dictionary in visible:
		var parent := str(row.get("parent_organization_id",""))
		if not positions.has(parent): continue
		var source := positions[parent] as Rect2
		var target := positions[str(row.organization_id)] as Rect2
		shell.draw_polyline(PackedVector2Array([Vector2(source.get_center().x,source.end.y),Vector2(source.get_center().x,target.position.y-10),Vector2(target.get_center().x,target.position.y-10),Vector2(target.get_center().x,target.position.y)]),Color(0.68,0.60,0.39,0.65),1.5,true)
	for row: Dictionary in visible:
		var node := positions[str(row.organization_id)] as Rect2
		shell.button(node,str(row.label),"organization:open:"+str(row.organization_id))
	if not has_edges and not own_only:
		shell.label(Vector2(rect.position.x+22,rect.end.y-58),"暂无完整机构层级资料。",11,Color(0.75,0.79,0.72))
	if page>0 or records.size()>count:
		shell.button(Rect2(rect.position.x+20,rect.end.y-35,82,25),"上一页","organization:previous",page>0)
		shell.button(Rect2(rect.position.x+112,rect.end.y-35,82,25),"下一页","organization:next",(page+1)*count<records.size())

func _draw_detail(shell: MainShell, rect: Rect2, row: Dictionary) -> void:
	shell.heading(rect,str(row.label),str(row.get("kind_label","")))
	var facts: Array[String] = ["类型："+str(row.get("kind_label","未记录"))]
	if not str(row.get("place_name","")).is_empty(): facts.append("所在地："+str(row.place_name))
	if row.has("player_roles"): facts.append("人物关系："+str(row.player_roles))
	if row.has("member_ids"): facts.append("实际成员："+str((row.member_ids as Array).size()))
	if row.has("positions"): facts.append("已记录职务："+str((row.positions as Array).size()))
	facts.append("资料依据："+str(row.get("basis_label","未记录")))
	shell.lines(rect.position+Vector2(22,118),facts,rect.size.x*0.52-30)
	shell.wrapped(rect.position+Vector2(rect.size.x*0.54,118),str(row.get("case_text","")),rect.size.x*0.46-22,12,4)
	if not str(row.get("place_id","")).is_empty(): shell.button(Rect2(rect.position.x+22,rect.end.y-35,112,25),"所在地资料","place:open:"+str(row.place_id))
	var parent := str(row.get("parent_organization_id",""))
	for candidate: Dictionary in _records():
		if str(candidate.organization_id)==parent:
			shell.button(Rect2(rect.end.x-148,rect.end.y-35,126,25),"上级机构","organization:open:"+parent)
			break

func record_count() -> int:
	return _records().size()
