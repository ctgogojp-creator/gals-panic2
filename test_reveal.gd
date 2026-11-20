extends SceneTree
## クリア→ご褒美画像(RevealEffect)→ルーレット の遷移を frames 単位で確認する検証用

const MAIN_SCENE := preload("res://main.tscn")

var main: Node
var frames := 0
var log_lines: Array[String] = []

func _init() -> void:
	main = MAIN_SCENE.instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		main.credits = 9
		main._start_game()
		main.enemies.setup(1, 0, 0, 0, 0, 0, main.grid)
		for i in main.grid.cells.size():
			main.grid.cells[i] = 1
		main.dirty = true
		main._begin_clear()
	if frames % 20 == 0:
		print("f=%d state=%d phase=%d rev_state=%s rev_vis=%s rev_t=%.2f tex=%s" % [
			frames, main.state, main.clear_phase, main.reveal.state,
			str(main.reveal.visible), main.reveal.t,
			str(main.reveal.sprite.texture != null)])
	if frames > 420:
		print("DONE frames=%d state=%d" % [frames, main.state])
		quit(0)
	return false
