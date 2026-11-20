extends SceneTree
## ゲーム全体のHEADレススモークテスト。
## 実行: godot --headless --path <プロジェクトdir> -s test_game.gd
## 終了コード 0 = OK。main.gd の状態遷移（プレイ→クリア→ルーレット→次ステージ→死亡→ゲームオーバー）を
## 実フレームで進めて確認する。陣取りの判定自体は test_territory.gd が保証している。

const MAIN_SCENE := preload("res://main.tscn")

var main
var frames := 0
var phase := 0
var checks := 0
var fails := 0
var plan: Array[Vector2i] = []
var last_note := ""


func _init() -> void:
	print("=== GALS PANIC SMOKE TEST ===")
	main = MAIN_SCENE.instantiate()
	root.add_child(main)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _process(_delta: float) -> bool:
	frames += 1
	match phase:
		0:
			if frames > 3:
				check(main.state == main.GState.ATTRACT, "起動するとアトラクトモード")
				main.credits = 4
				main._start_game()
				main.enemies.foes.clear()
				check(main.state == main.GState.PLAY, "START でプレイ開始")
				check(main.grid.get_cell(Vector2i(0, 0)) == main.grid.Cell.CLAIMED
						and main.grid.get_cell(Vector2i(240, 359)) == main.grid.Cell.CLAIMED,
						"外枠が初期陣（CLAIMED）")
				check(main.grid.count_claimed_playable() == 0, "内側の初期占有率は0%%")
				# SPACE（描画ボタン）を押しっぱなしにする
				var ev := InputEventKey.new()
				ev.keycode = KEY_SPACE
				ev.physical_keycode = KEY_SPACE
				ev.pressed = true
				Input.parse_input_event(ev)
				# 初手は下側の縁を左端まで歩く → そこから縦長の帯を順に抜く
				plan.clear()
				for i in (main.grid.player.x - 1):
					plan.append(Vector2i.LEFT)
				phase = 1
		1:
			# plan が尽きたら下側の縁から帯を抜く計画を足し続ける
			while plan.size() < 200 and main.state == main.GState.PLAY and main.grid.get_claim_ratio() < main.WIN_RATIO:
				var px: int = main.grid.player.x
				var n_up: int = main.grid.player.y - 2
				var n_right: int = mini(60, main.grid.width - 2 - px)
				if n_right < 4:
					break
				for i in n_up:
					plan.append(Vector2i.UP)
				for i in n_right:
					plan.append(Vector2i.RIGHT)
				for i in n_up:
					plan.append(Vector2i.DOWN)
				plan.append(Vector2i.RIGHT)
			# プレイヤーを1フレームに200ステップ進める
			var n := 0
			while not plan.is_empty() and n < 200:
				var d: Vector2i = plan[0]
				plan.pop_front()
				n += 1
				main._do_step(d)
				if main.state != main.GState.PLAY:
					plan.clear()
					break
			if main.state != main.GState.PLAY:
				check(main.state == main.GState.CLEAR, "占有率%d%%でクリア演出へ" % int(main.grid.get_claim_ratio() * 100.0))
				check(main.score > 100000, "クリアでスコアが入った (%d)" % main.score)
				phase = 2
			elif frames % 60 == 0:
				print("  ... playing, claim=%f%%  score=%d  plan=%d" % [main.grid.get_claim_ratio() * 100.0, main.score, plan.size()])
			if frames > 4000:
				check(false, "クリアが早すぎる/遅すぎる (frames=%d)" % frames)
				return true
		2:
			# クリア演出 → ルーレット
			if frames % 120 == 0:
				print("  ... clear_phase=%d reveal=%s t=%.2f state=%d frames=%d" % [main.clear_phase, main.reveal.state, main.reveal.t, main.state, frames])
			if main.state == main.GState.ROULETTE:
				check(true, "クリア演出後にルーレットへ (frames=%d)" % frames)
				main.roulette.press()
				phase = 3
			elif frames > 1500:
				check(false, "ルーレットが始まらない (state=%d)" % main.state)
				return true
		3:
			# 2回目のボタンで減速を開始させる
			if frames % 25 == 0:
				main.roulette.press()
			# ルーレットが止まるのを待つ
			if main.state == main.GState.PLAY:
				check(main.stage_number == 1 and main.gal_index == 0 and main.stage_in_gal == 2, "ルーレット後に次のステージへ (%s ST%d LV%d)" % [main.GALS[main.gal_index], main.stage_number + 1, main.stage_in_gal])
				check(main.grid.get_claim_ratio() < 0.02, "新ステージは盤面リセット")
				phase = 4
			elif frames > 3300:
				check(false, "ルーレットが止まらない (state=%d)" % main.state)
				return true
		4:
			# 死亡 → 残機減少 → ゲームオーバー
			var lives_before: int = main.lives
			main._lose_life("TEST HIT", true)
			check(main.state == main.GState.DYING, "被弾で DYING")
			check(main.lives == lives_before - 1, "残機が1減った")
			check(not main.grid.drawing, "被弾で線はキャンセル済み")
			main.lives = 1
			main.time_left = 0.001
			phase = 5
		5:
			if main.state == main.GState.DYING:
				pass
			elif main.state == main.GState.OVER:
				check(true, "TIME UP で残機0 → ゲームオーバー")
				phase = 6
			elif frames > 3400:
				check(false, "ゲームオーバーにならない (state=%d)" % main.state)
				return true
		6:
			main._enter_attract()
			check(main.state == main.GState.ATTRACT, "R でアトラクトへ戻れる")
			phase = 7
		7:
			# アトラクトの自動デモを回す
			if frames > 4400:
				var ratio: float = main.grid.get_claim_ratio()
				check(ratio > 0.001, "アトラクトの自動デモで陣が増えた (%f)" % ratio)
				check(main.grid.count_claimed_playable() == roundi(ratio * (main.grid.width - 2) * (main.grid.height - 2)),
						"占有率カウンタが数え直しと一致")
				# モンスター化の挙動
				main.panic = 0.1
				main._update_monster_state()
				check(main.monster_mode, "パニックバー低下でモンスター化")
				main.panic = 0.9
				main._update_monster_state()
				check(not main.monster_mode, "パニックバー回復で女の子に戻る")
				print("---- %d checks, %d failed ----" % [checks, fails])
				return true
	return false
