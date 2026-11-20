extends Node2D
## ギャルズパニック (Gals Panic / Kaneko 1990 風) 本体。
##
## 線・囲み・占有率の判定は すべて territory_grid.gd (TerritoryGrid) が持つ。
## このファイルは step() の戻り値（BLOCKED/MOVEED/TRAIL_STARTED/DRAWING/CLOSED/SELF_CROSS）を
## 見て 演出・スコア・ライフを処理するだけ。
##
## 画面: 1920x1080 基準 / 盤面 480x360セル x 3px = 1440x1080 / 左右240pxはHUD
## 操作: 矢印=移動 / SPACE(押しながら)=線を引く / SPACE=ルーレット操作 / F11=フルスクリーン
##       5=COIN / 1=START / R=リセット / M=ミュート
##
## 素材:
##  res://bg.png                     … 盤面背景の差し替え用（あれば最優先）
##  res://bg/gal{1..6}_{1..3}.png   … ステージ画像（女の子の写真）
##  res://reward/gal{1..6}_{1..3}.png … クリア時のご褒美画像
##  res://mask/gal{1..6}_{1..3}.png … シルエットマスク(画像から生成)
##  res://reward/monster.png        … パンクバー側のモンスター表示用
##  res://title.png                 … タイトル画
##  res://audio/...                 … BGM / 効果音 / 声（audio_manager.gd 参照）
## 画像が無い場合はコード生成した代用画像を使い、ゲームはそのまま動く。

# ---------------------------------------------------------------- 定数

const VIEW_W := 1920
const VIEW_H := 1080
const GRID_W := 480
const GRID_H := 360
const CELL := 3
const ORIGIN := Vector2(240, 0)
const FIELD := Vector2(GRID_W * CELL, GRID_H * CELL)   # 1440x1080

const PLAYER_CELLS_PER_SEC := 100.0
const MAX_STEPS_PER_FRAME := 8
const WIN_RATIO := 0.8
const START_LIVES := 3
const MAX_LIVES := 6
const MAX_CREDITS := 10        # コインは最大10までストック
const OVER_COUNT := 10.0       # ゲームオーバー後のカウントダウン秒
const GALS := ["MARINA", "AYAMI", "NAMI", "YUKI", "EMI", "SHIORI"]
const STAGES_PER_GAL := 3

const ACTIONS := {
	"ui_up": Vector2i.UP, "ui_down": Vector2i.DOWN,
	"ui_left": Vector2i.LEFT, "ui_right": Vector2i.RIGHT,
}

enum GState { ATTRACT, PLAY, DYING, CLEAR, ROULETTE, OVER, ALLCLEAR }

enum Sym { STAR, LIFE, CLOCK, STORM, FROG, OCTOPUS, CURSE }

## 未取得の黒（＋シルエット）、取得済み（透明＝画像が見える）、縁の白線、引いている線の黄色
## …を GPU で描く。CPUで1ピクセルずつ塗る方式には戻さない。
const COVER_SHADER := """
shader_type canvas_item;
// TEXTURE : grid.cells を R8 で並べたもの 0=EMPTY 1=CLAIMED 2=TRAIL
uniform sampler2D mask : filter_nearest, repeat_disable;   // 255=女の子のシルエット
uniform sampler2D flash : filter_nearest, repeat_disable;  // 確定した瞬間に光るセル
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform float silhouette_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float c = floor(texture(TEXTURE, UV).r * 255.0 + 0.5);
	if (c > 1.5) {
		COLOR = vec4(1.0, 0.92, 0.25, 1.0);            // 引いている線
	} else if (c > 0.5) {
		bool edge = false;
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				float n = floor(texture(TEXTURE, UV + vec2(float(dx), float(dy)) * px).r * 255.0 + 0.5);
				if (n < 0.5) { edge = true; }
			}
		}
		float f = texture(flash, UV).r * flash_amount;
		if (edge) {
			COLOR = vec4(mix(vec3(1.0, 1.0, 1.0), vec3(1.0, 0.95, 0.7), f), 1.0);
		} else {
			COLOR = vec4(vec3(1.0, 0.9, 0.6) * f * 0.85, clamp(f * 0.9, 0.0, 1.0));
		}
	} else {
		float m = texture(mask, UV).r * silhouette_alpha;
		vec3 empty_bg = mix(vec3(0.055, 0.055, 0.11), vec3(0.01, 0.01, 0.03), m);
		COLOR = vec4(empty_bg, 1.0);
	}
}
"""

# ---------------------------------------------------------------- 変数

var grid: TerritoryGrid
var sil: Silhouette
var enemies: EnemyManager
var audio: AudioManager
var hud: Hud
var roulette: BonusRoulette
var reveal: RevealEffect

var board: Node2D
var actors: Node2D
var cover: Sprite2D
var title_art: Sprite2D

# 自動デモ（スクリーンショット検証用。--autodemo で有効化）
var demo_play := false
var auto_win_loop := false
var auto_win_timer := 0.0
var play_plan: Array = []
var play_i := 0
var play_left := 0
var play_dir := Vector2i.ZERO
var play_draw := false
var cover_img: Image
var cover_tex: ImageTexture
var mask_img: Image
var mask_tex: ImageTexture
var flash_img: Image
var flash_tex: ImageTexture
var cover_mat: ShaderMaterial
var bg_tex: Texture2D
var dirty := true

