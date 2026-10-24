extends RefCounted
## One metre frame. Tile membership is half-open; selecting a view never moves actors.
const REGION_ID := "training:cedar-rivergate-ridgevale:50km"
const EXTENT := 50000.0
const TILE := 5000.0
const ACTIVE := "ridgevale_c1"
const CENTER := Vector2(22500, 22500)
var tiles: Array[Dictionary] = [
	{"id":"ridgevale_c1", "name":"Ridgevale C1", "cell":[4,4], "profile":"ridgevale", "playable":true},
	{"id":"rivergate_b1", "name":"Rivergate B1", "cell":[5,4], "profile":"rivergate", "playable":false},
	{"id":"cedar_a1", "name":"Cedar A1", "cell":[4,5], "profile":"cedar", "playable":false},
	{"id":"atlas15_01", "name":"Atlas15 01", "cell":[5,5], "profile":"atlas15", "playable":false}
]
var textures: Dictionary = {}
var manifests: Dictionary = {}
var admin: Dictionary = {}
var hydro: Dictionary = {}

func load_sources() -> void:
	admin = JSON.parse_string(FileAccess.get_file_as_string("res://triple/admin_reference.json"))
	hydro = JSON.parse_string(FileAccess.get_file_as_string("res://rivergate/assets/hydrology.json"))
	for tile: Dictionary in tiles:
		var profile: String = tile.profile
		if profile == "atlas15":
			textures[tile.id] = load("res://triple/atlas15_01.png")
			manifests[tile.id] = JSON.parse_string(FileAccess.get_file_as_string("res://triple/atlas15_01_layout.json"))
			continue
		manifests[tile.id] = JSON.parse_string(FileAccess.get_file_as_string("res://%s/assets/map.json" % profile))
		var bytes := FileAccess.get_file_as_bytes("res://%s/assets/height_4m.f32" % profile)
		var heights := bytes.to_float32_array()
		var image := Image.create(251,251,false,Image.FORMAT_RGB8)
		for z: int in 251:
			for x: int in 251:
				var i := z*5*1251+x*5
				var h := heights[i]
				var slope := (h-heights[mini(i+2,heights.size()-1)])*.09
				var color := Color("485845").lerp(Color("c4bb8e"),clampf(h/160.0,0,1))
				image.set_pixel(x,z,color.lightened(clampf(slope,-.2,.2)))
		textures[tile.id] = ImageTexture.create_from_image(image)

static func world_position(local: Vector3) -> Vector2:
	return CENTER + Vector2(local.x, local.z)

static func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x/TILE),floori(point.y/TILE))

static func sector_at(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x/25000),floori(point.y/25000))

func tile_at(point: Vector2) -> Dictionary:
	var cell := cell_at(point)
	for tile: Dictionary in tiles:
		if Vector2i(tile.cell[0],tile.cell[1]) == cell: return tile
	return {}

func tile_by_id(id: String) -> Dictionary:
	for tile: Dictionary in tiles:
		if tile.id == id: return tile
	return {}

static func rect(tile: Dictionary) -> Rect2:
	return Rect2(Vector2(tile.cell[0],tile.cell[1])*TILE,Vector2.ONE*TILE)

func roads(tile: Dictionary) -> Array:
	return manifests.get(tile.id,{}).get("roads",[])
