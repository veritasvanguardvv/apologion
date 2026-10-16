extends RefCounted
# QR CODE ENCODER (pure GDScript)
# --------------------------------
# Makes a QR code picture for a short text (like the join link for phones).
# Port of the essential parts of Project Nayuki's "QR Code generator library"
# (MIT License, Copyright (c) Project Nayuki, https://www.nayuki.io/page/qr-code-generator-library):
# byte mode, error correction level M (or better), versions 1-10 (up to ~200 bytes).
#
# Usage:
#   var QrCode = preload("res://qr_code.gd")
#   var modules = QrCode.encode("http://192.168.1.5:8080")   # Array of rows of bool (true = black)
#   var texture = QrCode.make_texture("http://...", 8)       # ImageTexture, 8 pixels per module

const ECC_CODEWORDS_PER_BLOCK_M = [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26]
const NUM_BLOCKS_M = [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5]
const ECC_CODEWORDS_PER_BLOCK_Q = [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24]
const NUM_BLOCKS_Q = [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8]
const MAX_VERSION = 10

var version = 1
var size = 21
var ecc_q = false    # false = level M, true = level Q (chosen automatically if it still fits)
var modules = []     # modules[y][x] = true for dark
var is_function = []


# Returns the QR code as rows of booleans (true = dark), or [] if the text is too long.
static func encode(text: String) -> Array:
	var qr = new()
	if not qr._build(text.to_utf8_buffer()):
		return []
	return qr.modules

# A ready-to-use picture: black modules on white with a 4-module quiet border.
static func make_texture(text: String, pixels_per_module := 8) -> ImageTexture:
	var m = encode(text)
	if m.is_empty():
		return null
	var border = 4
	var n = m.size()
	var image = Image.create((n + border * 2) * pixels_per_module, (n + border * 2) * pixels_per_module, false, Image.FORMAT_RGB8)
	image.fill(Color.WHITE)
	for y in n:
		for x in n:
			if m[y][x]:
				image.fill_rect(Rect2i((x + border) * pixels_per_module, (y + border) * pixels_per_module, pixels_per_module, pixels_per_module), Color.BLACK)
	return ImageTexture.create_from_image(image)


func _build(data: PackedByteArray) -> bool:
	# Smallest version that fits (byte mode: 4 bits mode + 8/16 bits length + data)
	var found = false
	for v in range(1, MAX_VERSION + 1):
		var used = 4 + (8 if v < 10 else 16) + data.size() * 8
		if used <= _num_data_codewords(v, false) * 8:
			version = v
			ecc_q = used <= _num_data_codewords(v, true) * 8   # more error correction if it fits
			found = true
			break
	if not found:
		return false
	size = version * 4 + 17
	# Bits: mode 0100 (byte), length, data, terminator, padding
	var bits = []
	_append_bits(bits, 4, 4)
	_append_bits(bits, data.size(), 8 if version < 10 else 16)
	for b in data:
		_append_bits(bits, b, 8)
	var capacity = _num_data_codewords(version, ecc_q) * 8
	_append_bits(bits, 0, min(4, capacity - bits.size()))
	_append_bits(bits, 0, (8 - bits.size() % 8) % 8)
	var pad = [0xEC, 0x11]
	var i = 0
	while bits.size() < capacity:
		_append_bits(bits, pad[i % 2], 8)
		i += 1
	var codewords = PackedByteArray()
	codewords.resize(bits.size() / 8)
	for j in bits.size():
		codewords[j >> 3] |= bits[j] << (7 - (j & 7))
	# Draw
	modules = []
	is_function = []
	for y in size:
		var row = []
		row.resize(size)
		row.fill(false)
		modules.append(row)
		is_function.append(row.duplicate())
	_draw_function_patterns()
	_draw_codewords(_add_ecc_and_interleave(codewords))
	# Pick the mask with the lowest penalty
	var best_mask = 0
	var best_penalty = 1 << 30
	for mask in 8:
		_apply_mask(mask)
		_draw_format_bits(mask)
		var penalty = _penalty()
		if penalty < best_penalty:
			best_penalty = penalty
			best_mask = mask
		_apply_mask(mask)   # undo (XOR)
	_apply_mask(best_mask)
	_draw_format_bits(best_mask)
	return true