var state: int = GState.ATTRACT
var score := 0
var hi_score := 0
var lives := START_LIVES
var credits := 0
var over_count := 0.0
var over_last := -1
var over_banner: OverBanner
var auto_continue := false
var last_eroded := 0
var erode_msg := 0.0
var auto_wheel := false
var wheel_auto := 0.0
var gal_index := 0
var stage_in_gal := 1
var stage_number := 0
var time_max := 60.0
var time_left := 60.0
var panic := 0.78
var monster_mode := false
var monster_hold := 0.0   # モンスター領域に入ってからGAL側へ戻すまでの残り秒数(ランダム)
var score_mult := 1
var bonus_time := 0.0
var enemy_penalty := 1.0
var panic_penalty := 0.0
var pending_mult := 1
var pending_time := 0.0
var pending_penalty := 1.0
var pending_panic := 0.0
var pending_storm := false
var mask_bytes := PackedByteArray()
var freeze := 0.0
var clear_phase := 0
var clear_timer := 0.0
var voice_pending := ""
var voice_timer := 0.0
var flash_amount := 0.0
var trail_started_at := 0.0
var pre_cells := PackedByteArray()
var symbol_timer := 0.0
var symbols: Array[Dictionary] = []
var stage_total := 0
var time_warn := false
var attract_timer := 0.0
var demo_plan: Array[Vector2i] = []
var demo_dir := Vector2i.ZERO
var last_dir := Vector2i.ZERO
var step_acc := 0.0
var death_cause := ""
var _img_cache := {}


# ---------------------------------------------------------------- 準備

func _ready() -> void:
	randomize()
	grid = TerritoryGrid.new(GRID_W, GRID_H, true)
	sil = Silhouette.new(GRID_W, GRID_H)
	enemies = EnemyManager.new()

	audio = AudioManager.new()
	audio.name = "Audio"
	add_child(audio)

	hud = Hud.new()
	hud.name = "Hud"
	hud.z_index = 10
	add_child(hud)

	board = Node2D.new()
	board.name = "Board"
	add_child(board)

	cover = Sprite2D.new()
	cover.centered = false
	cover.position = ORIGIN
	cover.scale = Vector2(CELL, CELL)
	cover.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cover_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = COVER_SHADER
	cover_mat.shader = shader
	cover.material = cover_mat
	board.add_child(cover)

	actors = Node2D.new()
	actors.name = "Actors"
	actors.set_script(load("res://actors.gd"))
	actors.game = self
	board.add_child(actors)

	roulette = BonusRoulette.new()
	roulette.name = "Roulette"
	roulette.visible = false
	roulette.finished.connect(_on_roulette_finished)
	add_child(roulette)

	reveal = RevealEffect.new()
	reveal.name = "Reveal"
	reveal.visible = false
	reveal.finished.connect(_on_reveal_finished)
	add_child(reveal)

	mask_img = Image.create(GRID_W, GRID_H, false, Image.FORMAT_R8)
	mask_tex = ImageTexture.create_from_image(mask_img)
	flash_img = Image.create(GRID_W, GRID_H, false, Image.FORMAT_R8)
	flash_img.fill(0)
	flash_tex = ImageTexture.create_from_image(flash_img)
	cover_mat.set_shader_parameter("mask", mask_tex)
	cover_mat.set_shader_parameter("flash", flash_tex)

	over_banner = OverBanner.new()
	over_banner.name = "OverBanner"
	over_banner.z_index = 30
	add_child(over_banner)

	title_art = Sprite2D.new()
	title_art.name = "TitleArt"
	title_art.visible = false
	title_art.z_index = 5
	if AssetPaths.has("title.png"):
		title_art.texture = AssetPaths.texture("title.png")
		var t: Texture2D = title_art.texture
		var s := minf(1920.0 / float(t.get_width()), 1080.0 / float(t.get_height()))
		title_art.scale = Vector2(s, s)
		title_art.position = Vector2(960.0, 540.0)
	add_child(title_art)

	_enter_attract()

	for a in OS.get_cmdline_user_args():
		if a == "--autowin":
			credits = 9
			_start_game()
			enemies.setup(1, 0, 0, 0, 0, 0, grid)
			for i in grid.cells.size():
				grid.cells[i] = int(TerritoryGrid.Cell.CLAIMED)
			dirty = true
			auto_wheel = true
			_begin_clear()
		if a == "--autodie":
			credits = 3
			_start_game()
			enemies.setup(1, 0, 0, 0, 0, 0, grid)
			time_max = 3.0
			time_left = 3.0
			auto_continue = true
		if a == "--autostages":
			credits = 9
			_start_game()
			enemies.setup(1, 0, 0, 0, 0, 0, grid)
			auto_win_loop = true
			auto_win_timer = 4.0
			auto_wheel = true
		if a == "--monster":
			credits = 9
			_start_game()
			enemies.setup(1, 0, 0, 0, 0, 0, grid)
			demo_play = true
			panic = 0.30
			monster_hold = 999.0   # 検証用: 戻さない
		if a == "--autodemo":
			credits = 9
			_start_game()
			enemies.setup(1, 0, 0, 0, 0, 0, grid)
			demo_play = true
			play_i = 0
			play_left = 0
			play_plan = [
				"U1120", "R1120", "D1120",
				"R0120", "U1120", "R1120", "D1120",
				"R0120", "U1120", "R1120", "D1120",
				"L0600", "U1120", "L1120", "D1120",
			]


# ---------------------------------------------------------------- ステート遷移

