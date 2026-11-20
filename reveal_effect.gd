class_name RevealEffect
extends Node2D
## 「画面が開く」演出（領域確保・ステージクリア・ご褒美画像・モンスター化）。
## 演出専用で陣取りの判定には関与しない。1920x1080 基準の座標で描く。
##
## 使い方:
##   reveal.play_image(tex, "STAGE CLEAR", "MARINA")     # 開く演出 → 表示
##   reveal.dismiss()                                      # 玩家のボタンで閉じる
##   reveal.finished.connect(...)

signal finished

const OPEN_SHADER := """
shader_type canvas_item;
uniform sampler2D reward : filter_linear, repeat_disable;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

float jag(vec2 uv) {
	return (sin(uv.y * 78.0) + sin(uv.y * 31.0 + 1.7) + sin(uv.x * 44.0)) * 0.0055;
}

void fragment() {
	vec2 uv = UV;
	vec2 d = abs(uv - vec2(0.5));
	float hx = progress * 0.5 + 0.0002;
	float hy = progress * 0.52 + 0.0002;
	float j = jag(uv);
	vec4 img = texture(reward, uv) * tint;
	if (d.x <= hx + j && d.y <= hy + j) {
		float scanline = 1.0 - 0.16 * step(0.5, fract(uv.y * 240.0));
		float vign = 1.0 - 0.35 * dot(d, d);
		COLOR = vec4(img.rgb * scanline * vign + vec3(flash), 1.0);
	} else {
		float near = smoothstep(0.035, 0.0, min(hx - d.x, hy - d.y));
		vec3 base = vec3(0.015, 0.015, 0.03);
		COLOR = vec4(base + vec3(1.0, 0.88, 0.55) * near * 1.1 + vec3(flash) * 0.25, 1.0);
	}
}
"""

## 額縁・火花・文字用。スプライト(z_index 20)より上に出すための子ノード。
class FrameFX:
	extends Node2D
	var owner_ref: Node2D
	func _draw() -> void:
		if owner_ref != null and owner_ref.has_method("draw_frame_fx"):
			owner_ref.draw_frame_fx(self)


var sprite: Sprite2D
var fx: Node2D
var mat: ShaderMaterial
var state := "idle"        # idle / opening / show / closing
var t := 0.0
var open_time := 1.7
var title_text := ""
var sub_text := ""
var sparkles: Array[Dictionary] = []
var area := Rect2(240, 0, 1440, 1080)
var dismissable := false


func _ready() -> void:
	var shader := Shader.new()
	shader.code = OPEN_SHADER
	mat = ShaderMaterial.new()
	mat.shader = shader
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.material = mat
	sprite.visible = false
	sprite.z_index = 20
	add_child(sprite)
	fx = FrameFX.new()
	fx.name = "FrameFX"
	fx.z_index = 40
	add_child(fx)
	fx.owner_ref = self
	visible = false


func _layout() -> void:
	var s := minf(area.size.x / maxf(1.0, float(sprite.texture.get_width())),
			area.size.y / maxf(1.0, float(sprite.texture.get_height()))) if sprite.texture else 1.0
	var size := Vector2(sprite.texture.get_width(), sprite.texture.get_height()) * s if sprite.texture else Vector2.ONE
	sprite.scale = Vector2(s, s)
	sprite.position = area.position + (area.size - size) * 0.5


## 画像を開いて見せる。kind: "clear" / "monster" / "photo"
func play_image(tex: Texture2D, title: String, sub: String, kind: String = "clear") -> void:
	if tex == null:
		_finish_now()
		return
	sprite.texture = tex
	# シェーダがサンプリングする画像は reward ユニフォーム側。
	# ここを設定しないと sampler2D が既定の白になり「ご褒美画像が出ない」ままになる。
	mat.set_shader_parameter("reward", tex)
	_layout()
	title_text = title
	sub_text = sub
	state = "opening"
	t = 0.0
	open_time = 1.7 if kind != "photo" else 2.3
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("flash", 1.0)
	mat.set_shader_parameter("tint", Color(1, 1, 1, 1) if kind != "monster" else Color(0.55, 1.0, 0.5))
	visible = true
	sprite.visible = true
	dismissable = false
	sparkles.clear()
	for i in 46:
		sparkles.append({"p": Vector2(randf(), randf()), "v": randf_range(0.15, 0.6), "s": randf_range(3.0, 12.0)})
	queue_redraw()


