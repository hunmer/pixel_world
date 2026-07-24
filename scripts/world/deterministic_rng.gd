class_name DeterministicRng
extends RefCounted

## Stable, stateless random samples for world generation.
##
## New systems should identify their random stream by name. During migration,
## callers may also pass the old integer salt; when present it takes precedence
## and `cell_float()` reproduces the legacy `_cell_rand()` calculation exactly.

const U32_MASK := 0xFFFFFFFF
const U32_MAX_FLOAT := 4294967295.0
const CELL_X_FACTOR := 0x8DA6B343
const CELL_Y_FACTOR := 0xD8163841
const SAMPLE_FACTOR := 0x9E3779B9
const FNV_OFFSET_BASIS := 0x811C9DC5
const FNV_PRIME := 0x01000193

var world_seed: int


func _init(initial_world_seed: int = 0) -> void:
	world_seed = initial_world_seed


## Matches the lowbias32 hash used by the existing world generator.
static func hash_u32(value: int) -> int:
	value = (value ^ (value >> 16)) & U32_MASK
	value = (value * 0x7FEB352D) & U32_MASK
	value = (value ^ (value >> 15)) & U32_MASK
	value = (value * 0x846CA68B) & U32_MASK
	value = (value ^ (value >> 16)) & U32_MASK
	return value


## FNV-1a over UTF-8 bytes avoids relying on engine/runtime String.hash().
static func stable_stream_salt(stream_id: StringName) -> int:
	var hash_value := FNV_OFFSET_BASIS
	for byte_value in String(stream_id).to_utf8_buffer():
		hash_value = (
			((hash_value ^ int(byte_value)) * FNV_PRIME)
			& U32_MASK
		)
	return hash_value


static func resolve_stream_salt(
	stream_id: StringName,
	legacy_salt: Variant = null
) -> int:
	if legacy_salt != null:
		return int(legacy_salt)
	return stable_stream_salt(stream_id)


## Raw 32-bit sample. `sample_index == 0` with a legacy salt is byte-for-byte
## compatible with the old cell random input and output hash.
func cell_u32(
	cell: Vector2i,
	stream_id: StringName,
	legacy_salt: Variant = null,
	sample_index: int = 0
) -> int:
	var salt := resolve_stream_salt(stream_id, legacy_salt)
	var sample_offset := sample_index * SAMPLE_FACTOR if sample_index != 0 else 0
	return hash_u32(
		cell.x * CELL_X_FACTOR
		^ cell.y * CELL_Y_FACTOR
		^ (world_seed + salt + sample_offset)
	)


func cell_float(
	cell: Vector2i,
	stream_id: StringName,
	legacy_salt: Variant = null,
	sample_index: int = 0
) -> float:
	return (
		float(cell_u32(cell, stream_id, legacy_salt, sample_index))
		/ U32_MAX_FLOAT
	)


func cell_bool(
	cell: Vector2i,
	stream_id: StringName,
	chance: float,
	legacy_salt: Variant = null,
	sample_index: int = 0
) -> bool:
	return cell_float(cell, stream_id, legacy_salt, sample_index) < clampf(chance, 0.0, 1.0)


## Returns an integer in [minimum_inclusive, maximum_exclusive).
func cell_int(
	cell: Vector2i,
	stream_id: StringName,
	minimum_inclusive: int,
	maximum_exclusive: int,
	legacy_salt: Variant = null,
	sample_index: int = 0
) -> int:
	assert(maximum_exclusive > minimum_inclusive)
	var span := maximum_exclusive - minimum_inclusive
	return minimum_inclusive + int(
		cell_u32(cell, stream_id, legacy_salt, sample_index) % span
	)
