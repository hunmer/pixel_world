class_name AmbientRegistry
extends Node

## Plugin host and router for ambient visual species.
##
## An ambient species definition names a `renderer_script`. The script must
## instantiate a Node and may implement any subset of the common interfaces:
##
##     configure(profile: Dictionary)
##     add_cluster(cell, host, local_surface_position, count, seed)
##     remove_cell(cell)
##     clear()
##     refresh_field()
##     set_environment_amount(amount)
##     update_observer(context, delta)
##
## Calls are routed by ambient species ID. Missing optional interfaces are
## reported when requested instead of being silently ignored. Renderers can be
## shared explicitly with `renderer_alias`, or automatically when species use
## the same renderer script and renderer profile.

const COMMON_INTERFACES: Array[StringName] = [
	&"configure",
	&"add_cluster",
	&"remove_cell",
	&"clear",
	&"refresh_field",
	&"set_environment_amount",
]

var _routes: Dictionary = {}
var _renderers: Dictionary = {}
var _errors: Array[Dictionary] = []


## Registers every definition without depending on Dictionary iteration order.
## Script-backed species are created first, then alias-only species are resolved.
func register_species_catalog(definitions: Dictionary) -> bool:
	var success := true
	var aliases_pending: Array[Dictionary] = []
	for ambient_id_value in definitions:
		var ambient_id := StringName(ambient_id_value)
		var definition_value: Variant = definitions[ambient_id_value]
		if not definition_value is Dictionary:
			_report(
				&"invalid_ambient_definition",
				ambient_id,
				"ambient definition must be a Dictionary"
			)
			success = false
			continue
		var definition: Dictionary = definition_value
		if definition.has("renderer_script"):
			success = register_species(ambient_id, definition) and success
		else:
			aliases_pending.append({"id": ambient_id, "definition": definition})

	var made_progress := true
	while made_progress and not aliases_pending.is_empty():
		made_progress = false
		for index in range(aliases_pending.size() - 1, -1, -1):
			var pending: Dictionary = aliases_pending[index]
			var definition: Dictionary = pending["definition"]
			if not _alias_is_resolvable(StringName(definition.get("renderer_alias", ""))):
				continue
			if not register_species(pending["id"], definition):
				success = false
			aliases_pending.remove_at(index)
			made_progress = true

	for pending: Dictionary in aliases_pending:
		var ambient_id: StringName = pending["id"]
		var definition: Dictionary = pending["definition"]
		var alias_name := StringName(definition.get("renderer_alias", ""))
		_report(
			&"missing_renderer_script",
			ambient_id,
			(
				"renderer_script is missing and renderer_alias '%s' cannot be resolved"
				% alias_name
			)
		)
		success = false
	return success


## Registers one ambient species and creates or reuses its renderer Node.
func register_species(ambient_id: StringName, definition: Dictionary) -> bool:
	if ambient_id.is_empty():
		_report(&"invalid_ambient_id", ambient_id, "ambient id cannot be empty")
		return false
	if _routes.has(ambient_id):
		_report(
			&"duplicate_ambient_id",
			ambient_id,
			"ambient id is already registered"
		)
		return false

	var profile_value: Variant = definition.get(
		"renderer_profile",
		definition.get("renderer_config", definition.get("profile", {}))
	)
	if not profile_value is Dictionary:
		_report(
			&"invalid_renderer_profile",
			ambient_id,
			"renderer profile must be a Dictionary"
		)
		return false
	var profile: Dictionary = (profile_value as Dictionary).duplicate(true)
	var renderer_alias := StringName(definition.get("renderer_alias", ""))
	var renderer_key := &""
	var renderer_script: Script = null
	var script_id := ""

	if definition.has("renderer_script"):
		renderer_script = _load_renderer_script(
			ambient_id,
			definition.get("renderer_script")
		)
		if renderer_script == null:
			return false
		script_id = _script_id(renderer_script)
		renderer_key = (
			StringName("alias:%s" % renderer_alias)
			if not renderer_alias.is_empty()
			else StringName("shared:%s:%s" % [script_id, _stable_variant(profile)])
		)
		if _renderers.has(renderer_key):
			var existing: Dictionary = _renderers[renderer_key]
			if (
				String(existing.get("script_id", "")) != script_id
				or _stable_variant(existing.get("profile", {})) != _stable_variant(profile)
			):
				_report(
					&"renderer_alias_conflict",
					ambient_id,
					"renderer_alias is already bound to another script or profile"
				)
				return false
		else:
			var renderer := _instantiate_renderer(ambient_id, renderer_script)
			if renderer == null:
				return false
			_renderers[renderer_key] = {
				"node": renderer,
				"script_id": script_id,
				"profile": profile,
				"ambient_ids": [],
			}
			# `configure` is optional. If provided, initialize the shared renderer
			# exactly once with its renderer profile.
			if renderer.has_method(&"configure"):
				renderer.call(&"configure", profile.duplicate(true))
	else:
		if renderer_alias.is_empty():
			_report(
				&"missing_renderer_script",
				ambient_id,
				"ambient definition requires renderer_script or renderer_alias"
			)
			return false
		renderer_key = _renderer_key_for_alias(renderer_alias)
		if renderer_key.is_empty():
			_report(
				&"missing_renderer_script",
				ambient_id,
				"renderer_alias '%s' cannot be resolved" % renderer_alias
			)
			return false
		if not profile.is_empty():
			var aliased_record: Dictionary = _renderers[renderer_key]
			if _stable_variant(aliased_record.get("profile", {})) != _stable_variant(profile):
				_report(
					&"renderer_alias_conflict",
					ambient_id,
					"alias-only species cannot replace a shared renderer profile"
				)
				return false

	_routes[ambient_id] = {
		"renderer_key": renderer_key,
		"definition": definition.duplicate(true),
	}
	var record: Dictionary = _renderers[renderer_key]
	var ambient_ids: Array = record["ambient_ids"]
	ambient_ids.append(ambient_id)
	return true


