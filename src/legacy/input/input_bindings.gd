class_name InputBindings
extends RefCounted
## Custom key and button bindings of the game actions (story 007 part 3, controls menu).
## The defaults live in InputActions; this only swaps InputMap events of the actions in
## InputActions.REBINDABLE and saves them as JSON (normally user://controls.json: per action
## keys = physical keycodes, buttons = joypad buttons, axes = [axis, sign]). JSON, not ConfigFile:
## a damaged ConfigFile makes the engine print an error, JSON.parse only returns one.
## Two columns are kept apart: the keyboard (keys) and the controller (buttons and axes).
## An input is never bound to two rebindable actions of the same column: [method bind] swaps.

enum Device { KEYBOARD, CONTROLLER }

## Where the bindings are saved on this PC.
const DEFAULT_PATH: String = "user://controls.json"
## Format version written into the file ("version").
const FILE_VERSION: int = 1


## The column [param e] belongs to: Device.KEYBOARD, Device.CONTROLLER, or -1 (mouse and others).
static func device_of(e: InputEvent) -> int:
	if e is InputEventKey:
		return Device.KEYBOARD
	if e is InputEventJoypadButton or e is InputEventJoypadMotion:
		return Device.CONTROLLER
	return -1


## The events of [param action] in column [param device], in InputMap order.
static func events_of(action: StringName, device: int) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not InputMap.has_action(action):
		return out
	for e in InputMap.action_get_events(action):
		if device_of(e) == device:
			out.append(e)
	return out


## True when [param a] and [param b] are the same physical input (key, button, or axis direction).
static func same_input(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return _key_of(a as InputEventKey) == _key_of(b as InputEventKey)
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		var ma := a as InputEventJoypadMotion
		var mb := b as InputEventJoypadMotion
		return ma.axis == mb.axis and signf(ma.axis_value) == signf(mb.axis_value)
	return false


## A clean binding event made from a captured [param e] (a key by its physical position, a
## button, or an axis direction with value -1 or 1); null when [param e] cannot be bound.
static func normalized(e: InputEvent) -> InputEvent:
	if e is InputEventKey:
		var code: Key = _key_of(e as InputEventKey)
		if code == KEY_NONE:
			return null
		var k := InputEventKey.new()
		k.physical_keycode = code
		return k
	if e is InputEventJoypadButton:
		var b := InputEventJoypadButton.new()
		b.button_index = (e as InputEventJoypadButton).button_index
		return b
	if e is InputEventJoypadMotion:
		var src := e as InputEventJoypadMotion
		if is_zero_approx(src.axis_value):
			return null
		var m := InputEventJoypadMotion.new()
		m.axis = src.axis
		m.axis_value = signf(src.axis_value)
		return m
	return null


## The rebindable action other than [param except_action] that has [param e] in the same
## column, or &"" when none.
static func owner_of(e: InputEvent, except_action: StringName) -> StringName:
	var device: int = device_of(e)
	for a: StringName in InputActions.REBINDABLE:
		if a == except_action:
			continue
		for other in events_of(a, device):
			if same_input(other, e):
				return a
	return &""


## Makes [param e] the only binding of [param action] in its column, in effect at once.
## When another rebindable action used [param e], the two swap: that action loses [param e] and
## gets this action's old inputs of the column. Returns the swapped action, or &"" when none.
static func bind(action: StringName, e: InputEvent) -> StringName:
	var clean: InputEvent = normalized(e)
	if clean == null or not InputMap.has_action(action):
		return &""
	var device: int = device_of(clean)
	var old: Array[InputEvent] = events_of(action, device)
	var other: StringName = owner_of(clean, action)
	for o in old:
		InputMap.action_erase_event(action, o)
	InputMap.action_add_event(action, clean)
	if other != &"":
		for o in events_of(other, device):
			if same_input(o, clean):
				InputMap.action_erase_event(other, o)
		for o in old:
			if not same_input(o, clean) and owner_of(o, &"") == &"":
				InputMap.action_add_event(other, o)
	return other


## Writes every rebindable action's events to [param path] as JSON. An empty path saves
## nothing (debug shots). Returns the file error.
static func save(path: String) -> Error:
	if path == "":
		return OK
	var actions: Dictionary = {}
	for a: StringName in InputActions.REBINDABLE:
		var keys: Array = []
		var buttons: Array = []
		var axes: Array = []
		for e in InputMap.action_get_events(a):
			if e is InputEventKey:
				keys.append(int(_key_of(e as InputEventKey)))
			elif e is InputEventJoypadButton:
				buttons.append(int((e as InputEventJoypadButton).button_index))
			elif e is InputEventJoypadMotion:
				var m := e as InputEventJoypadMotion
				axes.append([int(m.axis), int(signf(m.axis_value))])
		actions[String(a)] = {"keys": keys, "buttons": buttons, "axes": axes}
	var dir: String = path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Could not save the controls to %s (error %d)." % [path, FileAccess.get_open_error()])
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"version": FILE_VERSION, "actions": actions}, "\t"))
	f.close()
	return OK


