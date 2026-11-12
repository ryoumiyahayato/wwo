extends RefCounted
# Finite A0 prototype. FRA0 v1: codec byte + flags + dimensions/raw/payload lengths.
# No Shader/LOD changes. All returned images retain the original GPU format/Mips.

static func decode(data: PackedByteArray) -> Dictionary:
	var bad := {"errors":["Invalid A0 surface"]}
	if data.size()<28 or data.slice(0,8)!=PackedByteArray([70,82,65,48,0,0,0,0]) or data[8]!=1: return bad
	var codec := int(data[9])
	var flags := int(data.decode_u16(10))
	var bpp := flags>>8
	var mips := bool(flags&1)
	var w := int(data.decode_u32(12));var h := int(data.decode_u32(16))
	var raw_size := int(data.decode_u32(20))
	if bpp not in [1,2,4] or flags&254 or w<1 or h<1 or w>16384 or h>16384 or raw_size>268435456 or int(data.decode_u32(24))!=data.size()-28: return bad
	var fmt := Image.FORMAT_RGBA8 if bpp==4 else (Image.FORMAT_RG8 if bpp==2 else Image.FORMAT_R8)
	var layout: Array[Vector3i] = []
	var ww := w;var hh := h;var expected := 0
	while true:
		layout.append(Vector3i(ww,hh,ww*hh*bpp));expected+=ww*hh*bpp
		if not mips or ww==1 and hh==1: break
		ww=maxi(1,ww/2);hh=maxi(1,hh/2)
	if raw_size!=expected: return bad
	var payload := data.slice(28)
	var raw: PackedByteArray
	if codec==1:
		raw=payload.decompress(raw_size,FileAccess.COMPRESSION_ZSTD)
	elif codec==2:
		if payload.size()<4 or int(payload.decode_u32(0))!=layout.size(): return bad
		var cursor := 4
		for level: Vector3i in layout:
			if cursor+4>payload.size(): return bad
			var length := int(payload.decode_u32(cursor));cursor+=4
			if length<33 or cursor+length>payload.size(): return bad
			var pic := _png(payload.slice(cursor,cursor+length),level.x,level.y,fmt)
			if pic==null: return bad
			raw.append_array(pic.get_data());cursor+=length
		if cursor!=payload.size(): return bad
	elif codec==3:
		var padded_height := ceili(float(raw_size/bpp)/w)
		var pic := _png(payload,w,padded_height,fmt)
		if pic==null: return bad
		raw=pic.get_data()
		pic=null # Release image ownership before shrinking the COW byte array.
		raw.resize(raw_size)
	elif codec==5:
		var padded_height := ceili(float(raw_size/bpp)/w)
		if payload.size()<25 or payload.slice(0,4).get_string_from_ascii()!="RIFF" or payload.slice(8,16).get_string_from_ascii()!="WEBPVP8L" or payload[20]!=47: return bad
		var bits := int(payload.decode_u32(21))
		if (bits&16383)+1!=w or ((bits>>14)&16383)+1!=padded_height: return bad
		var pic := Image.new()
		if pic.load_webp_from_buffer(payload)!=OK: return bad
		pic.convert(fmt)
		raw=pic.get_data()
		pic=null # Release image ownership before shrinking the COW byte array.
		raw.resize(raw_size)
	elif codec==4:
		# Deliberately measure the real VM inverse cost; no native extension.
		var planes := payload.decompress(raw_size,FileAccess.COMPRESSION_ZSTD)
		if planes.size()!=raw_size: return bad
		raw.resize(raw_size)
		var pixels := raw_size/bpp
		for channel: int in range(bpp):
			for i: int in range(pixels): raw[i*bpp+channel]=planes[channel*pixels+i]
		var offset := 0
		for level: Vector3i in layout:
			for y: int in range(level.y):
				for x: int in range(1,level.x):
					for channel: int in range(bpp):
						var index := offset+(y*level.x+x)*bpp+channel
						raw[index]=(int(raw[index])+int(raw[index-bpp]))&255
			offset+=level.z
	else: return bad
	if raw.size()!=raw_size: return bad
	var image := Image.create_from_data(w,h,mips,fmt,raw)
	if image==null: return bad
	return {"errors":[],"image":image}

static func _png(data: PackedByteArray,w: int,h: int,fmt: Image.Format) -> Image:
	# Check IHDR dimensions before allowing native PNG allocation.
	if data.size()<33 or data.slice(0,8)!=PackedByteArray([137,80,78,71,13,10,26,10]): return null
	if _be32(data,16)!=w or _be32(data,20)!=h: return null
	var image := Image.new()
	if image.load_png_from_buffer(data)!=OK or image.get_width()!=w or image.get_height()!=h: return null
	image.convert(fmt)
	return image

static func _be32(data: PackedByteArray,offset: int) -> int:
	return int(data[offset])<<24|int(data[offset+1])<<16|int(data[offset+2])<<8|int(data[offset+3])