func has_species(ambient_id: StringName) -> bool:
	return _routes.has(ambient_id)


func registered_species_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_routes.keys())
	result.sort()
	return result


func renderer_count() -> int:
	return _renderers.size()


func get_renderer(ambient_id: StringName) -> Node:
	var record := _record_for(ambient_id, false)
	if record.is_empty():
		return null
	var renderer: Node = record.get("node")
	return renderer if is_instance_valid(renderer) else null


func shares_renderer(first_id: StringName, second_id: StringName) -> bool:
	if not _routes.has(first_id) or not _routes.has(second_id):
		return false
	return _routes[first_id]["renderer_key"] == _routes[second_id]["renderer_key"]


func supports_interface(ambient_id: StringName, interface_name: StringName) -> bool:
	var renderer := get_renderer(ambient_id)
	return renderer != null and renderer.has_method(interface_name)


func configure(ambient_id: StringName, profile: Dictionary = {}) -> bool:
	return _invoke(ambient_id, &"configure", [profile.duplicate(true)])


func add_cluster(
	ambient_id: StringName,
	cell: Vector2i,
	host: Node2D,
	local_surface_position: Vector2,
	count: int,
	deterministic_seed: int
) -> bool:
	return _invoke(
		ambient_id,
		&"add_cluster",
		[cell, host, local_surface_position, count, deterministic_seed]
	)


func remove_cell(ambient_id: StringName, cell: Vector2i) -> bool:
	return _invoke(ambient_id, &"remove_cell", [cell])


func clear(ambient_id: StringName) -> bool:
	return _invoke(ambient_id, &"clear", [])


func refresh_field(ambient_id: StringName) -> bool:
	return _invoke(ambient_id, &"refresh_field", [])


func set_environment_amount(ambient_id: StringName, amount: float) -> bool:
	return _invoke(ambient_id, &"set_environment_amount", [clampf(amount, 0.0, 1.0)])


## Broadcast helpers invoke each shared renderer once, even if many species IDs
## route to it.
func clear_all() -> bool:
	return _invoke_all_unique(&"clear", [])


func remove_cell_all(cell: Vector2i) -> bool:
	return _invoke_all_unique(&"remove_cell", [cell])


func refresh_all() -> bool:
	return _invoke_all_unique(&"refresh_field", [])


func set_all_environment_amount(amount: float) -> bool:
	return _invoke_all_unique(
		&"set_environment_amount",
		[clampf(amount, 0.0, 1.0)]
	)


## Observer updates are deliberately optional: static ambient renderers such as
## fireflies do not need the player/camera every frame, while birds use it for
## proximity take-off and short-lived flyovers. Shared renderers are still
## invoked only once and the absence of this interface is not an error.
func update_observer_all(context: Dictionary, delta: float) -> void:
	for renderer_key in _renderers:
		var record: Dictionary = _renderers[renderer_key]
		var renderer: Node = record.get("node")
		if is_instance_valid(renderer) and renderer.has_method(&"update_observer"):
			renderer.call(&"update_observer", context, maxf(delta, 0.0))