## Applies the bindings saved in [param path] over the defaults. A missing file keeps the
## defaults quietly; an unreadable file, or a bad action entry, keeps the defaults (for that
## action) with a warning. An input found on two actions of a column is kept on the first one
## only, with a warning. Returns the number of actions taken from the file.
static func load_saved(path: String) -> int:
	if path == "" or not FileAccess.file_exists(path):
		return 0
	var text: String = FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err: Error = json.parse(text)
	if err != OK or not (json.data is Dictionary) or not ((json.data as Dictionary).get("actions") is Dictionary):
		push_warning("The controls file %s cannot be read (%s); using the default controls." % [path,
				json.get_error_message() if err != OK else "not a controls file"])
		return 0
	var saved: Dictionary = (json.data as Dictionary).get("actions")
	# Pass 1: read every entry; a bad one keeps that action's defaults.
	var parsed: Dictionary = {}
	for a: StringName in InputActions.REBINDABLE:
		if not saved.has(String(a)):
			continue
		var events: Variant = _events_from(saved[String(a)])
		if events == null:
			push_warning("The controls file %s has a bad entry for '%s'; that action keeps its default keys." % [path, a])
			continue
		parsed[a] = events
	# Pass 2: clear the actions read, then add their inputs (never one input on two actions).
	for a: StringName in parsed:
		InputMap.action_erase_events(a)
	for a: StringName in InputActions.REBINDABLE:
		if not parsed.has(a):
			continue
		for e: InputEvent in parsed[a]:
			var other: StringName = owner_of(e, a)
			if other != &"":
				push_warning("The controls file %s binds one input to '%s' and '%s'; it stays on '%s' only." % [
						path, a, other, other])
				continue
			InputMap.action_add_event(a, e)
	return parsed.size()


# The events of one saved action ({keys, buttons, axes}); null when anything has the wrong type.
static func _events_from(entry: Variant) -> Variant:
	if not (entry is Dictionary):
		return null
	var d: Dictionary = entry
	var keys: Variant = d.get("keys", [])
	var buttons: Variant = d.get("buttons", [])
	var axes: Variant = d.get("axes", [])
	if not (keys is Array and buttons is Array and axes is Array):
		return null
	var out: Array[InputEvent] = []
	for k: Variant in keys as Array:
		if not _is_whole(k) or int(k) <= 0:
			return null
		var ke := InputEventKey.new()
		ke.physical_keycode = int(k) as Key
		out.append(ke)
	for b: Variant in buttons as Array:
		if not _is_whole(b) or int(b) < 0 or int(b) >= JOY_BUTTON_MAX:
			return null
		var be := InputEventJoypadButton.new()
		be.button_index = int(b) as JoyButton
		out.append(be)
	for ax: Variant in axes as Array:
		if not (ax is Array) or (ax as Array).size() != 2:
			return null
		var axis: Variant = (ax as Array)[0]
		var sgn: Variant = (ax as Array)[1]
		if not _is_whole(axis) or not _is_whole(sgn) or int(axis) < 0 or int(axis) >= JOY_AXIS_MAX or absi(int(sgn)) != 1:
			return null
		var me := InputEventJoypadMotion.new()
		me.axis = int(axis) as JoyAxis
		me.axis_value = float(sgn)
		out.append(me)
	return out


# JSON numbers arrive as floats: true for a whole number.
static func _is_whole(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	return typeof(v) == TYPE_FLOAT and is_equal_approx(float(v), roundf(float(v)))


# A key's physical keycode (its position on the keyboard), from the keycode when the event has none.
static func _key_of(k: InputEventKey) -> Key:
	if k.physical_keycode != KEY_NONE:
		return k.physical_keycode
	return k.keycode
