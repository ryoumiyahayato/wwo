extends RefCounted

const MAGIC := "WWOCTM01"
const HEADER_BYTES := 24
const MAX_DECODE_BYTES := 32 * 1024 * 1024

static func encode(arrays: Array) -> PackedByteArray:
	var points: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if points.is_empty() or points.size()!=colors.size() or indices.is_empty() or indices.size()%3!=0:
		return PackedByteArray()
	var planar := PackedInt32Array()
	planar.resize(points.size()*2+indices.size())
	var positions := points.to_byte_array().to_int32_array()
	var codes := PackedByteArray()
	codes.resize(points.size())
	var palette := PackedInt32Array()
	var lookup := {}
	var x := 0
	var y := 0
	for i in points.size():
		planar[i]=positions[i*2]^x
		planar[i+points.size()]=positions[i*2+1]^y
		x=positions[i*2]
		y=positions[i*2+1]
		var color := colors[i].to_rgba32()
		if not lookup.has(color):
			if palette.size()>=256: return PackedByteArray()
			lookup[color]=palette.size()
			palette.append(color)
		codes[i]=int(lookup[color])
	var triangles := indices.size()/3
	var base := points.size()*2
	var first := 0
	for i in triangles:
		var a := indices[i*3]
		planar[base+i]=a-first
		planar[base+triangles+i]=indices[i*3+1]-a
		planar[base+triangles*2+i]=indices[i*3+2]-a
		first=a
	var raw := planar.to_byte_array()
	raw.append_array(palette.to_byte_array())
	raw.append_array(codes)
	if raw.size()>MAX_DECODE_BYTES: return PackedByteArray()
	var result := MAGIC.to_ascii_buffer()
	result.resize(HEADER_BYTES)
	result.encode_u32(8,points.size())
	result.encode_u32(12,triangles)
	result.encode_u32(16,palette.size())
	result.encode_u32(20,raw.size())
	result.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return result

static func read(path: String) -> Array:
	return decode(FileAccess.get_file_as_bytes(path))

static func read_budget(file: FileAccess) -> int:
	if file.get_length()<=HEADER_BYTES or file.get_buffer(8).get_string_from_ascii()!=MAGIC: return 0
	var vertices := file.get_32()
	var triangles := file.get_32()
	return vertices*24+triangles*12

static func decode(data: PackedByteArray) -> Array:
	if data.size()<=HEADER_BYTES or data.slice(0,8).get_string_from_ascii()!=MAGIC: return []
	var count := data.decode_u32(8)
	var triangles := data.decode_u32(12)
	var palette_size := data.decode_u32(16)
	var expected := count*9+triangles*12+palette_size*4
	if count==0 or triangles==0 or palette_size<1 or palette_size>256 or expected>MAX_DECODE_BYTES or data.decode_u32(20)!=expected:
		return []
	var raw := data.slice(HEADER_BYTES).decompress(expected,FileAccess.COMPRESSION_ZSTD)
	if raw.size()!=expected: return []
	var base := count*2
	var words := raw.slice(0,(base+triangles*3+palette_size)*4).to_int32_array()
	var palette := PackedColorArray()
	for i in palette_size: palette.append(Color.hex(words[base+triangles*3+i]))
	var indices := PackedInt32Array()
	indices.resize(triangles*3)
	var a := 0
	for i in triangles:
		a+=words[base+i]
		var b := a+words[base+triangles+i]
		var c := a+words[base+triangles*2+i]
		if mini(a,mini(b,c))<0 or maxi(a,maxi(b,c))>=count: return []
		indices[i*3]=a
		indices[i*3+1]=b
		indices[i*3+2]=c
	var positions := PackedInt32Array()
	positions.resize(base)
	var colors := PackedColorArray()
	colors.resize(count)
	var x := 0
	var y := 0
	for i in count:
		x^=words[i]
		y^=words[count+i]
		positions[i*2]=x
		positions[i*2+1]=y
		var code := raw[expected-count+i]
		if code>=palette_size: return []
		colors[i]=palette[code]
	var floats := positions.to_byte_array().to_float32_array()
	var points := PackedVector2Array()
	points.resize(count)
	for i in count: points[i]=Vector2(floats[i*2],floats[i*2+1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=points
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_INDEX]=indices
	return arrays
