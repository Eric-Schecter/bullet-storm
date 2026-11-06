extends SceneTree
# Functional integration check: actual projectiles hit three real enemy types.
var game
var elapsed = 0.0
var phase = 0

func _initialize():
	game = load("res://main.tscn").instantiate()
	root.add_child.call_deferred(game)

func _process(dt):
	if not is_instance_valid(game) or not game.is_node_ready(): return false
	elapsed += minf(dt,0.04)
	if phase == 0:
		game._start(false)
		game.auto_fire = true
		game.spawn_cd = 999
		game.core_cd = 999
		game._add_enemy("drone",Vector2(640,410),1,0)
		game.enemies[-1].p = Vector2(640,410)
		phase = 1
	elif phase == 1 and elapsed > 0.6:
		game._add_enemy("frame",Vector2(640,410),1,0)
		game.enemies[-1].p = Vector2(640,410)
		game._pattern(game.enemies[-1])
		phase = 2
	elif phase == 2 and elapsed > 1.3:
		game._add_enemy("core",Vector2(640,390),1,0)
		game.enemies[-1].p = Vector2(640,390)
		game._pattern(game.enemies[-1])
		phase = 3
	elif phase == 3 and elapsed > 2.5:
		for key in ["shot","impact","break","break_heavy","break_core","enemy_shot","enemy_core"]:
			if int(game.sound_counts.get(key,0)) <= 0:
				push_error("Audio event did not fire: "+key)
				quit(1)
				return false
		assert(game.sounds.size()==14,"Missing audio pools")
		for key in game.SOUND_VARIANTS:
			assert(game.sound_streams[key].size()==game.SOUND_VARIANTS[key].size(),"Generated variants missing: "+key)
		assert(game.score==1850,"Drone + heavy + core should award 1850 points exactly")
		print("AUDIO CHECK PASS: actual player shots, normal/heavy/core impacts and destruction, enemy volley cues; counts=",game.sound_counts)
		quit()
	return false
