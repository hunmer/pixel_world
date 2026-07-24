class_name CommunityStateStore
extends RefCounted

## Bounded runtime state for deterministic ecology communities.
##
## Community values stay untouched: LRU, pinning, and active-member bookkeeping
## live in a separate metadata table. This lets callers cache a deterministic
## plan without leaking runtime state into that plan.
##
## Entries with a pin count or active members are protected from eviction. If
## every entry is protected the store may temporarily exceed `max_entries`; it
## shrinks again as soon as an entry becomes inactive/unpinned.

const DEFAULT_MAX_ENTRIES := 2048

var max_entries: int:
	get:
		return _max_entries
	set(value):
		_max_entries = maxi(0, value)
		_shrink_to_limit()

var _max_entries := DEFAULT_MAX_ENTRIES
var _values := {}
var _metadata := {}
var _access_clock := 0


func _init(initial_max_entries: int = DEFAULT_MAX_ENTRIES) -> void:
	_max_entries = maxi(0, initial_max_entries)


func has(key: Variant) -> bool:
	return _values.has(_storage_key(key))


## Reads and refreshes the entry's LRU position, like a cache lookup.
##
## Godot reserves Object.get(StringName), so generic/default-value lookups use
## this explicit method. String community IDs also work with native `get(id)`
## through `_get` below, preserving the familiar Dictionary-like call site.
func get_value(key: Variant, default_value: Variant = null) -> Variant:
	var stored_key: Variant = _storage_key(key)
	if not _values.has(stored_key):
		return default_value
	touch(stored_key)
	return _values[stored_key]


func _get(property: StringName) -> Variant:
	return get_value(property)


func _set(property: StringName, value: Variant) -> bool:
	set_or_put(property, value)
	return true


## Adds or replaces an entry without changing its deterministic value shape.
##
## `pin_entry` and `active_members` allow a newly inserted active group to be
## protected atomically, before capacity enforcement runs. For an existing
## entry, omitted active-members (-1) preserves its current runtime count.
func set_or_put(
	key: Variant,
	value: Variant,
	pin_entry: bool = false,
	active_members: int = -1
) -> Variant:
	var stored_key: Variant = _storage_key(key)
	var existed := _values.has(stored_key)
	_values[stored_key] = value
	if not existed:
		_metadata[stored_key] = {
			"last_access": _next_access(),
			"pin_count": 1 if pin_entry else 0,
			"active_members": maxi(0, active_members),
		}
	else:
		var metadata: Dictionary = _metadata[stored_key]
		metadata["last_access"] = _next_access()
		if pin_entry:
			# Atomic protection is idempotent; explicit pin() is reference-counted.
			metadata["pin_count"] = maxi(1, int(metadata.get("pin_count", 0)))
		if active_members >= 0:
			metadata["active_members"] = active_members
	_shrink_to_limit()
	return value if _values.has(stored_key) else null


## Refreshes an entry without reading or rewriting its value.
func touch(key: Variant) -> bool:
	var stored_key: Variant = _storage_key(key)
	if not _values.has(stored_key):
		return false
	var metadata: Dictionary = _metadata[stored_key]
	metadata["last_access"] = _next_access()
	return true


## Explicit removal ignores pin/active protection, matching Dictionary.erase.
func erase(key: Variant) -> bool:
	var stored_key: Variant = _storage_key(key)
	if not _values.has(stored_key):
		return false
	_values.erase(stored_key)
	_metadata.erase(stored_key)
	return true


func clear() -> void:
	_values.clear()
	_metadata.clear()
	_access_clock = 0


func size() -> int:
	return _values.size()


func is_empty() -> bool:
	return _values.is_empty()


func keys() -> Array:
	return _values.keys()


## Reference-counted protection for callers with overlapping ownership.
func pin(key: Variant) -> bool:
	var stored_key: Variant = _storage_key(key)
	if not _values.has(stored_key):
		return false
	var metadata: Dictionary = _metadata[stored_key]
	metadata["pin_count"] = int(metadata.get("pin_count", 0)) + 1
	metadata["last_access"] = _next_access()
	return true


func unpin(key: Variant) -> bool:
	var stored_key: Variant = _storage_key(key)
	if not _values.has(stored_key):
		return false
	var metadata: Dictionary = _metadata[stored_key]
	metadata["pin_count"] = maxi(0, int(metadata.get("pin_count", 0)) - 1)
	metadata["last_access"] = _next_access()
	_shrink_to_limit()
	return true


func pin_count(key: Variant) -> int:
	var stored_key: Variant = _storage_key(key)
	if not _metadata.has(stored_key):
		return 0
	return int((_metadata[stored_key] as Dictionary).get("pin_count", 0))


## Active-member protection is count-based so partial stream unloads are safe.
func set_active_member_count(key: Variant, count: int) -> bool:
	var stored_key: Variant = _storage_key(key)
	if not _values.has(stored_key):
		return false
	var metadata: Dictionary = _metadata[stored_key]
	metadata["active_members"] = maxi(0, count)
	metadata["last_access"] = _next_access()
	_shrink_to_limit()
	return true


func set_active_members(key: Variant, count: int) -> bool:
	return set_active_member_count(key, count)


func increment_active_members(key: Variant, amount: int = 1) -> bool:
	if not has(key):
		return false
	return set_active_member_count(key, active_member_count(key) + maxi(0, amount))


func decrement_active_members(key: Variant, amount: int = 1) -> bool:
	if not has(key):
		return false
	return set_active_member_count(key, active_member_count(key) - maxi(0, amount))


func active_member_count(key: Variant) -> int:
	var stored_key: Variant = _storage_key(key)
	if not _metadata.has(stored_key):
		return 0
	return int((_metadata[stored_key] as Dictionary).get("active_members", 0))


func is_protected(key: Variant) -> bool:
	return pin_count(key) > 0 or active_member_count(key) > 0


func _next_access() -> int:
	_access_clock += 1
	return _access_clock


func _shrink_to_limit() -> void:
	while _values.size() > _max_entries:
		var candidate: Array = _least_recent_inactive_key()
		if not bool(candidate[0]):
			# All entries are live. Capacity is a cache bound, never a reason to
			# invalidate a currently active community.
			return
		_values.erase(candidate[1])
		_metadata.erase(candidate[1])


func _least_recent_inactive_key() -> Array:
	var found := false
	var oldest_access := 0
	var oldest_key: Variant = null
	for key in _values.keys():
		var metadata: Dictionary = _metadata[key]
		if (
			int(metadata.get("pin_count", 0)) > 0
			or int(metadata.get("active_members", 0)) > 0
		):
			continue
		var last_access := int(metadata.get("last_access", 0))
		if not found or last_access < oldest_access:
			found = true
			oldest_access = last_access
			oldest_key = key
	return [found, oldest_key]


func _storage_key(key: Variant) -> Variant:
	if key is String or key is StringName:
		return StringName(key)
	return key
