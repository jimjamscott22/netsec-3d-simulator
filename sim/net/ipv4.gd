class_name IPv4
extends RefCounted
## Dotted-quad helpers. Addresses and masks are ints holding the unsigned
## 32-bit value; -1 is the invalid sentinel (mask 0 is valid).

const INVALID: int = -1
const MAX_ADDR: int = 0xFFFFFFFF


static func parse(s: String) -> int:
	var parts: PackedStringArray = s.split(".", true)
	if parts.size() != 4:
		return INVALID
	var addr: int = 0
	for part: String in parts:
		if part.is_empty() or not part.is_valid_int() or part.length() > 3:
			return INVALID
		# is_valid_int accepts a sign; require digits only, no leading zero.
		for i in part.length():
			if part[i] < "0" or part[i] > "9":
				return INVALID
		if part.length() > 1 and part[0] == "0":
			return INVALID
		var octet: int = part.to_int()
		if octet > 255:
			return INVALID
		addr = (addr << 8) | octet
	return addr


static func format(addr: int) -> String:
	return "%d.%d.%d.%d" % [(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]


static func is_valid(s: String) -> bool:
	return parse(s) != INVALID


static func parse_mask(s: String) -> int:
	var mask: int = parse(s)
	if mask == INVALID or mask_to_prefix(mask) == INVALID:
		return INVALID
	return mask


static func prefix_to_mask(prefix: int) -> int:
	if prefix < 0 or prefix > 32:
		return INVALID
	return (MAX_ADDR << (32 - prefix)) & MAX_ADDR


static func mask_to_prefix(mask: int) -> int:
	if mask < 0 or mask > MAX_ADDR:
		return INVALID
	var prefix: int = 0
	var seen_zero: bool = false
	for bit in range(31, -1, -1):
		if (mask >> bit) & 1 == 1:
			if seen_zero:
				return INVALID
			prefix += 1
		else:
			seen_zero = true
	return prefix


static func network(addr: int, mask: int) -> int:
	return addr & mask


static func same_subnet(a: int, b: int, mask: int) -> bool:
	return (a & mask) == (b & mask)
