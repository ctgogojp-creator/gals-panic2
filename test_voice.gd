extends SceneTree
## ステージクリア時にご褒美画像の約1秒後へ女の子音声を流す仕様の検証。
## 音声は audio/voice/galN_M.mp3(そのステージの女の子)を使う。

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

	# 18ステージ分の音声ファイルが揃っているか
	var missing: Array = []
	for g in GALS:
		for l in range(1, PER + 1):
			var path := "res://audio/voice/gal%d_%d.mp3" % [g + 1, l]
			if not ResourceLoader.exists(path):
				missing.append(path)
	ok(missing.is_empty(), "galN_M.mp3 が18枚揃っている (%s)" % str(missing))

	main._start_game()
	main.enemies.foes.clear()
	main._begin_clear()

	var seen_pending := ""
	var fired := false
	var played_stream: bool = false
	var game_time := 0.0
	var fired_at := 0.0
	var frame := 0
	while frame < 4000:
		frame += 1
		await process_frame
		var dt: float = main.get_process_delta_time()
		if main.clear_phase == 1 and not fired and seen_pending == "":
			seen_pending = main.voice_pending
			game_time = 0.0
		if main.clear_phase == 1 and seen_pending != "" and main.voice_pending == "" and not fired:
			fired = true
			fired_at = game_time
			played_stream = main.audio._voices.stream != null
			break
		if seen_pending != "":
			game_time += dt

	ok(seen_pending == "gal1_1", "1-1 クリアの音声は gal1_1 (got %s)" % seen_pending)
	ok(fired, "音声が再生された")
	ok(fired_at > 0.7 and fired_at < 1.8,
		"全裸画像表示から約1秒後 (%.2fs)" % fired_at)
	ok(played_stream, "mp3 がストリームに載っている")
	ok(main.audio._voices.playing, "音声プレイヤーが再生中")

	# ステージが変われば音声も変わる
	main.stage_number = 4
	main._start_stage()
	main._begin_clear()
	var pend2 := ""
	var f2 := 0
	while f2 < 400:
		f2 += 1
		await process_frame
		if main.clear_phase == 1:
			pend2 = main.voice_pending
			if pend2 != "":
				break
	ok(pend2 == "gal2_2", "2-2 クリアの音声は gal2_2 (got %s)" % pend2)

	# ALL CLEAR でもそのステージの音声になる
	main.stage_number = 17
	main._start_stage()
	main.voice_pending = ""
	main._all_clear()
	var pend3 := ""
	var f3 := 0
	while f3 < 400:
		f3 += 1
		await process_frame
		if main.voice_pending != "":
			pend3 = main.voice_pending
			break
	ok(pend3 == "gal6_3", "ALL CLEAR の音声は gal6_3 (got %s)" % pend3)

	# ステージ開始時は pending を消す(古い音声が流れない)
	main.voice_pending = "stale"
	main._start_stage()
	ok(main.voice_pending == "", "ステージ開始で pending クリア")

	print("---- %d checks, %d failed ----" % [checks, fails])
	quit(1 if fails > 0 else 0)