func _enter_attract() -> void:
	state = GState.ATTRACT
	voice_pending = ""
	if over_banner != null:
		over_banner.show_it = false
		over_banner.queue_redraw()
	grid.reset()
	symbols.clear()
	demo_plan.clear()
	enemies.setup(1, 1, 2, 0, 0, 0, grid)
	enemies.speed_scale = 1.0
	attract_timer = 0.0
	_apply_stage_visuals(0, 1)
	_rebuild_cover()
	hud.demo = true
	hud.message = ""
	hud.set_message("PRESS START (ENTER)   5=COIN", 4.0)
	title_art.visible = title_art.texture != null
	audio.play_music("bgm_title")


func _start_game() -> void:
	if credits <= 0:
		hud.set_message("INSERT COIN  (KEY 5)", 2.0)
		audio.sfx("sfx_select")
		return
	credits -= 1
	score = 0
	lives = START_LIVES
	stage_number = 0
	gal_index = 0
	stage_in_gal = 1
	score_mult = 1
	bonus_time = 0.0
	enemy_penalty = 1.0
	panic_penalty = 0.0
	monster_hold = 0.0
	pending_mult = 1
	pending_time = 0.0
	pending_penalty = 1.0
	pending_panic = 0.0
	pending_storm = false
	hud.demo = false
	hud.combo = 1
	_start_stage()
	audio.play_voice("voice_start")


## ステージごとの敵構成。進行に応じて SAMSON / FROG / OCTOPUS が増える。
func _stage_composition(s: int) -> Dictionary:
	return {
		"big": mini(1 + int(s / 4), 4),
		"sparx": mini(2 + int(s / 2), 6),
		"samson": 0 if s < 2 else mini(1 + int((s - 2) / 3), 3),
		"frog": 0 if s < 3 else mini(1 + int((s - 3) / 4), 3),
		"octo": 0 if s < 4 else mini(1 + int((s - 4) / 4), 3),
	}


func _setup_enemies(seed_stage: int, g) -> void:
	var c := _stage_composition(seed_stage)
	enemies.big_speed = 38.0 + seed_stage * 2.6
	enemies.sparx_speed = 50.0 + seed_stage * 3.4
	enemies.samson_speed = 26.0 + seed_stage * 2.0
	enemies.frog_speed = 15.0 + seed_stage * 1.2
	enemies.octo_speed = 11.0 + seed_stage * 1.0
	enemies.setup(seed_stage + 7, int(c["big"]), int(c["sparx"]), int(c["samson"]),
			int(c["frog"]), int(c["octo"]), g)


func _start_stage() -> void:
	# ステージが進むたびに女の子が変わる (6人ローテ)。
	# ひと巡りごとに露出レベル(1→2→3)が上がり、3で写真になる。
	gal_index = int(stage_number / STAGES_PER_GAL) % GALS.size()
	stage_in_gal = (stage_number % STAGES_PER_GAL) + 1
	stage_total = stage_number
	voice_pending = ""
	title_art.visible = false
	grid.reset()
	symbols.clear()
	# ルーレットで出た「次のステージへの効果」をここで適用する
	score_mult = pending_mult
	bonus_time = pending_time
	enemy_penalty = pending_penalty
	panic_penalty = pending_panic
	var storm := pending_storm
	pending_mult = 1
	pending_time = 0.0
	pending_penalty = 1.0
	pending_panic = 0.0
	pending_storm = false
	time_max = clampf(72.0 - stage_total * 1.4, 42.0, 72.0)
	time_left = time_max + bonus_time
	panic = clampf(0.78 - panic_penalty, 0.2, 1.0)
	monster_mode = panic < 0.35
	monster_hold = 0.0
	enemies.speed_scale = enemy_penalty
	_setup_enemies(stage_total, grid)
	if storm:
		var n := enemies.kill_all()
		score += n * 1500
		hud.set_message("ASTEROID STORM!  x%d" % n, 2.4)
	_apply_stage_visuals(gal_index, stage_in_gal)
	_rebuild_cover()
	state = GState.PLAY
	step_acc = 0.0
	last_dir = Vector2i.ZERO
	time_warn = false
	hud.combo = 1
	hud.set_message("STAGE %d   %s   GO!" % [stage_number + 1, GALS[gal_index]], 2.2)
	hud.set_sub(enemies.roster_text(), 3.4)
	audio.play_music("bgm_stage")
	audio.sfx("sfx_life")


func _game_over() -> void:
	state = GState.OVER
	freeze = 0.0
	voice_pending = ""
	over_count = OVER_COUNT
	over_last = -1
	audio.stop_music()
	audio.play_music("bgm_over")
	audio.sfx("sfx_gameover")
	audio.play_voice("voice_gameover")
	hi_score = maxi(hi_score, score)


## ゲームオーバー中の「GAME OVER / CONTINUE? n」バナー。演出専用（判定には関与しない）。
class OverBanner:
	extends Node2D
	var show_it := false
	var count := 0
	var cr := 0
	func _draw() -> void:
		if not show_it:
			return
		var f := ThemeDB.fallback_font
		draw_rect(Rect2(240, 300, 1440, 470), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(240, 300, 1440, 470), Color(1, 0.35, 0.3, 0.9), false, 6.0)
		draw_string(f, Vector2(240, 430), "GAME OVER", HORIZONTAL_ALIGNMENT_CENTER, 1440, 110, Color(1, 0.25, 0.2))
		var blink := 0.55 + 0.45 * sin(float(Time.get_ticks_msec()) * 0.006)
		if count > 0:
			draw_string(f, Vector2(240, 560), "CONTINUE ?  %d" % count,
					HORIZONTAL_ALIGNMENT_CENTER, 1440, 76, Color(1, 0.95, 0.5, blink))
			draw_string(f, Vector2(240, 640), "5 = COIN      1 = START",
					HORIZONTAL_ALIGNMENT_CENTER, 1440, 40, Color(0.8, 0.9, 1.0))
			draw_string(f, Vector2(240, 710), "CREDIT  %d" % cr,
					HORIZONTAL_ALIGNMENT_CENTER, 1440, 40, Color(1, 0.9, 0.4))
		else:
			draw_string(f, Vector2(240, 580), "INSERT COIN",
					HORIZONTAL_ALIGNMENT_CENTER, 1440, 64, Color(1, 0.9, 0.4, blink))


