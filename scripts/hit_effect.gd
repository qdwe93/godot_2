extends Sprite2D
class_name HitEffect

@export var frames_per_second: float = 40.0
@export var effect_scale: float = 0.35
@export var tint: Color = Color(1, 1, 1, 1)
@export var texture_columns: int = 6
@export var texture_rows: int = 4

var _elapsed: float = 0.0


func _ready() -> void:
	hframes = max(1, texture_columns)
	vframes = max(1, texture_rows)
	scale = Vector2.ONE * effect_scale
	modulate = tint
	frame = 0


func _process(delta: float) -> void:
	_elapsed += delta
	var total_frames: int = hframes * vframes
	var next_frame: int = int(floor(_elapsed * frames_per_second))
	if next_frame >= total_frames:
		queue_free()
		return
	frame = next_frame


func configure(at_position: Vector2, colour: Color, size_scale: float) -> void:
	position = at_position
	tint = colour
	effect_scale = size_scale
	# Set these immediately as well as in _ready(), so configuration is useful
	# both before and after the node enters the tree.
	modulate = tint
	scale = Vector2.ONE * effect_scale

