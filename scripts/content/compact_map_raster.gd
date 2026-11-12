extends RefCounted
## WWOCM2 raster blocks. Decode on the existing map or terrain worker.

const MANIFEST := "res://assets/maps/compact/base.json"
const RELIEF_PAGES := "res://assets/maps/compact/relief/"
const MAX_INDEX_BYTES := 1024 * 1024
const MAX_READ_BYTES := 32 * 1024 * 1024
const MAX_DECODE_BYTES := 64 * 1024 * 1024

static func enabled() -> bool:
	var args := OS.get_cmdline_user_args()
	return "--compact-map" in args and "--legacy-map" not in args

static func _manifest_path() -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--compact-map-pack")
	if index < 0: return MANIFEST
	return args[index+1].path_join("base.json") if index+1 < args.size() else ""

static func has_builtin_relief_pages() -> bool:
	return enabled() and _manifest_path() == MANIFEST

static func read_relief_page(path: String, source: String, width: int, height: int, bytes: int, current: Callable, measured: bool) -> Dictionary:
	if width < 1 or width > 16384 or height < 1 or height > 16384 or bytes > MAX_DECODE_BYTES: return {}
	var shape := Vector2i(width, height)
	var expected := 0
	while true:
		expected += shape.x*shape.y*4
		if shape == Vector2i.ONE: break
		shape = Vector2i(maxi(1,shape.x/2),maxi(1,shape.y/2))
	if bytes != expected: return {}
	var started := Time.get_ticks_usec() if measured else 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 12 or file.get_length() > MAX_READ_BYTES: return {}
	if file.get_buffer(8) != PackedByteArray([87,87,79,67,77,50,0,0]): return {}
	var index_size := int(file.get_32())
	if index_size < 2 or index_size > mini(4096,file.get_length()-12): return {}
	var header: Variant = JSON.parse_string(file.get_buffer(index_size).get_string_from_utf8())
	if not header is Dictionary or not header.get("meta") is Dictionary or not header.get("blocks") is Dictionary: return {}
	var meta: Dictionary = header.meta
	if meta.get("kind") != "relief-page" or meta.get("source") != source.trim_prefix("res://") or meta.get("width") != width or meta.get("height") != height or meta.get("decoded_bytes") != bytes: return {}
	var blocks: Dictionary = header.blocks
	var length := file.get_length()-file.get_position()
	if current.is_valid() and not current.call(): return {}
	var block: Variant = blocks.get("mips")
	var predicted := blocks.has("base")
	if not predicted and (not block is Array or block.size() != 3 or block[0] != 0 or block[1] != length or block[2] != "webp-rgba8-mips"): return {}
	var payload := file.get_buffer(length)
	if payload.size() != length: return {}
	file.close()
	var read_done := Time.get_ticks_usec() if measured else 0
	var image := _decode_predicted_mips(payload,blocks,width,height,bytes,current) if predicted else decode_webp_mips(payload,width,height,bytes)
	if image == null or (current.is_valid() and not current.call()): return {}
	var errors: Array[String] = []
	var result := {"image":image,"errors":errors,"storage":"wwocm2-page"}
	if measured:
		result["read_us"] = read_done-started
		result["decode_us"] = Time.get_ticks_usec()-read_done
	return result

static func _decode_predicted_mips(payload: PackedByteArray, blocks: Dictionary, width: int, height: int, expected: int, current: Callable) -> Image:
	var base: Variant = blocks.get("base")
	var corrections: Variant = blocks.get("mip_corrections")
	if blocks.size()!=2 or not base is Array or base.size()!=3 or not corrections is Array or corrections.size()!=4: return null
	if base[0]!=0 or not _is_integer(base[1],25,payload.size()-1) or base[2]!="webp-rgba8-base": return null
	var split := int(base[1])
	if corrections[0]!=split or corrections[1]!=payload.size()-split or corrections[2]!="zlib-sparse-box-rgba8": return null
	if not _is_integer(corrections[3],4,mini(MAX_DECODE_BYTES,(expected-width*height*4)*4+64)) or int(corrections[3])%4!=0: return null
	if payload.slice(0,4).get_string_from_ascii()!="RIFF" or payload.slice(8,16).get_string_from_ascii()!="WEBPVP8L" or payload[20]!=47: return null
	var dimensions := payload.decode_u32(21)
	if (dimensions&16383)+1!=width or ((dimensions>>14)&16383)+1!=height or dimensions>>29: return null
	var image := Image.new()
	if image.load_webp_from_buffer(payload.slice(0,split))!=OK or image.get_width()!=width or image.get_height()!=height: return null
	image.convert(Image.FORMAT_RGBA8)
	var original := Vector2i(width,height)
	var raw := image.get_data()
	var delta := payload.slice(split).decompress(int(corrections[3]),FileAccess.COMPRESSION_DEFLATE).to_int32_array()
	if delta.size()*4!=int(corrections[3]): return null
	var offset := 0
	while width!=1 or height!=1:
		if offset>=delta.size() or (current.is_valid() and not current.call()): return null
		var prior_bytes := width*height*4
		width = maxi(1,width/2)
		height = maxi(1,height/2)
		var level_bytes := width*height*4
		if image.generate_mipmaps()!=OK: return null
		var pixels := image.get_data().slice(prior_bytes,prior_bytes+level_bytes)
		var count := delta[offset]
		offset += 1
		if count<0 or count>level_bytes or offset+count>delta.size(): return null
		var at := -1
		for index in range(offset,offset+count):
			var word := delta[index]
			var gap := (word>>8)&0xffffff
			if gap==0: return null
			at += gap
			if at>=level_bytes: return null
			pixels[at] = (int(pixels[at])+(word&255))&255
		offset += count
		raw.append_array(pixels)
		image = Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,pixels)
	if offset!=delta.size() or raw.size()!=expected: return null
	return Image.create_from_data(original.x,original.y,true,Image.FORMAT_RGBA8,raw)