## ゲームオーバー中の 10 カウント。間にコインを入れて START すると続きから。
func _update_over(delta: float) -> void:
	over_count = maxf(0.0, over_count - delta)
	var n := int(ceil(over_count))
	if n != over_last:
		over_last = n
		if n > 0:
			hud.set_message("CONTINUE?  %d   5=COIN  1=START" % n, 2.0)
			audio.sfx("sfx_time", 1.0 + float(10 - n) * 0.05)
		else:
			hud.set_message("GAME OVER", 2.0)
	if over_banner != null:
		over_banner.show_it = true
		over_banner.count = n
		over_banner.cr = credits
		over_banner.queue_redraw()
	if auto_continue and n == 5 and credits > 0:
		auto_continue = false
		credits -= 1
		_continue_game()
		return
	_update_enemies_idle(delta)
	if over_count <= 0.0:
		_enter_attract()


## 続きからプレイする（スコア・ステージ・占有率はそのまま、残機だけ戻す）
func _continue_game() -> void:
	if state != GState.OVER:
		return
	if credits <= 0:
		hud.set_message("INSERT COIN (5) TO CONTINUE", 2.0)
		audio.sfx("sfx_select")
		return
	credits -= 1
	hud.credits = credits
	lives = START_LIVES
	score_mult = 1
	hud.combo = 1
	hud.demo = false
	time_warn = false
	if over_banner != null:
		over_banner.show_it = false
		over_banner.queue_redraw()
	_start_stage()
	hud.set_message("CONTINUE!  STAGE %d   %s" % [stage_number + 1, GALS[gal_index]], 2.2)


# ---------------------------------------------------------------- 入力

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif event.keycode == KEY_M:
			hud.set_message("MUTE %s" % ("ON" if audio.toggle_mute() else "OFF"), 1.2)


func _handle_ui_input() -> void:
	if Input.is_action_just_pressed("coin"):
		if credits >= MAX_CREDITS:
			hud.set_message("MAX CREDIT %d" % MAX_CREDITS, 1.6)
			audio.sfx("sfx_select")
		else:
			credits += 1
			hud.credits = credits
			audio.sfx("sfx_select")
			if state == GState.ATTRACT:
				hud.set_message("CREDIT %d - PRESS START (1)" % credits, 2.5)
			elif state == GState.OVER:
				hud.set_message("CREDIT %d - PRESS START (1) TO CONTINUE" % credits, 2.5)
	if Input.is_action_just_pressed("start"):
		if state == GState.ATTRACT:
			_start_game()
		elif state == GState.OVER:
			_continue_game()
		elif state == GState.ALLCLEAR:
			_enter_attract()
	if Input.is_action_just_pressed("restart"):
		_enter_attract()
	if Input.is_action_just_pressed("draw"):
		if reveal.is_busy():
			reveal.dismiss()
		elif state == GState.ROULETTE:
			roulette.press()
			audio.sfx("sfx_wheel" if roulette.state == "spinning" else "sfx_select")
		elif state == GState.ATTRACT:
			_start_game()


# ---------------------------------------------------------------- 本体ループ

func _process(delta: float) -> void:
	delta = minf(delta, 1.0 / 20.0)
	_handle_ui_input()
	match state:
		GState.ATTRACT:
			_update_attract(delta)
		GState.PLAY:
			_update_play(delta)
		GState.DYING:
			freeze -= delta
			_update_enemies_idle(delta)
			if freeze <= 0.0:
				if lives <= 0:
					_game_over()
				else:
					state = GState.PLAY
					hud.set_message("LIFE LOST", 1.2)
		GState.CLEAR:
			_update_clear(delta)
		GState.ROULETTE:
			_update_enemies_idle(delta)
			if auto_wheel:
				wheel_auto += delta
				if wheel_auto > 1.4:
					wheel_auto = 0.0
					roulette.press()
		GState.OVER:
			_update_over(delta)
		_:
			pass
	_update_voice(delta)
	_sync_hud(delta)
	_flush_cover(delta)
	actors.queue_redraw()


func _sync_hud(delta: float) -> void:
	hud.score = score
	hud.hi_score = maxi(hi_score, score)
	hud.lives = lives
	hud.gal_index = gal_index
	hud.stage_in_gal = stage_in_gal
	hud.claim_pct = grid.get_claim_ratio() * 100.0
	hud.time_left = time_left
	hud.time_max = time_max
	hud.panic = panic
	hud.monster = monster_mode
	hud.monster_tex = _monster_texture()
	hud.stage_label = "%s %d-%d" % [GALS[gal_index], gal_index + 1, stage_in_gal]
	hud.combo = score_mult
	hud.credits = credits
	hud.tick(delta)


# ---------------------------------------------------------------- プレイ中

