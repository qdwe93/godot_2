extends Node

var level: int = 1
var experience: float = 0.0

signal experience_changed(current: float, required: float, level: int)
signal leveled_up(new_level: int)


func required_for_next_level() -> float:
	return 5.0 + float(level - 1) * 3.0


func add_experience(amount: float) -> void:
	experience += amount
	while experience >= required_for_next_level():
		experience -= required_for_next_level()
		level += 1
		leveled_up.emit(level)
	experience_changed.emit(experience, required_for_next_level(), level)