func get_errors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for error: Dictionary in _errors:
		result.append(error.duplicate(true))
	return result


func clear_errors() -> void:
	_errors.clear()


func is_valid() -> bool:
	return _errors.is_empty()


func _invoke(
	ambient_id: StringName,
	interface_name: StringName,
	arguments: Array
) -> bool:
	var record := _record_for(ambient_id, true)
	if record.is_empty():
		return false
	var renderer: Node = record.get("node")
	if not is_instance_valid(renderer):
		_report(
			&"renderer_instance_missing",
			ambient_id,
			"renderer instance is no longer valid"
		)
		return false
	if not renderer.has_method(interface_name):
		_report(
			&"missing_renderer_interface",
			ambient_id,
			"renderer does not implement '%s'" % interface_name,
			interface_name
		)
		return false
	renderer.callv(interface_name, arguments)
	return true


func _invoke_all_unique(interface_name: StringName, arguments: Array) -> bool:
	var success := true
	for renderer_key in _renderers:
		var record: Dictionary = _renderers[renderer_key]
		var ambient_ids: Array = record.get("ambient_ids", [])
		if ambient_ids.is_empty():
			continue
		success = _invoke(ambient_ids[0], interface_name, arguments) and success
	return success


func _record_for(ambient_id: StringName, report_unknown: bool) -> Dictionary:
	if not _routes.has(ambient_id):
		if report_unknown:
			_report(
				&"unknown_ambient_id",
				ambient_id,
				"ambient id is not registered"
			)
		return {}
	var renderer_key: StringName = _routes[ambient_id]["renderer_key"]
	return _renderers.get(renderer_key, {})


func _load_renderer_script(ambient_id: StringName, script_value: Variant) -> Script:
	if script_value is Script:
		return script_value
	var script_path := String(script_value)
	if script_path.is_empty() or not ResourceLoader.exists(script_path):
		_report(
			&"missing_renderer_script",
			ambient_id,
			"renderer script does not exist: %s" % script_path
		)
		return null
	var resource := load(script_path)
	if not resource is Script:
		_report(
			&"invalid_renderer_script",
			ambient_id,
			"renderer resource is not a Script: %s" % script_path
		)
		return null
	return resource


func _instantiate_renderer(ambient_id: StringName, renderer_script: Script) -> Node:
	var instance: Variant = renderer_script.new()
	if not instance is Node:
		_report(
			&"renderer_not_node",
			ambient_id,
			"renderer script must instantiate a Node"
		)
		return null
	var renderer: Node = instance
	renderer.name = "AmbientRenderer_%s" % String(ambient_id)
	add_child(renderer)
	return renderer


func _renderer_key_for_alias(renderer_alias: StringName) -> StringName:
	if _routes.has(renderer_alias):
		return _routes[renderer_alias]["renderer_key"]
	var shared_key := StringName("alias:%s" % renderer_alias)
	return shared_key if _renderers.has(shared_key) else &""


func _alias_is_resolvable(renderer_alias: StringName) -> bool:
	return not renderer_alias.is_empty() and not _renderer_key_for_alias(renderer_alias).is_empty()


func _script_id(renderer_script: Script) -> String:
	if not renderer_script.resource_path.is_empty():
		return renderer_script.resource_path
	return "script_instance_%d" % renderer_script.get_instance_id()


func _stable_variant(value: Variant) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value
		var keyed_entries: Array[Dictionary] = []
		for key in dictionary:
			keyed_entries.append({
				"sort_key": "%s:%s" % [typeof(key), var_to_str(key)],
				"original_key": key,
			})
		keyed_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["sort_key"]) < String(b["sort_key"])
		)
		var parts: Array[String] = []
		for entry: Dictionary in keyed_entries:
			var original_key: Variant = entry["original_key"]
			parts.append("%s:%s" % [
				entry["sort_key"],
				_stable_variant(dictionary[original_key]),
			])
		return "{%s}" % ",".join(parts)
	if value is Array:
		var array_parts: Array[String] = []
		for item in value:
			array_parts.append(_stable_variant(item))
		return "[%s]" % ",".join(array_parts)
	return "%s:%s" % [typeof(value), var_to_str(value)]


func _report(
	code: StringName,
	ambient_id: StringName,
	message: String,
	interface_name: StringName = &""
) -> void:
	_errors.append({
		"code": code,
		"ambient_id": ambient_id,
		"interface": interface_name,
		"message": message,
	})