static func _append_bits(bits: Array, value: int, count: int):
	for k in range(count - 1, -1, -1):
		bits.append((value >> k) & 1)

static func _num_raw_data_modules(v: int) -> int:
	var result = (16 * v + 128) * v + 64
	if v >= 2:
		var numalign = v / 7 + 2
		result -= (25 * numalign - 10) * numalign - 55
		if v >= 7:
			result -= 36
	return result

static func _num_data_codewords(v: int, q: bool) -> int:
	var ecc = ECC_CODEWORDS_PER_BLOCK_Q[v] if q else ECC_CODEWORDS_PER_BLOCK_M[v]
	var blocks = NUM_BLOCKS_Q[v] if q else NUM_BLOCKS_M[v]
	return _num_raw_data_modules(v) / 8 - ecc * blocks


# ---------------- Function patterns ----------------

func _set_function(x: int, y: int, dark: bool):
	modules[y][x] = dark
	is_function[y][x] = true

func _draw_function_patterns():
	for i in size:
		_set_function(6, i, i % 2 == 0)
		_set_function(i, 6, i % 2 == 0)
	_draw_finder(3, 3)
	_draw_finder(size - 4, 3)
	_draw_finder(3, size - 4)
	var pos = _alignment_positions()
	var n = pos.size()
	for i in n:
		for j in n:
			if (i == 0 and j == 0) or (i == 0 and j == n - 1) or (i == n - 1 and j == 0):
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					_set_function(pos[i] + dx, pos[j] + dy, max(abs(dx), abs(dy)) != 1)
	_draw_format_bits(0)
	_draw_version()

func _draw_finder(cx: int, cy: int):
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var x = cx + dx
			var y = cy + dy
			if x >= 0 and x < size and y >= 0 and y < size:
				var d = max(abs(dx), abs(dy))
				_set_function(x, y, d != 2 and d != 4)

func _alignment_positions() -> Array:
	if version == 1:
		return []
	var numalign = version / 7 + 2
	var step = (version * 8 + numalign * 3 + 5) / (numalign * 4 - 4) * 2
	var result = []
	for i in numalign - 1:
		result.append(size - 7 - i * step)
	result.append(6)
	result.reverse()
	return result

func _draw_format_bits(mask: int):
	var data = (3 if ecc_q else 0) << 3 | mask   # format bits: M = 0, Q = 3
	var rem = data
	for k in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits = (data << 10 | rem) ^ 0x5412
	for i in range(0, 6):
		_set_function(8, i, (bits >> i) & 1 == 1)
	_set_function(8, 7, (bits >> 6) & 1 == 1)
	_set_function(8, 8, (bits >> 7) & 1 == 1)
	_set_function(7, 8, (bits >> 8) & 1 == 1)
	for i in range(9, 15):
		_set_function(14 - i, 8, (bits >> i) & 1 == 1)
	for i in range(0, 8):
		_set_function(size - 1 - i, 8, (bits >> i) & 1 == 1)
	for i in range(8, 15):
		_set_function(8, size - 15 + i, (bits >> i) & 1 == 1)
	_set_function(8, size - 8, true)

func _draw_version():
	if version < 7:
		return
	var rem = version
	for k in 12:
		rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
	var bits = version << 12 | rem
	for i in 18:
		var bit = (bits >> i) & 1 == 1
		var a = size - 11 + i % 3
		var b = i / 3
		_set_function(a, b, bit)
		_set_function(b, a, bit)


# ---------------- Data and error correction ----------------

