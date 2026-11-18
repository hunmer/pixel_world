extends Node2D

const WORLD_RECT := Rect2(-960.0, -540.0, 1920.0, 1080.0)
const GRID_SIZE := 64

@onready var player_sprite: AnimatedSprite2D = $Player/AnimatedSprite2D
@onready var character_name: Label = $UI/CharacterName

var character_paths: Array[String] = []
var character_index := 0


func _ready() -> void:
    queue_redraw()
    _find_character_sheets()
    _apply_character(0)


func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return

    if event.physical_keycode == KEY_Q:
        _apply_character(character_index - 1)
    elif event.physical_keycode == KEY_E:
        _apply_character(character_index + 1)


func _find_character_sheets() -> void:
    var directory := DirAccess.open("res://")
    if directory == null:
        return

    for file_name in directory.get_files():
        if file_name.to_lower().ends_with(".png"):
            character_paths.append("res://" + file_name)
    character_paths.sort()


func _apply_character(index: int) -> void:
    if character_paths.is_empty():
        character_name.text = "未找到角色 PNG"
        return

    character_index = posmod(index, character_paths.size())
    var texture := load(character_paths[character_index]) as Texture2D
    if texture == null:
        return

    for animation_name in player_sprite.sprite_frames.get_animation_names():
        var frame_count := player_sprite.sprite_frames.get_frame_count(animation_name)
        for frame_index in range(frame_count):
            var frame_texture := player_sprite.sprite_frames.get_frame_texture(animation_name, frame_index)
            if frame_texture is AtlasTexture:
                frame_texture.atlas = texture

    character_name.text = "%d / %d  %s" % [
        character_index + 1,
        character_paths.size(),
        character_paths[character_index].get_file()
    ]


func _draw() -> void:
    draw_rect(WORLD_RECT, Color("182536"), true)

    for x in range(int(WORLD_RECT.position.x), int(WORLD_RECT.end.x) + 1, GRID_SIZE):
        draw_line(
            Vector2(x, WORLD_RECT.position.y),
            Vector2(x, WORLD_RECT.end.y),
            Color("23364a"),
            1.0
        )

    for y in range(int(WORLD_RECT.position.y), int(WORLD_RECT.end.y) + 1, GRID_SIZE):
        draw_line(
            Vector2(WORLD_RECT.position.x, y),
            Vector2(WORLD_RECT.end.x, y),
            Color("23364a"),
            1.0
        )

    draw_rect(WORLD_RECT, Color("5b7896"), false, 4.0)
