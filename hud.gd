class_name Hud
extends Node2D
## 左右240pxのHUDレーンと、上部の「パニックバー（針のバー）」を描くだけのノード。
## 陣取りの判定には関与しない（数値は main 側から受け取る）。
## 座標はすべて 1920x1080 基準。

const VIEW_W := 1920
const LEFT_X := 24.0
const RIGHT_X := 1680.0

var score := 0
var hi_score := 0
var lives := 3
var gal_index := 0
var stage_in_gal := 1
var goal_pct := 80
var claim_pct := 0.0
var time_left := 60.0
var time_max := 60.0
var panic := 0.75
var monster := false
var monster_tex: Texture2D   # main.gd が設定。バーがモンスター側に振れた時に表示
var stage_label := "MARINA  1-1"
var message := ""
var message_timer := 0.0
var sub := ""
var sub_timer := 0.0
var blink := 0.0
var combo := 1
var credits := 0
var demo := false


func set_message(text: String, secs: float = 2.0) -> void:
	message = text
	message_timer = secs


func set_sub(text: String, secs: float = 3.0) -> void:
	sub = text
	sub_timer = secs


func tick(delta: float) -> void:
	blink += delta
	if message_timer > 0.0:
		message_timer -= delta
		if message_timer <= 0.0:
			message = ""
	if sub_timer > 0.0:
		sub_timer -= delta
		if sub_timer <= 0.0:
			sub = ""
	queue_redraw()


func _f() -> Font:
	return ThemeDB.fallback_font


func _draw() -> void:
	# 左右のHUDパネル
	draw_rect(Rect2(0, 0, 240, 1080), Color(0.04, 0.04, 0.09))
	draw_rect(Rect2(1680, 0, 240, 1080), Color(0.04, 0.04, 0.09))
	draw_rect(Rect2(238, 0, 4, 1080), Color(0.25, 0.25, 0.4))
	draw_rect(Rect2(1678, 0, 4, 1080), Color(0.25, 0.25, 0.4))

	var f := _f()
	# --- 左レーン
	_label(f, LEFT_X, 52, "1UP", 22, Color(0.9, 0.9, 1.0))
	_value(f, LEFT_X, 104, _pad(hi_score), 34, Color(1, 0.9, 0.4))
	_label(f, LEFT_X, 152, "SCORE", 22, Color(0.9, 0.9, 1.0))
	_value(f, LEFT_X, 204, _pad(score), 38, Color(1, 1, 1))
	_label(f, LEFT_X, 252, "GAL", 22, Color(0.9, 0.9, 1.0))
	_value(f, LEFT_X, 300, stage_label, 30, Color(0.7, 0.95, 1.0))

	_label(f, LEFT_X, 352, "CLAIM", 22, Color(0.9, 0.9, 1.0))
	_bar(Rect2(LEFT_X, 366, 190, 26), claim_pct / 100.0, Color(0.25, 0.85, 0.5))
	_value(f, LEFT_X, 420, "%d%% / %d%%" % [int(claim_pct), goal_pct], 26, Color(0.85, 0.9, 1.0))

	_label(f, LEFT_X, 470, "TIME", 22, Color(0.9, 0.9, 1.0))
	var tk := clampf(time_left / maxf(time_max, 1.0), 0.0, 1.0)
	_bar(Rect2(LEFT_X, 484, 190, 26), tk, Color(0.95, 0.35, 0.3) if tk < 0.25 else Color(0.95, 0.75, 0.25))
	_value(f, LEFT_X, 538, "%0.0f" % ceil(time_left), 30, Color(1, 1, 1))

	_label(f, LEFT_X, 588, "LIVES", 22, Color(0.9, 0.9, 1.0))
	for i in lives:
		var p := Vector2(LEFT_X + 14 + i * 34, 616)
		draw_polygon_marker(p, 13.0, Color(1, 0.25, 0.3))
	_label(f, LEFT_X, 664, "BONUS x%d" % combo, 22, Color(0.9, 0.9, 1.0))

	# --- 右レーン
	_label(f, RIGHT_X, 52, "PANIC BAR", 22, Color(0.9, 0.9, 1.0))
	_panic_bar(Rect2(RIGHT_X, 66, 190, 34))
	_label(f, RIGHT_X, 128, "MONSTER!" if monster else "GAL OK", 24,
			Color(0.6, 1.0, 0.5) if not monster else Color(1, 0.35, 0.35))
	_label(f, RIGHT_X, 178, "CONTROLS", 22, Color(0.9, 0.9, 1.0))
	var lines := ["ARROWS  MOVE", "SPACE   DRAW", "SPACE   STOP WHEEL", "F11     FULLSCREEN", "M       MUTE", "R       RESTART"]
	for i in lines.size():
		_label(f, RIGHT_X, 212 + i * 30, lines[i], 20, Color(0.75, 0.8, 0.95))
	_label(f, RIGHT_X, 420, "HOW TO PLAY", 22, Color(0.9, 0.9, 1.0))
	var tips := ["DRAW A LINE FROM", "YOUR TERRITORY AND", "CLOSE IT TO CLAIM", "THE GIRL PICTURE.", "CLAIM %d%% TO CLEAR." % goal_pct, "DON'T TOUCH YOUR", "OWN LINE OR FOES."]
	for i in tips.size():
		_label(f, RIGHT_X, 454 + i * 28, tips[i], 19, Color(0.65, 0.7, 0.9))

	# パニックバーがモンスター側に振れている間、右レーンにモンスター画像を出す
	if monster and monster_tex != null:
		var mr := Rect2(RIGHT_X, 700, 190, 143)
		draw_texture_rect(monster_tex, mr, false)
		draw_rect(mr, Color(1, 0.4, 0.4, 0.9), false, 3.0)
		_label(f, RIGHT_X, 880, "MONSTER IMAGE", 20, Color(1, 0.5, 0.5))

	# --- 上部の針バー（原作の「バー＋針」）
	_top_bar(Rect2(260, 14, 1400, 30))

	# --- 中央メッセージ
	if message != "":
		var a := clampf(message_timer, 0.0, 1.0)
		draw_string(f, Vector2(240, 972), message, HORIZONTAL_ALIGNMENT_CENTER, 1440, 46,
				Color(1, 1, 0.6, a))
	if sub != "":
		var b := clampf(sub_timer, 0.0, 1.0)
		draw_string(f, Vector2(240, 1014), sub, HORIZONTAL_ALIGNMENT_CENTER, 1440, 30,
				Color(0.6, 0.95, 1.0, b))
	if demo:
		draw_string(f, Vector2(240, 1050), "INSERT COIN (5) - ATTRACT MODE",
				HORIZONTAL_ALIGNMENT_CENTER, 1440, 26, Color(1, 0.9, 0.5, 0.5 + 0.5 * sin(blink * 4.0)))
	if credits > 0:
		_label(f, RIGHT_X, 1040, "CREDIT %d" % credits, 22, Color(1, 0.9, 0.5))