func dismiss() -> void:
	if state == "show":
		state = "closing"
		t = 0.0


func _finish_now() -> void:
	state = "idle"
	visible = false
	sprite.visible = false
	if mat != null:
		mat.set_shader_parameter("reward", null)
	finished.emit()


func is_busy() -> bool:
	return state == "opening" or state == "show"


func _process(delta: float) -> void:
	if state == "idle":
		return
	t += delta
	match state:
		"opening":
			var k := clampf(t / open_time, 0.0, 1.0)
			mat.set_shader_parameter("progress", ease(k, 1.35))
			mat.set_shader_parameter("flash", maxf(0.0, 1.0 - t * 2.4))
			if t >= open_time:
				state = "show"
				t = 0.0
				dismissable = true
				queue_redraw()
		"show":
			mat.set_shader_parameter("flash", 0.0)
			if t > 4.5:
				# 自動で閉じる（放置対策）。ボタンがあれば即閉じられる
				dismiss()
			queue_redraw()
		"closing":
			var k2 := clampf(t / 0.45, 0.0, 1.0)
			mat.set_shader_parameter("progress", 1.0 - k2)
			mat.set_shader_parameter("flash", k2 * 0.5)
			if t >= 0.45:
				_finish_now()
		_:
			pass


func _draw() -> void:
	if state == "idle":
		return
	# 全面を暗くして盤面を消す
	draw_rect(Rect2(-240, 0, 1920, 1080), Color(0, 0, 0, 1))
	# 火花
	if fx != null:
		fx.queue_redraw()


func draw_frame_fx(n: Node2D) -> void:
	if state == "idle":
		return
	for s in sparkles:
		var p: Vector2 = s["p"]
		var v: float = s["v"]
		var sz: float = s["s"]
		var yy := fmod(p.y + t * v, 1.0)
		var pos := Vector2(area.position.x + p.x * area.size.x, area.position.y + yy * area.size.y)
		var a := 0.35 + 0.65 * sin((t + p.x * 3.0) * 9.0)
		n.draw_circle(pos, sz * 0.35, Color(1, 0.95, 0.7, clampf(a, 0.0, 1.0) * 0.8))
	# 額縁
	var frame := Rect2(sprite.position - Vector2(10, 10),
			Vector2(sprite.texture.get_width() * sprite.scale.x,
					sprite.texture.get_height() * sprite.scale.y) + Vector2(20, 20)) if sprite.texture else Rect2(area)
	n.draw_rect(frame, Color(1, 0.85, 0.4, 0.9), false, 6.0)
	var f := ThemeDB.fallback_font
	if state == "show" or state == "closing":
		n.draw_string(f, Vector2(240, 70), title_text, HORIZONTAL_ALIGNMENT_CENTER, 1440, 64, Color(1, 0.95, 0.6))
		n.draw_string(f, Vector2(240, 1040), sub_text, HORIZONTAL_ALIGNMENT_CENTER, 1440, 34, Color(0.85, 0.9, 1.0))
		if dismissable:
			n.draw_string(f, Vector2(240, 1000), "PRESS DRAW (SPACE)",
					HORIZONTAL_ALIGNMENT_CENTER, 1440, 26,
					Color(0.7, 0.75, 0.9, 0.6 + 0.4 * sin(t * 6.0)))
	else:
		n.draw_string(f, Vector2(240, 70), title_text, HORIZONTAL_ALIGNMENT_CENTER, 1440, 64,
				Color(1, 0.95, 0.6, clampf(t * 2.0, 0.0, 1.0)))