func _update_play(delta: float) -> void:
	if auto_win_loop:
		auto_win_timer -= delta
		if auto_win_timer <= 0.0:
			auto_win_timer = 4.0
			for i in grid.cells.size():
				grid.cells[i] = int(TerritoryGrid.Cell.CLAIMED)
			dirty = true
			_begin_clear()
			return
	# 時間
	time_left -= delta
	if time_left <= 10.0 and not time_warn:
		time_warn = true
		audio.sfx("sfx_time")
	if time_left <= 0.0:
		_lose_life("TIME UP")
		time_left = time_max
		return
	# パニックバーはゆっくりモンスター側へ下がる(前は速すぎて常時モンスター表示だった)
	panic = clampf(panic - _panic_drain() * delta, 0.0, 1.0)
	_update_monster_state(delta)

	_update_player(delta)
	symbol_timer += delta
	if symbol_timer > 9.0:
		symbol_timer = 0.0
		_spawn_symbol()
	var hit := enemies.update(delta, grid, grid.player, grid.drawing)
	erode_msg -= delta
	if enemies.eroded != last_eroded:
		# FROG が陣を食べた → カバーステクチャを再構築して反映
		last_eroded = enemies.eroded
		dirty = true
		if erode_msg <= 0.0:
			erode_msg = 3.0
			audio.sfx("sfx_asteroid")
			hud.set_message("FROG IS EATING YOUR TERRITORY!", 2.0)
	if hit != 0:
		_lose_life(enemies.hit_name())


func _update_attract(delta: float) -> void:
	attract_timer += delta
	_update_enemies_idle(delta)
	# 自動デモ：自陣の縁から四角い区画を抜く手順を自分で組んで流す
	if demo_plan.is_empty():
		if not grid.drawing:
			var p := grid.player
			var up := randi_range(12, 30)
			# 帯の幅を絞る(広すぎると 1 周が長くて閉じる前にデモが切れるため)
			var right := randi_range(30, 92)
			if p.x > GRID_W * 0.5:
				right = -right
			if p.x + right >= GRID_W - 2:
				right = -(right)
			elif p.x + right <= 1:
				right = absi(right)
			demo_plan.clear()
			for i in up:
				demo_plan.append(Vector2i.UP)
			for i in absi(right):
				demo_plan.append(Vector2i.RIGHT if right > 0 else Vector2i.LEFT)
			for i in up:
				demo_plan.append(Vector2i.DOWN)
		else:
			grid.cancel_trail()
			dirty = true
	else:
		var dir: Vector2i = demo_plan[0]
		demo_plan.pop_front()
		if not grid.drawing:
			pre_cells = grid.cells.duplicate()
		# アトラクトデモは敵に邪魔されない(敵は見た目のために動き続ける)。
		# 敵が描線を食べて輪が閉じないと陣が 0% のままになるため、
		# デモの step には敵セルを渡さない。
		var r := grid.step(dir, true, [])
		match r:
			TerritoryGrid.StepResult.TRAIL_STARTED:
				dirty = true
				trail_started_at = attract_timer
			TerritoryGrid.StepResult.DRAWING:
				dirty = true
			TerritoryGrid.StepResult.CLOSED:
				dirty = true
				_flash_gained(pre_cells, grid.cells)
				score = 0
				if grid.get_claim_ratio() >= WIN_RATIO:
					grid.reset()
					demo_plan.clear()
			TerritoryGrid.StepResult.SELF_CROSS:
				grid.cancel_trail()
				dirty = true
				demo_plan.clear()
			TerritoryGrid.StepResult.BLOCKED:
				# 敵に塞がれて進めない: 描線を止めて計画を作り直す
				# (UP の本数と DOWN の本数がズレると輪が閉じず陣が増えないため)
				grid.cancel_trail()
				dirty = true
				demo_plan.clear()
			_:
				pass
	if attract_timer > 22.0:
		attract_timer = 0.0
		grid.reset()
		demo_plan.clear()
		dirty = true


func _read_dir() -> Vector2i:
	for a in ACTIONS:
		if Input.is_action_just_pressed(a):
			last_dir = ACTIONS[a]
	if last_dir != Vector2i.ZERO:
		for a in ACTIONS:
			if ACTIONS[a] == last_dir and Input.is_action_pressed(a):
				return last_dir
	last_dir = Vector2i.ZERO
	for a in ACTIONS:
		if Input.is_action_pressed(a):
			return ACTIONS[a]
	return Vector2i.ZERO


func _update_player(delta: float) -> void:
	var interval := 1.0 / PLAYER_CELLS_PER_SEC
	if demo_play:
		step_acc += delta
		var m := 0
		while step_acc >= interval and m < MAX_STEPS_PER_FRAME and state == GState.PLAY:
			step_acc -= interval
			m += 1
			if play_left <= 0:
				if play_i >= play_plan.size():
					demo_play = false
					break
				var tok := String(play_plan[play_i])
				play_i += 1
				match tok.substr(0, 1):
					"U": play_dir = Vector2i.UP
					"D": play_dir = Vector2i.DOWN
					"L": play_dir = Vector2i.LEFT
					"R": play_dir = Vector2i.RIGHT
				var want := tok.substr(1, 1) == "1"
				play_left = int(tok.substr(2))
				play_draw = want
			play_left -= 1
			if not _do_step(play_dir, play_draw):
				step_acc = 0.0
		return
	var dir := _read_dir()
	if dir == Vector2i.ZERO:
		step_acc = 0.0
		return
	step_acc += delta
	var n := 0
	while step_acc >= interval and n < MAX_STEPS_PER_FRAME and state == GState.PLAY:
		step_acc -= interval
		n += 1
		if not _do_step(dir, Input.is_action_pressed("draw")):
			step_acc = 0.0
			break
	if n >= MAX_STEPS_PER_FRAME:
		step_acc = 0.0


