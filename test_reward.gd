extends SceneTree
## クリア時のご褒美画像の検証:
##  常に「そのステージの女の子」画像を使うこと。モンスター画像はパンクバー側の表示専用。

const MAIN_SCENE := preload("res://main.tscn")
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
	main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	main._start_game()

	# パニックバーがモンスター側に振れた状態
	main.panic = 0.2
	main.monster_mode = true

	var girl = main._reward_texture()
	var mon = main._monster_texture()
	var got = main._reward_texture_for_clear()

	ok(got == girl, "クリア時はステージの女の子画像(reward/galN_M)")
	ok(got != mon, "モンスター画像はクリア表示に使わない")
	ok(got != null, "画像が取得できている")

	# 女の子ごとに画像が変わる(=ステージに合わせて切り替わる)
	var t2 = null
	main.gal_index = 1
	main.stage_in_gal = 1
	t2 = main._reward_texture()
	ok(t2 != girl and t2 != null, "ステージ2(AYAMI)では別の女の子画像")

	# 写真パスは参照しない(素材廃止)
	var src := FileAccess.get_file_as_string("res://main.gd")
	ok(not src.contains("res://reward/photo"), "main.gd は photo パスを参照していない")

	# hud 側はモンスター画像を受け取る(バー側の脅威表示)
	main._sync_hud(0.0)
	ok(main.hud.monster_tex != null, "hud はモンスター画像を受け取る(バー側表示用)")

	print("---- %d checks, %d failed ----" % [checks, fails])
	quit(1 if fails > 0 else 0)
