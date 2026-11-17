extends Node

# ذخیره‌ی محلی: سکه و رکورد. بعداً با سرور همگام می‌شود.
const PATH := "user://save.cfg"

var coins := 0
var best_score := 0


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		coins = cf.get_value("player", "coins", 0)
		best_score = cf.get_value("player", "best_score", 0)


func get_coins() -> int:
	return coins


func add_coins(amount: int) -> void:
	coins += amount
	_save()


func spend_coins(amount: int) -> bool:
	if amount > coins:
		return false
	coins -= amount
	_save()
	return true


func set_best(score: int) -> void:
	if score > best_score:
		best_score = score
		_save()


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "coins", coins)
	cf.set_value("player", "best_score", best_score)
	cf.save(PATH)