## 1セル分動かす。grid.step() を呼んで結果に応じた演出・スコア・ライフ処理だけ行う。
func _do_step(dir: Vector2i, want_draw: bool = true) -> bool:
	var enemies_cells: Array = enemies.cell_list()
	if not grid.drawing:
		pre_cells = grid.cells.duplicate()
	var r := grid.step(dir, want_draw, enemies_cells)
	match r:
		TerritoryGrid.StepResult.BLOCKED:
			return false
		TerritoryGrid.StepResult.TRAIL_STARTED:
			dirty = true
			trail_started_at = float(Time.get_ticks_msec()) / 1000.0
			audio.sfx("sfx_draw")
		TerritoryGrid.StepResult.DRAWING:
			dirty = true
			if grid.trail.size() % 6 == 0:
				audio.sfx("sfx_draw", 1.0 + float(grid.trail.size() % 12) * 0.03)
		TerritoryGrid.StepResult.CLOSED:
			dirty = true
			_on_closed()
		TerritoryGrid.StepResult.SELF_CROSS:
			# 盤面は未変更。ペナルティ処理のあと cancel_trail() を呼ぶ。
			_lose_life("CROSSED OWN LINE", true)
			return false
	return true


func _on_closed() -> void:
	var gained: int = grid.last_gained
	var fast := (float(Time.get_ticks_msec()) / 1000.0 - trail_started_at) < 3.0
	var base := gained * 10 * score_mult
	if fast and gained > 24:
		base += int(gained * 5 * score_mult)
		hud.set_message("FAST DRAW!  +%d" % base, 1.6)
	score += base
	_flash_gained(pre_cells, grid.cells)
	# パニックバー: シルエットを大きく取るとモンスター側へ、背景側を取ると女の子側へ戻る
	var sil_hits := _count_silhouette_gained(pre_cells, grid.cells)
	var frac := clampf(float(sil_hits) / maxf(1.0, float(gained)), 0.0, 1.0)
	panic = clampf(panic - frac * 0.10 + (1.0 - frac) * 0.09, 0.0, 1.0)
	_update_monster_state()
	_collect_symbols()
	audio.sfx("sfx_capture", 1.0 + minf(0.4, gained / 900.0))
	if grid.get_claim_ratio() >= WIN_RATIO:
		_begin_clear()


func _panic_drain() -> float:
	var d := 0.006 + 0.0008 * float(stage_total)
	if grid.drawing:
		d *= 1.5
	return d


func _monster_hold_secs() -> float:
	# モンスター領域に入ってから GAL 側へ戻すまでの秒数(ランダム)。
	# バーが最後まで振り切れる前に、最低5秒は残して戻す。
	var to_end: float = panic / maxf(_panic_drain(), 0.0001)
	var latest: float = maxf(2.0, to_end - 5.0)
	var earliest: float = minf(4.0, latest * 0.5)
	if latest <= earliest:
		return latest
	return randf_range(earliest, latest)


func _update_monster_state(delta: float = 0.0) -> void:
	if not monster_mode and panic < 0.35:
		monster_mode = true
		monster_hold = _monster_hold_secs()
		audio.sfx("sfx_monster")
		hud.set_message("MONSTER!!  IMAGE IS GONE", 2.2)
	elif monster_mode:
		if monster_hold > 0.0:
			monster_hold -= delta
			if monster_hold <= 0.0:
				monster_hold = 0.0
				panic = 0.72   # ランダム経過 -> GAL側へ戻す
		if panic > 0.52:
			monster_mode = false
			audio.sfx("sfx_bonus")
			hud.set_message("GAL IS BACK", 1.6)


func _lose_life(cause: String, cancel := false) -> void:
	if state != GState.PLAY:
		return
	lives -= 1
	if cancel or grid.drawing:
		grid.cancel_trail()
	dirty = true
	freeze = 1.3
	state = GState.DYING
	death_cause = cause
	hud.set_message(cause, 2.0)
	audio.sfx("sfx_hit")
	if monster_mode:
		audio.play_voice("voice_monster")
	hi_score = maxi(hi_score, score)


func _update_enemies_idle(delta: float) -> void:
	enemies.update(delta, grid, grid.player, false)


# ---------------------------------------------------------------- クリア演出

func _begin_clear() -> void:
	state = GState.CLEAR
	clear_phase = 0
	clear_timer = 0.0
	hi_score = maxi(hi_score, score)
	var pct := int((grid.get_claim_ratio() - WIN_RATIO) * 100.0)
	var bonus := maxi(0, pct) * 1000 * score_mult
	score += bonus
	audio.stop_music()
	if monster_mode:
		audio.sfx("sfx_monster")
		hud.set_message("MONSTER CLEAR!  STAGE REPEAT", 2.6)
	else:
		audio.sfx("sfx_clear")
		hud.set_message("STAGE CLEAR  +%d" % bonus, 2.4)


## 全裸画像を表示してから delay 秒後に、そのステージの女の子音声(galN_M.mp3)を鳴らす。
func _schedule_voice(name: String, delay: float) -> void:
	voice_pending = name
	voice_timer = delay


func _update_voice(delta: float) -> void:
	if voice_pending == "":
		return
	voice_timer -= delta
	if voice_timer <= 0.0:
		var v := voice_pending
		voice_pending = ""
		audio.play_voice(v)


