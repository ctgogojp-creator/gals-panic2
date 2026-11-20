extends SceneTree
## ステージ進行が gal1_1 → gal1_2 → gal1_3 → gal2_1 ... の順で
## 用意した画像をすべて使うようになっているかの検証。

const GALS := 6
const PER := 3

var checks := 0
var fails := 0
var main


func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: " + msg)
	else:
		print("OK: " + msg)


func _init() -> void:
	main = preload("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main._start_game()
	main.enemies.foes.clear()

	var seq: Array = []
	var used_bg: Array = []
	var used_reward: Array = []
	for st in GALS * PER:
		main.stage_number = st
		main._start_stage()
		var g: int = int(st / PER) % GALS
		var l: int = (st % PER) + 1
		seq.append("%s %d-%d" % [main.GALS[main.gal_index], main.gal_index + 1, main.stage_in_gal])
		ok(main.gal_index == g and main.stage_in_gal == l,
			"ST%02d -> gal%d_%d (%s)" % [st + 1, g + 1, l, main.hud.stage_label])
		used_bg.append("res://bg/gal%d_%d.png" % [g + 1, l])
		used_reward.append("res://reward/gal%d_%d.png" % [g + 1, l])
		ok(ResourceLoader.exists("res://bg/gal%d_%d.png" % [g + 1, l]),
			"bg/gal%d_%d.png がある" % [g + 1, l])
		ok(ResourceLoader.exists("res://reward/gal%d_%d.png" % [g + 1, l]),
			"reward/gal%d_%d.png がある" % [g + 1, l])
		ok(ResourceLoader.exists("res://mask/gal%d_%d.png" % [g + 1, l]),
			"mask/gal%d_%d.png がある" % [g + 1, l])

	print("進行: " + ", ".join(seq))
	ok(seq[0] == "MARINA 1-1" and seq[1] == "MARINA 1-2" and seq[2] == "MARINA 1-3"
		and seq[3] == "AYAMI 2-1", "1-1 → 1-2 → 1-3 → 2-1 の順")

	# 18ステージ目で ALL CLEAR になるか
	main.stage_number = GALS * PER - 1
	main._start_stage()
	main._begin_clear()
	var guard := 0
	while main.state != main.GState.CLEAR and guard < 4000:
		guard += 1
		await process_frame
		if main.reveal and main.reveal.visible:
			main.reveal.dismiss()
	ok(main.state == main.GState.CLEAR, "18ステージ目でクリア扱い")

	print("---- %d checks, %d failed ----" % [checks, fails])
	quit(1 if fails > 0 else 0)