static func decode_webp_mips(payload: PackedByteArray, width: int, height: int, bytes: int) -> Image:
	# The lossless stream contains all original mip bytes, including RGB under zero alpha.
	if payload.size()<25 or payload.slice(0,4).get_string_from_ascii()!="RIFF" or payload.slice(8,16).get_string_from_ascii()!="WEBPVP8L" or payload[20]!=47: return null
	var bits := int(payload.decode_u32(21))
	if (bits&16383)+1!=width or ((bits>>14)&16383)+1!=ceili(float(bytes/4)/width) or bits>>29: return null
	var packed_image := Image.new()
	if packed_image.load_webp_from_buffer(payload)!=OK: return null
	packed_image.convert(Image.FORMAT_RGBA8)
	var raw := packed_image.get_data()
	packed_image = null
	if raw.size()<bytes: return null
	raw.resize(bytes)
	return Image.create_from_data(width,height,true,Image.FORMAT_RGBA8,raw)

static func read_relief(source: String, width: int, height: int, bytes: int, current: Callable) -> Image:
	if not enabled() or width < 1 or height < 1 or bytes > MAX_DECODE_BYTES: return null
	var shapes: Array[Vector2i] = []
	var expected := 0
	var size := Vector2i(width,height)
	while true:
		shapes.append(size)
		expected += size.x*size.y*4
		if size == Vector2i.ONE: break
		size = Vector2i(maxi(1,size.x/2),maxi(1,size.y/2))
	if expected != bytes: return null
	var pixels := _read(source,shapes,false,current)
	if pixels.size() != bytes: return null
	return Image.create_from_data(width,height,true,Image.FORMAT_RGBA8,pixels)

static func read_height(source: String, width: int) -> PackedByteArray:
	if not enabled() or width < 1 or width > 4096: return PackedByteArray()
	var shapes: Array[Vector2i] = [Vector2i(width,width)]
	return _read(source,shapes,true,Callable())

static func _read(source: String, shapes: Array[Vector2i], height: bool, current: Callable) -> PackedByteArray:
	var empty := PackedByteArray()
	var manifest_path := _manifest_path()
	if not FileAccess.file_exists(manifest_path): return empty
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary or manifest.get("format") != "wwo-compact-map-base-v1": return empty
	var files: Variant = manifest.get("sources")
	if not files is Dictionary: return empty
	var name := str(files.get(source,""))
	if name.is_empty() or name != name.get_file() or not name.ends_with(".wcm"): return empty
	var file := FileAccess.open(manifest_path.get_base_dir().path_join(name),FileAccess.READ)
	if file == null or file.get_length() < 12 or file.get_length() > MAX_READ_BYTES: return empty
	if file.get_buffer(8) != PackedByteArray([87,87,79,67,77,50,0,0]): return empty
	var index_bytes := int(file.get_32())
	if index_bytes < 2 or index_bytes > mini(file.get_length()-12,MAX_INDEX_BYTES): return empty
	var header: Variant = JSON.parse_string(file.get_buffer(index_bytes).get_string_from_utf8())
	if not header is Dictionary or not header.get("meta") is Dictionary or not header.get("blocks") is Dictionary: return empty
	var meta: Dictionary = header.meta
	if str(meta.get("source","")) != source.trim_prefix("res://"): return empty
	if height:
		var origin: Variant = meta.get("origin_xz_m")
		if not origin is Array or origin.size() != 2 or origin[0] != -2500 or origin[1] != -2500 or meta.get("step_m") != 4 or meta.get("height_dtype") != "<f4": return empty
	var declared: Variant = meta.get("shapes")
	var generated: Variant = meta.get("mips_from_box")
	if not declared is Array or declared.size() != shapes.size() or not generated is Array: return empty
	if height and not generated.is_empty(): return empty
	var box_mips: Array[int] = []
	for mip: Variant in generated:
		if not _is_integer(mip,1,shapes.size()-1) or int(mip) in box_mips: return empty
		box_mips.append(int(mip))
	var blocks: Array[Array] = []
	for level in shapes.size():
		var row: Variant = declared[level]
		var size := shapes[level]
		if not row is Array or row.size() != (2 if height else 3): return empty
		if row[0] != size.y or row[1] != size.x or (not height and row[2] != 4): return empty
		blocks.append([])
	var entries: Dictionary = header.blocks
	if entries.size() > 2048: return empty
	var data_start := file.get_position()
	for key: String in entries:
		var entry: Variant = entries[key]
		if not entry is Array or entry.size() != 3 or not entry[2] is Array or entry[2].size() != 8: return empty
		if not _is_integer(entry[0],0,file.get_length()) or not _is_integer(entry[1],1,MAX_READ_BYTES): return empty
		if int(entry[0])+int(entry[1]) > file.get_length()-data_start: return empty
		var desc: Array = entry[2]
		if not _is_integer(desc[0],0,shapes.size()-1): return empty
		var level := int(desc[0])
		var size := shapes[level]
		if not _is_integer(desc[1],0,size.x-1) or not _is_integer(desc[2],0,size.y-1) or not _is_integer(desc[3],1,size.x) or not _is_integer(desc[4],1,size.y): return empty
		if desc[1]+desc[3] > size.x or desc[2]+desc[4] > size.y: return empty
		if desc[6] != ("<f4" if height else "|u1") or desc[7] != (1 if height else 4): return empty
		if desc[5] not in (["raw","zlib","xor-shuffle"] if height else ["raw","zlib","planar","planar-xor"]): return empty
		blocks[level].append(entry)
	var output := PackedByteArray()
	var prior: Image
	for level in shapes.size():
		if current.is_valid() and not current.call(): return empty
		var size := shapes[level]
		var image: Image
		if level in box_mips:
			# Phase-two packs only omit mips proven byte-exact under this box rule.
			if prior == null or not blocks[level].is_empty() or size.x*size.y > 256: return empty
			image = _box_mip(prior,size)
		else:
			image = _read_level(file,data_start,size,blocks[level],current)
		if image == null: return empty
		output.append_array(image.get_data())
		prior = image
	return output

