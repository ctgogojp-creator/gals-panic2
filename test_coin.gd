extends SceneTree
## コイン上限 / ゲームオーバー10カウント / 続きプレイ / ご褒美画像 の検証

const MAIN_SCENE := preload("res://main.tscn")

var main: Node
var frames := 0
var checks := 0
var fails := 0
var phase := 0
var armed := false
var settle := 0
var save_score := 0
var save_gal := 0
var save_credits := 0

func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok:
		print("OK    " + msg)
	else:
		fails += 1
		print("FAIL  " + msg)

func key(k: int, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = pressed
	Input.parse_input_event(e)

func tap(k: int) -> void:
	key(k, true)
	key(k, false)

func _init() -> void:
	main = MAIN_SCENE.instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	frames += 1
	if frames < 4:
		return false

	# --- フェーズ1: コインを 14 枚入れて上限を確認 ---
	if phase == 0:
		if frames % 3 == 0:
			tap(KEY_5)
		if frames > 60:
			check(main.credits == main.MAX_CREDITS,
					"コインは %d までしか入らない (actual %d)" % [main.MAX_CREDITS, main.credits])
			phase = 1

	# --- フェーズ2: スタートして即死を繰り返しゲームオーバー、残りコインを確認 ---
	if phase == 1:
		tap(KEY_1)
		if main.state == main.GState.PLAY:
			phase = 2

	# --- フェーズ3: 残機を全部失わせてゲームオーバーにする ---
	if phase == 2:
		if not armed:
			armed = true
			main.lives = 1
			main._lose_life("TEST")
		if main.state == main.GState.OVER:
			check(main.over_count > 9.0, "ゲームオーバーで10カウント開始 (actual %.1f)" % main.over_count)
			armed = false
			phase = 3

	# --- フェーズ4: コインを入れて START → 続きから ---
	if phase == 3:
		var before_score: int = main.score
		var before_gal: int = main.gal_index
		var before_credits: int = main.credits
		tap(KEY_1)
		armed = true
		settle = frames
		phase = 31
		save_score = before_score
		save_gal = before_gal
		save_credits = before_credits
	if phase == 31:
		if frames > settle + 6:
			check(main.state == main.GState.PLAY, "START で続きから再開 (state=%d)" % main.state)
			check(main.lives == main.START_LIVES, "続きで残機が戻る (lives=%d)" % main.lives)
			check(main.score == save_score, "スコアはそのまま (%d)" % main.score)
			check(main.gal_index == save_gal, "ステージ進行はそのまま (gal=%d)" % main.gal_index)
			check(main.credits == save_credits - 1, "コインを1枚消費 (%d -> %d)" % [save_credits, main.credits])
			armed = false
			phase = 4

	# --- フェーズ5: コイン 0 でゲームオーバー → START では続けない → 10カウントでアトラクト ---
	if phase == 4:
		if not armed:
			armed = true
			main.credits = 0
			main.lives = 1
			main._lose_life("TEST")
		if main.state == main.GState.OVER:
			tap(KEY_1)
			settle = frames
			armed = true
			phase = 41

	if phase == 41:
		if frames > settle + 8:
			check(main.state == main.GState.OVER, "コインなしでは続けない (state=%d)" % main.state)
			check(main.credits == 0, "コイン 0 を維持 (credits=%d)" % main.credits)
			armed = false
			phase = 5

	if phase == 5:
		if frames % 120 == 0:
			print("  ... over_count=%.2f state=%d msg='%s' frames=%d" % [main.over_count, main.state, main.hud.message, frames])
		if main.state == main.GState.ATTRACT:
			check(true, "10カウント後にアトラクトへ戻った (frames=%d)" % frames)
			phase = 6

	# --- フェーズ6: クリア → ご褒美画像（シェーダに reward が設定される） ---
	if phase == 6:
		main.credits = 5
		main._start_game()
		main.enemies.setup(1, 0, 0, 0, 0, 0, main.grid)
		for i in main.grid.cells.size():
			main.grid.cells[i] = 1
		main.dirty = true
		main._begin_clear()
		phase = 7

	if phase == 7:
		if main.clear_phase >= 1:
			var m: ShaderMaterial = main.reveal.mat
			var tex: Variant = m.get_shader_parameter("reward")
			check(tex != null, "ご褒美画像がシェーダに設定されている (reward=%s)" % str(tex != null))
			check(main.reveal.sprite.texture != null, "ご褒美画像がスプライトに設定されている")
			var img: Image = main.reveal.sprite.texture.get_image()
			var mid: Color = img.get_pixel(img.get_width() / 2, img.get_height() / 2)
			var not_blank: bool = not (mid.r > 0.97 and mid.g > 0.97 and mid.b > 0.97)
			check(not_blank, "ご褒美画像が白抜きではない (center=%.2f,%.2f,%.2f)" % [mid.r, mid.g, mid.b])
			phase = 8

	if phase == 8:
		if main.state == main.GState.ROULETTE:
			check(true, "ご褒美画像の後にルーレットへ")
			phase = 9

	if phase == 9:
		if frames % 40 == 0:
			print("  ... wheel=%s angle=%.2f speed=%.2f state=%d frames=%d" % [main.roulette.state, main.roulette.angle, main.roulette.spin_speed, main.state, frames])
			tap(KEY_SPACE)
		if main.state == main.GState.PLAY:
			check(true, "ルーレット後に次のステージへ")
			print("---- %d checks, %d failed ----" % [checks, fails])
			quit(1 if fails > 0 else 0)
			return true

	if frames > 7000:
		print("TIMEOUT phase=%d state=%d clear_phase=%d" % [phase, main.state, main.clear_phase])
		print("---- %d checks, %d failed ----" % [checks, fails])
		quit(1)
		return true
	return false
