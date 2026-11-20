extends SceneTree
## パニックバーの「モンスター領域はランダム秒後にGAL側へ戻る」検証。
## 条件: バーが最後まで振り切れる前に、最低5秒は残して必ず戻す。

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

	# しきい値ぎりぎりまで振る -> モンスター領域に入る
	main.panic = 0.34
	main._update_monster_state(0.0)
	ok(main.monster_mode == true, "モンスター領域に入るとモンスター表示になる")

	var hold: float = main.monster_hold
	var drain: float = main._panic_drain()
	var to_end: float = 0.34 / maxf(drain, 0.0001)
	ok(hold > 0.0, "ランダム秒数が決まる (hold=%.1fs / 振り切りまで %.0fs)" % [hold, to_end])
	ok(hold <= to_end - 5.0 + 0.01, "振り切る5秒前までには戻る")

	# ランダム秒数が経過 -> GAL側へ戻る
	var sim := 0.0
	var guard := 0
	while main.monster_mode and guard < 40000:
		guard += 1
		sim += 0.05
		main._update_monster_state(0.05)
	ok(main.monster_mode == false, "ランダム秒後にGAL側へ戻った (経過 %.1fs)" % sim)
	ok(main.panic > 0.52, "バーがGAL側を向いている (%.2f)" % main.panic)

	# 乱数なので複数回分布を見る
	var vals: Array = []
	for i in 5:
		main.monster_mode = false
		main.panic = 0.34
		main._update_monster_state(0.0)
		vals.append(round(main.monster_hold * 10.0) / 10.0)
	print("hold samples: %s" % str(vals))
	var uniq := {}
	for v in vals:
		uniq[v] = true
	ok(uniq.size() > 1, "秒数はランダム")

	# モンスター画像
	var mt = main._monster_texture()
	ok(mt != null, "モンスター画像が読み込めている")
	ok(mt != main._reward_texture(), "モンスター画像は女の子画像と別物")

	print("---- %d checks, %d failed ----" % [checks, fails])
	quit(1 if fails > 0 else 0)
