extends Node

# ذخیره‌ی محلی: سکه، رکورد، تنظیمات، پوسته‌ها و بازی نیمه‌تمام.
const PATH := "user://save.cfg"

var coins := 0
var best_score := 0
var muted := false
var volume := 0.8
var skin := 0
var owned: Array = [0]
var avatar := 0
var line_acc := 0
var game: Dictionary = {}


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		coins = cf.get_value("player", "coins", 0)
		best_score = cf.get_value("player", "best_score", 0)
		muted = cf.get_value("player", "muted", false)
		volume = cf.get_value("player", "volume", 0.8)
		skin = cf.get_value("player", "skin", 0)
		owned = cf.get_value("player", "owned", [0])
		avatar = cf.get_value("player", "avatar", 0)
		line_acc = cf.get_value("player", "line_acc", 0)
		game = cf.get_value("player", "game", {})


func get_coins() -> int:
	return coins


func add_coins(amount: int) -> void:
	coins += amount
	save()


func spend_coins(amount: int) -> bool:
	if amount > coins:
		return false
	coins -= amount
	save()
	return true


func set_best(score: int) -> void:
	if score > best_score:
		best_score = score
		save()


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "coins", coins)
	cf.set_value("player", "best_score", best_score)
	cf.set_value("player", "muted", muted)
	cf.set_value("player", "volume", volume)
	cf.set_value("player", "skin", skin)
	cf.set_value("player", "owned", owned)
	cf.set_value("player", "avatar", avatar)
	cf.set_value("player", "line_acc", line_acc)
	cf.set_value("player", "game", game)
	cf.save(PATH)
