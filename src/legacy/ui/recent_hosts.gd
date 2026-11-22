class_name RecentHosts
extends RefCounted
## The last host addresses a player joined, saved as JSON under user:// (path and size from
## UiTheme). Newest first, no duplicates.


## The saved addresses (newest first); [param fallback] alone when nothing is saved.
static func load_list(path: String, fallback: String, max_count: int) -> PackedStringArray:
	var out := PackedStringArray()
	if FileAccess.file_exists(path):
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Array:
				for a in parsed as Array:
					var s: String = str(a).strip_edges()
					if s != "" and not out.has(s) and out.size() < max_count:
						out.append(s)
	if out.is_empty():
		out.append(fallback)
	return out


## Puts [param address] first in the saved list and writes the file.
static func remember(path: String, address: String, fallback: String, max_count: int) -> void:
	var addr: String = address.strip_edges()
	if addr == "":
		return
	var current: PackedStringArray = load_list(path, fallback, max_count)
	var out: Array = [addr]
	for a in current:
		if a != addr and out.size() < max_count:
			out.append(a)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Cannot save the recent hosts to %s." % path)
		return
	f.store_string(JSON.stringify(out))