func _add_ecc_and_interleave(data: PackedByteArray) -> PackedByteArray:
	var numblocks = NUM_BLOCKS_Q[version] if ecc_q else NUM_BLOCKS_M[version]
	var blockecclen = ECC_CODEWORDS_PER_BLOCK_Q[version] if ecc_q else ECC_CODEWORDS_PER_BLOCK_M[version]
	var rawcodewords = _num_raw_data_modules(version) / 8
	var numshortblocks = numblocks - rawcodewords % numblocks
	var shortblocklen = rawcodewords / numblocks
	var divisor = _rs_divisor(blockecclen)
	var blocks = []
	var k = 0
	for i in numblocks:
		var length = shortblocklen - blockecclen + (0 if i < numshortblocks else 1)
		var dat = data.slice(k, k + length)
		k += length
		var ecc = _rs_remainder(dat, divisor)
		if i < numshortblocks:
			dat.append(0)
		dat.append_array(ecc)
		blocks.append(dat)
	var result = PackedByteArray()
	for i in blocks[0].size():
		for j in blocks.size():
			if i != shortblocklen - blockecclen or j >= numshortblocks:
				result.append(blocks[j][i])
	return result

static func _rs_multiply(x: int, y: int) -> int:
	var z = 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z

static func _rs_divisor(degree: int) -> PackedByteArray:
	var result = PackedByteArray()
	result.resize(degree)
	result[degree - 1] = 1
	var root = 1
	for n in degree:
		for j in degree:
			result[j] = _rs_multiply(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = _rs_multiply(root, 0x02)
	return result

static func _rs_remainder(data: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var result = PackedByteArray()
	result.resize(divisor.size())
	for b in data:
		var factor = b ^ result[0]
		result.remove_at(0)
		result.append(0)
		for i in divisor.size():
			result[i] ^= _rs_multiply(divisor[i], factor)
	return result

func _draw_codewords(data: PackedByteArray):
	var i = 0
	var right = size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x = right - j
				var upward = ((right + 1) & 2) == 0
				var y = (size - 1 - vert) if upward else vert
				if not is_function[y][x] and i < data.size() * 8:
					modules[y][x] = ((data[i >> 3] >> (7 - (i & 7))) & 1) == 1
					i += 1
		right -= 2

func _apply_mask(mask: int):
	for y in size:
		for x in size:
			if is_function[y][x]:
				continue
			var invert = false
			match mask:
				0: invert = (x + y) % 2 == 0
				1: invert = y % 2 == 0
				2: invert = x % 3 == 0
				3: invert = (x + y) % 3 == 0
				4: invert = (x / 3 + y / 2) % 2 == 0
				5: invert = x * y % 2 + x * y % 3 == 0
				6: invert = (x * y % 2 + x * y % 3) % 2 == 0
				7: invert = ((x + y) % 2 + x * y % 3) % 2 == 0
			if invert:
				modules[y][x] = not modules[y][x]

# Simplified penalty (long runs, 2x2 blocks, dark/light balance). Any mask
# gives a valid code; this just picks one that scans easily.
func _penalty() -> int:
	var result = 0
	for y in size:
		var run = 0
		var color = false
		for x in size:
			if modules[y][x] == color:
				run += 1
				if run == 5: result += 3
				elif run > 5: result += 1
			else:
				color = modules[y][x]
				run = 1
	for x in size:
		var run = 0
		var color = false
		for y in size:
			if modules[y][x] == color:
				run += 1
				if run == 5: result += 3
				elif run > 5: result += 1
			else:
				color = modules[y][x]
				run = 1
	var dark = 0
	for y in size:
		for x in size:
			if modules[y][x]:
				dark += 1
			if x < size - 1 and y < size - 1 and modules[y][x] == modules[y][x + 1] and modules[y][x] == modules[y + 1][x] and modules[y][x] == modules[y + 1][x + 1]:
				result += 3
	var total = size * size
	var k = (abs(dark * 20 - total * 10) + total - 1) / total - 1
	result += max(k, 0) * 10
	return result