func _update_clear(delta: float) -> void:
	clear_timer += delta
	match clear_phase:
		0:
			if clear_timer > 1.1:
				clear_timer = 0.0
				clear_phase = 1
				var tex := _reward_texture_for_clear()
				reveal.play_image(tex,
						"STAGE CLEAR",
						"%s  %d-%d" % [GALS[gal_index], gal_index + 1, stage_in_gal],
						"clear")
				_schedule_voice("gal%d_%d" % [gal_index + 1, stage_in_gal], 1.0)
		1:
			pass
		2:
			# ルーレットへ
			clear_phase = 3
			state = GState.ROULETTE
			roulette.open_round()
			audio.play_music("bgm_roulette")
			audio.sfx("sfx_bonus")
		_:
			pass


func _on_reveal_finished() -> void:
	if state == GState.CLEAR:
		clear_phase = 2
		clear_timer = 0.0


func _on_roulette_finished(index: int) -> void:
	audio.sfx("sfx_wheel_stop")
	var label := roulette.slot_label(index)
	hud.set_message("ROULETTE: " + label, 2.6)
	match index:
		0: score += 5000
		1:
			lives = mini(MAX_LIVES, lives + 1)
			audio.sfx("sfx_life")
		2: score += 15000
		3: pending_time += 20.0
		4: pending_penalty = 1.45
		5: score += 2000
		6: pending_panic = 0.42
		7: pending_mult = 2
		8: score += 8000
		9: pending_time -= 10.0
		10: pending_storm = true
		11: score += 3000
	# 次のステージへ
	if monster_mode:
		# モンスター画像のままでクリアした → 同じステージをやり直し
		pass
	else:
		stage_number += 1
		if stage_number >= GALS.size() * STAGES_PER_GAL:
			_all_clear()
			return
	_start_stage()


func _all_clear() -> void:
	state = GState.ALLCLEAR
	score += 100000
	hi_score = maxi(hi_score, score)
	audio.stop_music()
	audio.play_music("bgm_clear")
	reveal.play_image(_reward_texture(), "ALL CLEAR!", "THANK YOU FOR PLAYING", "clear")
	_schedule_voice("gal%d_%d" % [gal_index + 1, stage_in_gal], 1.0)


# ---------------------------------------------------------------- ルーレット後処理


# ---------------------------------------------------------------- 素材

func _stage_texture(gal: int, stage: int) -> Texture2D:
	var key := "stage%d_%d" % [gal + 1, stage]
	if _img_cache.has(key):
		return _img_cache[key]
	var tex: Texture2D = null
	if AssetPaths.has("bg.png"):
		tex = AssetPaths.texture("bg.png")
	elif AssetPaths.has("bg/gal%d_%d.png" % [gal + 1, stage]):
		tex = AssetPaths.texture("bg/gal%d_%d.png" % [gal + 1, stage])
	else:
		var img := sil.procedural_image(480, 360, gal, stage)
		tex = ImageTexture.create_from_image(img)
	_img_cache[key] = tex
	return tex


func _reward_texture() -> Texture2D:
	var key := "reward%d_%d" % [gal_index + 1, stage_in_gal]
	if _img_cache.has(key):
		return _img_cache[key]
	var tex: Texture2D = null
	var rel := "reward/gal%d_%d.png" % [gal_index + 1, stage_in_gal]
	if AssetPaths.has(rel):
		tex = AssetPaths.texture(rel)
	if tex == null:
		var img := sil.procedural_image(480, 360, gal_index, stage_in_gal)
		tex = ImageTexture.create_from_image(img)
	_img_cache[key] = tex
	return tex


func _monster_texture() -> Texture2D:
	if _img_cache.has("monster"):
		return _img_cache["monster"]
	var tex: Texture2D = null
	if AssetPaths.has("reward/monster.png"):
		tex = AssetPaths.texture("reward/monster.png")
	if tex == null:
		var img := sil.procedural_image(480, 360, 3, 1)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(c.g * 0.7, c.r * 0.5, c.b * 0.9, 1.0))
		tex = ImageTexture.create_from_image(img)
	_img_cache["monster"] = tex
	return tex


func _apply_stage_visuals(gal: int, stage: int) -> void:
	bg_tex = _stage_texture(gal, stage)
	var mask := _load_mask_bytes(gal, stage)
	if mask.is_empty():
		mask = sil.build_mask(gal * 8 + stage)
	mask_bytes = mask
	mask_img = Image.create_from_data(GRID_W, GRID_H, false, Image.FORMAT_R8, mask)
	mask_tex.update(mask_img)
	cover_mat.set_shader_parameter("mask", mask_tex)
	board.queue_redraw()
	queue_redraw()   # 背景(bg_tex)は Main 自身の _draw() で描くのでこちらも再描画


## 画像のポースから作ったシルエツトマスク res://mask/galN_M.png を優先して読む。
## 無い時だけ従来のプロシージャルな人物プロファイルに落る。判定ロジックには関与しない。
func _load_mask_bytes(gal: int, stage: int) -> PackedByteArray:
	var p := "mask/gal%d_%d.png" % [gal + 1, stage]
	var img: Image = AssetPaths.image(p)
	if img == null:
		return PackedByteArray()
	if img.get_size() != Vector2i(GRID_W, GRID_H):
		img = img.duplicate()
		img.resize(GRID_W, GRID_H, Image.INTERPOLATE_LANCZOS)
	var out := PackedByteArray()
	out.resize(GRID_W * GRID_H)
	for y in GRID_H:
		for x in GRID_W:
			var c := img.get_pixel(x, y)
			out[y * GRID_W + x] = int(clamp(maxf(c.r, maxf(c.g, c.b)) * 255.0, 0.0, 255.0))
	return out