func _label(f: Font, x: float, y: float, text: String, size: int, col: Color) -> void:
	draw_string(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _value(f: Font, x: float, y: float, text: String, size: int, col: Color) -> void:
	draw_string(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _pad(v: int) -> String:
	return "%07d" % maxi(0, v)


func _bar(r: Rect2, k: float, col: Color) -> void:
	draw_rect(r, Color(0.1, 0.1, 0.16))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(k, 0.0, 1.0), r.size.y)), col)
	draw_rect(r, Color(0.6, 0.6, 0.8), false, 2.0)


func _panic_bar(r: Rect2) -> void:
	draw_rect(r, Color(0.1, 0.06, 0.12))
	var k := clampf(panic, 0.0, 1.0)
	# 右へ行くほど「女の子」、左へ行くほど「モンスター」
	var col := Color(0.9, 0.3, 0.35).lerp(Color(0.35, 0.9, 0.5), k)
	draw_rect(Rect2(r.position, Vector2(r.size.x * k, r.size.y)), col)
	draw_rect(r, Color(0.8, 0.8, 0.9), false, 2.0)
	# 危険ライン
	var danger := 0.35
	var dx := r.position.x + r.size.x * danger
	draw_line(Vector2(dx, r.position.y - 4), Vector2(dx, r.position.y + r.size.y + 4), Color(1, 0.9, 0.2), 3.0)
	_label(_f(), r.position.x, r.position.y + r.size.y + 26, "MONSTER", 18, Color(0.8, 0.6, 0.9))
	_label(_f(), r.position.x + 130, r.position.y + r.size.y + 26, "GAL", 18, Color(0.6, 0.9, 0.7))


func _top_bar(r: Rect2) -> void:
	# 原作の「上部のバー＋針」: 針が左(モンスター側)へ寄るとモンスター化
	draw_rect(r, Color(0.08, 0.08, 0.14))
	var k := clampf(panic, 0.0, 1.0)
	var grad_steps := 24
	for i in grad_steps:
		var t := float(i) / float(grad_steps - 1)
		var c := Color(0.85, 0.25, 0.3).lerp(Color(0.3, 0.85, 0.55), t)
		draw_rect(Rect2(r.position.x + r.size.x * float(i) / float(grad_steps), r.position.y,
				r.size.x / float(grad_steps), r.size.y), c.darkened(0.45))
	var px := r.position.x + r.size.x * k
	draw_line(Vector2(px, r.position.y - 8), Vector2(px, r.position.y + r.size.y + 8), Color(1, 1, 1), 5.0)
	draw_circle(Vector2(px, r.position.y + r.size.y * 0.5), 12.0, Color(1, 1, 1))
	draw_rect(r, Color(0.85, 0.85, 0.95), false, 3.0)
	draw_string(_f(), Vector2(r.position.x, r.position.y + r.size.y + 24), "MONSTER SIDE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.6, 0.7))
	draw_string(_f(), Vector2(r.position.x + r.size.x - 200, r.position.y + r.size.y + 24), "GAL SIDE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.6, 0.9, 0.7))


func draw_polygon_marker(p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	draw_colored_polygon(pts, col)