static func _is_integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and value >= low and value <= high and int(value) == value

static func _read_level(file: FileAccess, start: int, size: Vector2i, entries: Array, current: Callable) -> Image:
	var image := Image.create_empty(size.x,size.y,false,Image.FORMAT_RGBA8)
	var rectangles: Array[Rect2i] = []
	var area := 0
	for entry: Array in entries:
		if current.is_valid() and not current.call(): return null
		var desc: Array = entry[2]
		var rect := Rect2i(int(desc[1]),int(desc[2]),int(desc[3]),int(desc[4]))
		for earlier: Rect2i in rectangles:
			if rect.intersects(earlier): return null
		rectangles.append(rect)
		area += rect.get_area()
		file.seek(start+int(entry[0]))
		var payload := file.get_buffer(int(entry[1]))
		if payload.size() != int(entry[1]): return null
		var tile := _read_tile(payload,str(desc[5]),rect.size)
		if tile == null: return null
		image.blit_rect(tile,Rect2i(Vector2i.ZERO,rect.size),rect.position)
	return image if area == size.x*size.y else null

static func _read_tile(payload: PackedByteArray, codec: String, size: Vector2i) -> Image:
	var count := size.x*size.y
	var raw := payload if codec == "raw" else payload.decompress(count*4,FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != count*4: return null
	if codec == "xor-shuffle":
		var bytes := PackedByteArray()
		bytes.resize(raw.size())
		for y in size.y:
			var previous := 0
			for x in size.x:
				var at := y*size.x+x
				previous ^= raw[at] | (raw[at+count]<<8) | (raw[at+2*count]<<16) | (raw[at+3*count]<<24)
				bytes.encode_u32(at*4,previous)
		raw = bytes
	elif codec in ["planar","planar-xor"]:
		var bytes := PackedByteArray()
		bytes.resize(raw.size())
		for channel in 4:
			for y in size.y:
				var previous := 0
				for x in size.x:
					var at := y*size.x+x
					var value := int(raw[channel*count+at])
					if codec == "planar-xor":
						value ^= previous
						previous = value
					bytes[at*4+channel] = value
		raw = bytes
	return Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBA8,raw)

static func _box_mip(prior: Image, size: Vector2i) -> Image:
	var source := prior.get_data()
	var width := prior.get_width()
	var height := prior.get_height()
	var bytes := PackedByteArray()
	bytes.resize(size.x*size.y*4)
	for y in size.y:
		for x in size.x:
			var tl := (y*2*width+x*2)*4
			var tr := (y*2*width+mini(x*2+1,width-1))*4
			var bl := (mini(y*2+1,height-1)*width+x*2)*4
			var br := (mini(y*2+1,height-1)*width+mini(x*2+1,width-1))*4
			for c in 4:
				bytes[(y*size.x+x)*4+c] = (int(source[tl+c])+int(source[tr+c])+int(source[bl+c])+int(source[br+c])+2)/4
	return Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBA8,bytes)