func _reward_texture_for_clear() -> Texture2D:
	# クリア時はい常に「そのステージの女の子」の画像を出す。
	# モンスター画像はパンクバー側の脅威表示専用(hud.monster_tex へ渡す)。
	return _reward_texture()


# ---------------------------------------------------------------- 盤面描画

func _rebuild_cover() -> void:
	cover_img = Image.create_from_data(GRID_W, GRID_H, false, Image.FORMAT_R8, grid.cells)
	if cover_tex == null:
		cover_tex = ImageTexture.create_from_image(cover_img)
	else:
		cover_tex.update(cover_img)
	cover.texture = cover_tex
	dirty = false


func _flush_cover(delta: float) -> void:
	if dirty:
		dirty = false
		cover_img = Image.create_from_data(GRID_W, GRID_H, false, Image.FORMAT_R8, grid.cells)
		if cover_tex == null:
			cover_tex = ImageTexture.create_from_image(cover_img)
			cover.texture = cover_tex
		else:
			cover_tex.update(cover_img)
	if flash_amount > 0.0:
		flash_amount = maxf(0.0, flash_amount - delta * 2.2)
		cover_mat.set_shader_parameter("flash_amount", flash_amount)


## 確定で増えたセルを光らせる（pre→post の差分だけ使う。判定ロジックは再実装しない）。
func _flash_gained(pre: PackedByteArray, post: PackedByteArray) -> void:
	var n := pre.size()
	if n != post.size():
		return
	var buf := PackedByteArray()
	buf.resize(n)
	var any := false
	for i in n:
		if pre[i] != post[i] and post[i] == TerritoryGrid.Cell.CLAIMED:
			buf[i] = 255
			any = true
	if any:
		flash_img = Image.create_from_data(GRID_W, GRID_H, false, Image.FORMAT_R8, buf)
		flash_tex.update(flash_img)
		flash_amount = 1.0
		cover_mat.set_shader_parameter("flash_amount", 1.0)


func _count_silhouette_gained(pre: PackedByteArray, post: PackedByteArray) -> int:
	var n := pre.size()
	if n != mask_bytes.size():
		return 0
	var hits := 0
	for i in n:
		if pre[i] != post[i] and post[i] == TerritoryGrid.Cell.CLAIMED and mask_bytes[i] > 100:
			hits += 1
	return hits


# ---------------------------------------------------------------- ボーナスシンボル

func _spawn_symbol() -> void:
	if symbols.size() >= 4:
		return
	for tries in 200:
		var x := randi_range(2, GRID_W - 3)
		var y := randi_range(2, GRID_H - 3)
		var c := Vector2i(x, y)
		if grid.get_cell(c) != TerritoryGrid.Cell.EMPTY:
			continue
		var roll := randi() % 100
		var kind: int = Sym.STAR
		if roll < 34:
			kind = Sym.STAR
		elif roll < 48:
			kind = Sym.CLOCK
		elif roll < 60:
			kind = Sym.LIFE
		elif roll < 74:
			kind = Sym.STORM
		elif roll < 84:
			kind = Sym.CURSE
		elif roll < 92:
			kind = Sym.FROG
		else:
			kind = Sym.OCTOPUS
		symbols.append({"cell": c, "kind": kind, "phase": randf() * TAU})
		audio.sfx("sfx_bonus", 1.4)
		return


func _collect_symbols() -> void:
	var keep: Array[Dictionary] = []
	for s in symbols:
		var c: Vector2i = s["cell"]
		var cell_state := grid.get_cell(c)
		if cell_state == TerritoryGrid.Cell.EMPTY:
			keep.append(s)
			continue
		_apply_symbol(int(s["kind"]))
	if keep.size() != symbols.size():
		symbols = keep


func _apply_symbol(kind: int) -> void:
	match kind:
		Sym.STAR:
			score += 2000 * score_mult
			hud.set_message("STAR  +%d" % (2000 * score_mult), 1.8)
			audio.sfx("sfx_bonus")
		Sym.LIFE:
			lives = mini(MAX_LIVES, lives + 1)
			hud.set_message("1UP!", 2.0)
			audio.sfx("sfx_life")
		Sym.CLOCK:
			time_left += 15.0
			hud.set_message("TIME +15", 1.8)
			audio.sfx("sfx_time")
		Sym.STORM:
			var n := enemies.kill_all()
			score += n * 1500 * score_mult
			hud.set_message("ASTEROID STORM!  x%d" % n, 2.2)
			audio.sfx("sfx_asteroid")
		Sym.CURSE:
			panic = clampf(panic - 0.22, 0.0, 1.0)
			_update_monster_state()
			hud.set_message("CURSE...", 1.8)
			audio.sfx("sfx_monster")
		Sym.FROG:
			hud.set_message("FROG!  GIRL TURNED INTO A FROG", 2.4)
			audio.sfx("sfx_monster", 0.7)
			panic = clampf(panic - 0.12, 0.0, 1.0)
		Sym.OCTOPUS:
			hud.set_message("OCTOPUS!  TIME -10", 2.4)
			audio.sfx("sfx_monster", 1.5)
			time_left = maxf(1.0, time_left - 10.0)


# ---------------------------------------------------------------- 盤面（Board）の描画

func _draw() -> void:
	draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(0, 0, 0))
	var mod := Color(1, 1, 1)
	if monster_mode:
		mod = Color(0.55, 1.0, 0.6)
	if bg_tex != null:
		draw_texture_rect(bg_tex, Rect2(ORIGIN, FIELD), false, mod)
	# 盤面の外枠（縁取り）
	draw_rect(Rect2(ORIGIN, FIELD), Color(0.35, 0.35, 0.5), false, 2.0)
