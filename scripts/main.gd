extends Node2D

const WHITE = Color("e6e3d9")
const MUTED = Color("86857e")
const ORANGE = Color("ed8c42")
const RED = Color("c94043")
const BG = Color("08090b")
const MAX_LEVEL = 6
const ENEMY_POINTS = {"drone":100,"frame":250,"core":1500}
const MUSIC_DB = -8.0
const SOUND_VARIANTS = {
	"hit":["res://assets/audio/nier-hacking/player_hit.wav"],
	"shot":["res://assets/audio/nier-hacking/player_shoot.wav"],
	"enemy_shot":["res://assets/audio/nier-hacking/enemy_shoot.wav"],
	"enemy_core":["res://assets/audio/nier-hacking/enemy_shoot.wav"],
	"impact":["res://assets/audio/nier-hacking/enemy_hit.wav"],
	"bullet_break":["bullet_break_0","bullet_break_1"],
	"break":["res://assets/audio/nier-hacking/enemy_explode.wav"],
	"break_heavy":["res://assets/audio/nier-hacking/enemy_explode0.wav"],
	"break_core":["res://assets/audio/nier-hacking/core_exlode.wav"],
	"pickup":["wing_upgrade_0"],"upgrade":["upgrade_0"],
	"wing_loss":["wing_loss_0"],
}
const SOUND_LEVELS = {
	"shot":-14.0, "enemy_shot":-19.0, "enemy_core":-15.0,
	"impact":-17.0, "bullet_break":-24.0,
	"break":-11.0, "break_heavy":-7.0, "break_core":-3.5,
	"hit":-5.0, "select":-14.0, "pickup":-6.0,
	"upgrade":-8.0, "wing_loss":-6.0, "down":-6.0,
}
const SOUND_GAPS = {
	"shot":0.045, "enemy_shot":0.1, "enemy_core":0.18,
	"impact":0.06, "bullet_break":0.1,
	"break":0.055, "break_heavy":0.09, "break_core":0.25,
}

const ENCOURAGEMENT = ["Someone, somewhere, is still trying.", "Even here, you are not alone.", "A different future is still possible.", "Keep going. We are with you."]
var font = ThemeDB.fallback_font
var mode = "title"
var clock = 0.0
var stage = 0
var survival_time = 0.0
var spawn_cd = 0.5
var core_cd = 12.0
var spawn_serial = 0
var wingmen_count = 0
var weapon_level = 0
var pickups: Array = []
var pickups_collected = 0
var energy = 0
var boost_time = 0.0
var total_spawned = 0
var endless_test = false
var endless_test_time = 0.0
var escort_cd = 0.0
var deaths = 0
var hp = 3
var player = Vector2(640, 580)
var aim = Vector2.UP
var invincible = 0.0
var fire_cd = 0.0
var shake = 0.0
var flash = 0.0
var selection = 0
var assist = false
var auto_fire = false
var muted = false
var help_seen = false
var allies: Array = []
var enemies: Array = []
var bullets: Array = []
var shots: Array = []
var particles: Array = []
var stars: Array = []
var message = ""
var message_time = 0.0
var kills = 0
var score = 0
var best_score = 0
var music: AudioStreamPlayer
var sounds: Dictionary = {}
var sound_last: Dictionary = {}
var sound_counts: Dictionary = {}
var sound_streams: Dictionary = {}
var sound_last_variant: Dictionary = {}
var audio_rng = RandomNumberGenerator.new()
var music_duck = 0.0
var test_mode = false
var test_elapsed = 0.0
var test_phase = 0
var screenshot_pending = false
var combat_test = false
var demo_mode = false
var pilot_test = false
var pilot_elapsed = 0.0
var pilot_think = 0.0
var pilot_move = Vector2.ZERO
var pilot_hits = 0
var pilot_report = 10.0
var recording_limit = 0.0
var force_movie_draw = false
var recording_death_hold = 0.0

func _ready():
	randomize()
	for i in 140:
		stars.append([Vector2(randf()*1280, randf()*720), randf_range(0.15, 0.65), randf_range(0.3, 1.2)])
	_load_record()
	audio_rng.seed = 902
	# Catch coincident explosion peaks without turning down ordinary weapons.
	if AudioServer.get_bus_effect_count(0) == 0:
		AudioServer.add_bus_effect(0,AudioEffectLimiter.new())
	music = AudioStreamPlayer.new()
	music.stream = load("res://assets/audio/battle/arcade-drive.wav")
	music.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	music.stream.loop_begin = 0
	music.stream.loop_end = int(music.stream.get_length()*music.stream.mix_rate)
	music.volume_db = MUSIC_DB
	add_child(music)
	music.play()
	for key in SOUND_LEVELS:
		var streams: Array = []
		for name in SOUND_VARIANTS.get(key,[]):
			var path = name if name.begins_with("res://") else "res://assets/audio/elevenlabs/"+name+".wav"
			if ResourceLoader.exists(path): streams.append(load(path))
		if streams.is_empty(): streams.append(load("res://assets/"+key+".wav"))
		sound_streams[key] = streams
		var pool: Array = []
		for i in 5:
			var voice = AudioStreamPlayer.new()
			voice.stream = streams[0]
			voice.volume_db = SOUND_LEVELS[key]
			add_child(voice)
			pool.append(voice)
		sounds[key] = pool
	var args = OS.get_cmdline_user_args()
	if "--web-play" in args: _start(false)
	if "--smoke" in args:
		test_mode = true
		_start(false)
	if "--combat-test" in args:
		combat_test = true
		_start(false)
	if "--autoplay-demo" in args or "--pilot-test" in args:
		demo_mode = true
		pilot_test = "--pilot-test" in args
		seed(1606)
		_start(false)
		invincible = 0
	if "--record-long" in args and demo_mode:
		recording_limit = 300.0
	force_movie_draw = "--force-movie-draw" in args
	for argument in args:
		if argument.begins_with("--record-seconds=") and demo_mode:
			recording_limit = clampf(argument.get_slice("=",1).to_float(),1,3600)
	if "--preview" in args:
		_start(true)
		survival_time = 100
		stage = 3
		wingmen_count = 5
		weapon_level = 6
		_spawn_formation()
		_spawn_core()
		invincible = 999.0
	if "--endless-test" in args:
		endless_test = true
		demo_mode = true
		seed(1606)
		_start(false)
	if "--capture" in args:
		screenshot_pending = true

func sfx(key: String):
	if muted: return
	# Group a burst/volley into readable cues instead of one sound per pellet.
	if clock-float(sound_last.get(key,-1000.0)) < float(SOUND_GAPS.get(key,0.0)): return
	for voice in sounds.get(key, []):
		if not voice.playing:
			var variants: Array = sound_streams[key]
			var index = 0
			if variants.size() > 1:
				var previous = int(sound_last_variant.get(key,-1))
				index = audio_rng.randi_range(0,variants.size()-2 if previous>=0 else variants.size()-1)
				if previous>=0 and index>=previous: index += 1
			voice.stream = variants[index]
			sound_last_variant[key] = index
			voice.pitch_scale = 1.0 if key == "shot" else audio_rng.randf_range(0.985,1.015)
			voice.play()
			sound_last[key] = clock
			sound_counts[key] = int(sound_counts.get(key,0))+1
			if key in ["break","break_heavy","break_core","hit","wing_loss"]:
				music_duck = maxf(music_duck,0.5 if key == "break_core" else 0.3)
			break

func _input(event):
	if event is InputEventMouseMotion:
		if mode != "playing":
			var rows = _button_rows()
			for i in rows.size():
				if Rect2(440,rows[i]-26,400,48).has_point(get_global_mouse_position()): selection = i
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		if event.keycode == KEY_M:
			muted = not muted
			AudioServer.set_bus_mute(0, muted)
		if event.keycode == KEY_F: auto_fire = not auto_fire
		if event.keycode == KEY_ESCAPE:
			if mode == "playing": mode = "paused"
			elif mode == "paused": mode = "playing"
			elif mode == "controls": mode = "title"
		if event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D, KEY_UP, KEY_DOWN]:
			selection = 1-selection
		if event.keycode in [KEY_ENTER, KEY_SPACE]: _activate()
		if event.keycode == KEY_H and mode == "playing":
			mode = "help"
			selection = 0
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and mode != "playing":
		var pos = get_global_mouse_position()
		var rows = _button_rows()
		for i in rows.size():
			if Rect2(440, rows[i]-26, 400, 48).has_point(pos):
				selection = i
				_activate()
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_A: _activate()
		if event.button_index == JOY_BUTTON_START:
			mode = "paused" if mode == "playing" else "playing" if mode == "paused" else mode

func _button_rows() -> Array:
	match mode:
		"title": return [460, 518]
		"dead": return [444, 500]
		"help": return [442, 498]
		"paused": return [420, 478]
		"controls": return [554]
	return []

func _activate():
	if mode == "playing": return
	sfx("select")
	match mode:
		"title":
			if selection == 0: _start(false)
			else: mode = "controls"; selection = 0
		"controls": mode = "title"; selection = 0
		"dead":
			if selection == 0:
				if deaths >= 3 and not help_seen:
					mode = "help"
				else: _retry()
			else: mode = "title"; selection = 0
		"help":
			help_seen = true
			if selection == 0:
				assist = true
				allies = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
				message = "Support signal received. You are not alone."
				message_time = 6.0
			if hp > 0:
				mode = "playing"
				invincible = maxf(invincible,0.5)
			else: _retry()
		"paused":
			if selection == 0: mode = "playing"
			else: mode = "title"; selection = 0

func _start(with_help: bool):
	stage = 0
	deaths = 0
	kills = 0
	assist = with_help
	help_seen = false
	allies = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0] if with_help else []
	_retry()

func _retry():
	mode = "playing"
	selection = 0
	hp = 3
	player = Vector2(640, 580)
	invincible = 2.5
	fire_cd = 0.2
	bullets.clear()
	shots.clear()
	particles.clear()
	stage = 0
	kills = 0
	score = 0
	survival_time = 0.0
	spawn_cd = 0.5
	core_cd = 12.0
	spawn_serial = 0
	wingmen_count = 0
	weapon_level = 0
	pickups.clear()
	pickups_collected = 0
	energy = 0
	boost_time = 0
	total_spawned = 0
	escort_cd = 0
	enemies.clear()

func _spawn_formation():
	var limit = mini(18, 5+int(survival_time/18))
	var count = mini(3,1+int(survival_time/35))
	for i in count:
		if enemies.size() >= limit: return
		var x = 170.0+float((spawn_serial*3)%7)*155
		spawn_serial += 1
		var kind = "frame" if survival_time > 22 and spawn_serial%3 == 0 else "drone"
		var health = (40 if kind == "frame" else 24)*pow(1.0+survival_time/65,1.75)
		_add_enemy(kind,Vector2(x,165+(spawn_serial%3)*58),int(health),spawn_serial%5)

func _spawn_core():
	var cores = 0
	for e in enemies:
		if e.boss: cores += 1
	if cores >= 2: return
	var x = 420 if spawn_serial%2 == 0 else 860
	var pattern = randi_range(0,mini(4,int(survival_time/25)))
	_add_enemy("core",Vector2(x,125),int(900*pow(1.0+survival_time/100,2.2)),pattern)

func _update_director(dt: float):
	survival_time += dt
	stage = int(survival_time/30)
	boost_time = maxf(0,boost_time-dt)
	spawn_cd -= dt
	core_cd -= dt
	if spawn_cd <= 0:
		_spawn_formation()
		spawn_cd += maxf(0.85,2.9/(1.0+survival_time/95))
	if core_cd <= 0:
		_spawn_core()
		core_cd += maxf(14,26-survival_time*0.055)

func _gain_energy(amount: int):
	# Hull weapons are permanent for this run; escort losses never reset them.
	if weapon_level >= MAX_LEVEL:
		energy = 0
		return
	energy += amount
	while weapon_level < MAX_LEVEL and energy >= _energy_needed():
		energy -= _energy_needed()
		weapon_level += 1
		sfx("upgrade")
		if demo_mode: print("WEAPON UPGRADE time=",snappedf(survival_time,0.1)," weapon=",weapon_level)
		boost_time = 1.4
		_burst(player,WHITE,20)
	if weapon_level == MAX_LEVEL: energy = 0

func _energy_needed() -> int:
	return 6+weapon_level*3

func _weapon_interval() -> float:
	return maxf(0.055,0.105-weapon_level*0.004)

func _drop_key_loot(enemy: Dictionary):
	if enemy.kind not in ["core","frame"]: return
	if pickups.size() >= 24: return
	pickups.append({"p":enemy.p,"age":0.0})

func _update_pickups(dt: float):
	for i in range(pickups.size()-1,-1,-1):
		var item = pickups[i]
		item.age += dt
		# Slow descent lets the player intercept it without chasing into the spawn area.
		item.p.y += dt*65
		if wingmen_count < MAX_LEVEL and item.p.distance_squared_to(player) < 22*22:
			wingmen_count += 1
			pickups_collected += 1
			boost_time = 1.0
			_burst(player,WHITE,15)
			sfx("pickup")
			if demo_mode: print("WINGMAN PICKUP time=",snappedf(survival_time,0.1)," escorts=",wingmen_count)
			pickups.remove_at(i)
		elif item.age > 12 or item.p.y > 745:
			pickups.remove_at(i)

func _escort_count() -> int:
	return clampi(wingmen_count,0,MAX_LEVEL)

func _escort_pos(index: int) -> Vector2:
	var side = -1.0 if index%2 == 0 else 1.0
	var row = int(index/2)
	return player+Vector2(side*(28+row*17),20+row*13)

func _add_enemy(kind: String, pos: Vector2, health: int, pattern: int):
	var radius = 40.0 if kind == "core" else 24.0 if kind == "frame" else 18.0
	enemies.append({"kind":kind, "p":pos-Vector2(0,180), "home":pos, "hp":health, "max":health, "boss":kind == "core", "pattern":pattern, "cool":maxf(0.65,1.7-survival_time/100)+randf()*0.45, "age":0.0, "flash":0.0, "radius":radius})
	total_spawned += 1

func _process(dt):
	dt = minf(dt, 0.04)
	music_duck = maxf(0.0,music_duck-dt*1.8)
	music.volume_db = lerpf(music.volume_db,MUSIC_DB-music_duck*10,1-exp(-dt*25))
	if mode == "paused":
		queue_redraw()
		return
	clock += dt
	shake = maxf(0, shake-dt*24)
	flash = maxf(0, flash-dt*3)
	message_time = maxf(0, message_time-dt)
	for st in stars:
		st[0].y += dt*(2+st[2]*5)
		if st[0].y > 720: st[0].y = 0
	for i in range(particles.size()-1,-1,-1):
		var p = particles[i]
		p.p += p.v*dt
		p.v *= 1.0-dt*1.5
		p.life -= dt
		if p.life <= 0: particles.remove_at(i)
	if demo_mode: _update_pilot(dt)
	if mode == "playing": _update_game(dt)
	if test_mode: _smoke(dt)
	if combat_test: _combat_test(dt)
	if endless_test: _test_endless(dt)
	if screenshot_pending and clock > 5.0:
		screenshot_pending = false
		_capture.call_deferred()
	queue_redraw()
	if force_movie_draw: _draw_movie_frame.call_deferred(dt)

func _draw_movie_frame(dt: float):
	RenderingServer.force_draw(true,dt)

func _update_game(dt: float):
	_update_director(dt)
	invincible = maxf(0, invincible-dt)
	var move = Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	move += Vector2(float(Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_UP)))
	var pad_aim = Vector2.ZERO
	if Input.get_connected_joypads().size() > 0:
		var id = Input.get_connected_joypads()[0]
		var stick = Vector2(Input.get_joy_axis(id, JOY_AXIS_LEFT_X), Input.get_joy_axis(id, JOY_AXIS_LEFT_Y))
		if stick.length() > 0.18: move += stick
		pad_aim = Vector2(Input.get_joy_axis(id, JOY_AXIS_RIGHT_X), Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y))
	if demo_mode: move = pilot_move
	if move.length() > 1: move = move.normalized()
	player += move*dt*(145 if not demo_mode and Input.is_physical_key_pressed(KEY_SHIFT) else 310)
	player = player.clamp(Vector2(38,70), Vector2(1242,650))
	_update_pickups(dt)
	aim = Vector2.UP
	var firing = demo_mode or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or auto_fire or pad_aim.length() > 0.3
	if not Input.get_connected_joypads().is_empty():
		firing = firing or Input.get_joy_axis(Input.get_connected_joypads()[0], JOY_AXIS_TRIGGER_RIGHT) > 0.2
	fire_cd -= dt
	if firing and fire_cd <= 0:
		fire_cd = _weapon_interval()
		_fire(player, aim)
		escort_cd -= _weapon_interval()
		if escort_cd <= 0:
			escort_cd = 0.18
			for i in _escort_count(): _fire(_escort_pos(i),aim,true)
		for i in allies.size():
			if allies[i] <= 0: _fire(_ally_pos(i), aim.rotated((i-2.5)*0.024))
		sfx("shot")
	for i in allies.size(): allies[i] = maxf(0, allies[i]-dt)
	for e in enemies:
		e.age += dt
		e.flash = maxf(0, e.flash-dt*5)
		var target = e.home+Vector2(sin(e.age*0.65+e.pattern)* (85 if e.boss else 32), sin(e.age*0.8+e.pattern)*15)
		if e.age > (51 if e.boss else 28): target.y = -180
		e.p = e.p.lerp(target, 1-exp(-dt*2))
		e.cool -= dt
		if e.cool <= 0 and e.age > maxf(0.85,2.0-survival_time/100) and e.p.y>55:
			_pattern(e)
			e.cool = maxf(0.72, 1.9/(1.0+survival_time/145)) if e.boss else maxf(1.05, 2.8/(1.0+survival_time/140))
	for i in range(shots.size()-1,-1,-1):
		var s = shots[i]
		s.prev = s.p
		s.p += s.v*dt
		s.life -= dt
		var consumed = false
		for e in enemies:
			var closest = Geometry2D.get_closest_point_to_segment(e.p, s.prev, s.p)
			if closest.distance_squared_to(e.p) <= pow(e.radius+2.0, 2):
				e.hp -= s.damage
				e.flash = 1.0
				sfx("impact")
				_burst(s.p, WHITE, 3)
				consumed = true
				break
		if not consumed:
			for j in range(bullets.size()-1,-1,-1):
				var b = bullets[j]
				if not b.hard and Geometry2D.get_closest_point_to_segment(b.p, s.prev, s.p).distance_squared_to(b.p) < 125:
					sfx("bullet_break")
					_burst(b.p, ORANGE, 3)
					bullets.remove_at(j)
					consumed = true
					break
		if consumed or s.life <= 0 or not Rect2(-50,-50,1380,820).has_point(s.p): shots.remove_at(i)
	for i in range(enemies.size()-1,-1,-1):
		if enemies[i].hp <= 0:
			_burst(enemies[i].p, WHITE, 65 if enemies[i].boss else 30)
			shake = 5 if enemies[i].boss else 2
			sfx("break_core" if enemies[i].boss else "break_heavy" if enemies[i].kind == "frame" else "break")
			score += int(ENEMY_POINTS[enemies[i].kind])
			_drop_key_loot(enemies[i])
			_gain_energy(8 if enemies[i].boss else 3 if enemies[i].kind == "frame" else 2)
			enemies.remove_at(i)
			kills += 1
		elif enemies[i].age > (55 if enemies[i].boss else 32):
			enemies.remove_at(i)
	for i in range(bullets.size()-1,-1,-1):
		var b = bullets[i]
		b.p += b.v*dt
		b.age += dt
		var removed = false
		if invincible <= 0:
			for j in allies.size():
				if allies[j] <= 0 and b.p.distance_squared_to(_ally_pos(j)) < 230:
					allies[j] = 7.0
					_burst(_ally_pos(j), WHITE, 35)
					message = "A support unit has fallen. Its signal will return."
					message_time = 3
					invincible = 0.4
					removed = true
					break
			if not removed and b.p.distance_squared_to(player) < pow(b.r+4, 2):
				_damage()
				removed = true
		if removed or not Rect2(-70,-70,1420,860).has_point(b.p) or b.age > 16: bullets.remove_at(i)
func _fire(pos: Vector2, dir: Vector2, escort: bool = false):
	if shots.size() > 500: return
	var angles: Array = [0.0]
	if not escort:
		if weapon_level >= 2: angles.append_array([-0.075,0.075])
		if weapon_level >= 6: angles.append_array([-0.15,0.15])
	for angle in angles:
		var heading = dir.rotated(angle)
		for side in [-1,1]:
			var p = pos+heading.orthogonal()*side*4+heading*14
			var damage = (4.0+minf(weapon_level,16)*0.45)*(0.6 if escort else 1.0)
			shots.append({"p":p,"prev":p,"v":heading*950,"life":1.6,"damage":damage})

func _pattern(e: Dictionary):
	sfx("enemy_core" if e.boss else "enemy_shot")
	var intensity = mini(12,int(survival_time/30))
	var speed_scale = 1.0+minf(1.15,survival_time/260)
	var origin: Vector2 = e.p+Vector2(0,e.radius+5)
	var to_player = (player-origin).angle()
	var pattern: int = e.pattern%5
	if not e.boss:
		var count = mini(7,3+intensity/3) if e.kind == "frame" else mini(5,1+intensity/3)
		for i in count:
			_bullet(origin, to_player+(i-(count-1)/2.0)*0.15, 125*speed_scale, e.kind == "frame" and intensity >= 3 and i%3 == 0)
		return
	match pattern:
		0:
			for i in 18+intensity:
				_bullet(origin, TAU*i/(18.0+intensity)+e.age*0.35, 115*speed_scale, i%4==0 and intensity>1)
		1:
			for j in 3:
				for i in 7:
					_bullet(origin+Vector2((j-1)*60,0), to_player+(i-3)*0.13, (130+j*25)*speed_scale, j==1)
		2:
			for i in 25:
				_bullet(origin, TAU*i/25.0+e.age*0.5, 135*speed_scale, i%3==0)
		3:
			for i in 13:
				var p = Vector2(100+i*90,90)
				_bullet(p, PI/2+sin(e.age+i)*0.24, 145*speed_scale, i%3==0)
			for i in 7: _bullet(origin, to_player+(i-3)*0.09,minf(330,185*speed_scale),false)
		4:
			for j in 2:
				for i in 22:
					_bullet(origin, TAU*i/22.0+e.age*(0.23 if j==0 else -0.23), (120+j*35)*speed_scale, j==1)

func _bullet(pos: Vector2, angle: float, speed: float, hard: bool):
	if bullets.size() >= 1000: return
	bullets.append({"p":pos,"v":Vector2.from_angle(angle)*speed,"hard":hard,"r":7.0 if hard else 6.0,"age":0.0})

func _damage():
	if invincible > 0: return
	if demo_mode: pilot_hits += 1
	invincible = 2
	if wingmen_count > 0:
		sfx("wing_loss")
		var lost_position = _escort_pos(_escort_count()-1)
		wingmen_count -= 1
		boost_time = 0
		shake = 6
		flash = 0.2
		_burst(lost_position,WHITE,38)
	else:
		sfx("hit")
		hp -= 1
		shake = 13
		flash = 0.6
		_burst(player, RED, 45)
	if demo_mode:
		print("PILOT HIT time=",snappedf(pilot_elapsed,0.01)," hp=",hp," level=",wingmen_count," escorts=",_escort_count())
	if hp <= 0:
		sfx("down")
		deaths += 1
		mode = "dead"
		_save_record()
		selection = 0

func _load_record():
	if not FileAccess.file_exists("user://records.cfg"): return
	var record = ConfigFile.new()
	if record.load("user://records.cfg") == OK:
		best_score = maxi(0,int(record.get_value("score","best",0)))

func _save_record():
	# Automated runs and fixtures never overwrite the player's record.
	if demo_mode or test_mode or endless_test or combat_test: return
	best_score = maxi(best_score,score)
	var record = ConfigFile.new()
	record.set_value("score","best",best_score)
	var result = record.save("user://records.cfg")
	if result != OK: push_warning("Could not save high score: "+str(result))

func _ally_pos(i: int) -> Vector2:
	return player+Vector2.from_angle(-PI/2+i*TAU/6+sin(clock*0.4)*0.15)*52

func _burst(pos: Vector2, color: Color, count: int):
	for i in mini(count,maxi(0,2200-particles.size())):
		var life = randf_range(0.2, 0.95)
		particles.append({"p":pos,"v":Vector2.from_angle(randf()*TAU)*randf_range(25,240),"life":life,"max":life,"c":color,"size":randf_range(1,3)})

func _draw():
	draw_rect(Rect2(0,0,1280,720),BG)
	for st in stars:
		draw_circle(st[0],st[2],Color(0.62,0.65,0.65,st[1]*(0.6+0.2*sin(clock+st[0].x))))
	# Almost invisible architectural lines: credits remain the visual focus.
	for x in range(0,1281,80): draw_line(Vector2(x,0),Vector2(x,720),Color(0.6,0.6,0.55,0.018))
	for y in range(0,721,80): draw_line(Vector2(0,y),Vector2(1280,y),Color(0.6,0.6,0.55,0.018))
	if mode in ["playing","dead","paused","help"]:
		var offset = Vector2(randf_range(-shake,shake),randf_range(-shake,shake))
		draw_set_transform(offset)
		_draw_battle()
		draw_set_transform(Vector2.ZERO)
		_draw_hud()
	for p in particles:
		var c: Color = p.c
		c.a = p.life/p.max
		draw_line(p.p,p.p-p.v*0.025,c,p.size,true)
	if mode != "playing":
		if mode in ["dead","paused","help"]: draw_rect(Rect2(0,0,1280,720),Color(0.015,0.016,0.018,0.86))
		_draw_menu()
	if flash>0: draw_rect(Rect2(0,0,1280,720),Color(0.8,0.12,0.1,flash*0.2))
	# Fine scanline texture.
	for y in range(0,720,3): draw_line(Vector2(0,y),Vector2(1280,y),Color(0,0,0,0.13))

func _draw_battle():
	for item in pickups:
		var color = Color("c3d9d1")
		color.a = 0.65+0.25*sin(item.age*5)
		var p: Vector2 = item.p
		draw_circle(p,17,Color(BG,0.9))
		draw_arc(p,17,-PI*0.75,PI*0.75,28,color,1.2,true)
		_ship(p,Vector2.UP,0.5,color)
		draw_line(p+Vector2(18,-2),p+Vector2(24,-2),color,1.5,true)
		draw_line(p+Vector2(21,-5),p+Vector2(21,1),color,1.5,true)

	for e in enemies:
		_draw_enemy(e)
	for s in shots:
		var dir: Vector2 = s.v.normalized()
		draw_line(s.p,s.p-dir*26,Color(0.8,0.85,0.9,0.1),7,true)
		draw_line(s.p,s.p-dir*20,WHITE,2,true)
	for b in bullets:
		var c = RED if b.hard else ORANGE
		draw_circle(b.p,b.r+6,Color(c,0.045))
		draw_circle(b.p,b.r+3,Color(c,0.12))
		draw_circle(b.p,b.r,c.darkened(0.55))
		draw_arc(b.p,b.r-0.5,0,TAU,16,c,1.6,true)
		draw_circle(b.p,b.r*0.45,c.lightened(0.25))
	for i in _escort_count():
		draw_line(player,_escort_pos(i),Color(WHITE,0.1),1,true)
		_ship(_escort_pos(i),Vector2.UP,0.45,Color(WHITE,0.8))
	if boost_time>0:
		draw_arc(player,20+(1.4-boost_time)*65,0,TAU,48,Color(WHITE,boost_time*0.35),1,true)
	for i in allies.size():
		if allies[i]<=0:
			draw_line(player,_ally_pos(i),Color(0.9,0.9,0.8,0.12),1,true)
			_ship(_ally_pos(i),Vector2.UP,0.8,Color("b8c8cb"))
	if mode != "dead" and (invincible<=0 or invincible>100 or int(clock*12)%3!=0):
		_ship(player,Vector2.UP,1.0,WHITE)
		if Input.is_physical_key_pressed(KEY_SHIFT):
			draw_arc(player,13,0,TAU,32,Color(1,1,1,0.35),1,true)
			draw_circle(player,3,Color.WHITE)

func _draw_enemy(e: Dictionary):
	var pos: Vector2 = e.p
	var c = Color("b4b5af").lerp(Color.WHITE,e.flash)
	var fill = Color("1a1d1e").lerp(WHITE,e.flash*0.65)
	var pulse = 0.5+0.5*sin(e.age*2.0)
	# The tiny warm aperture ties each machine to its projectiles.
	var aperture = Color("bd9a70").lerp(WHITE,e.flash)
	if e.kind == "drone":
		var body = PackedVector2Array([pos+Vector2(0,-24),pos+Vector2(20,0),pos+Vector2(0,24),pos+Vector2(-20,0)])
		draw_colored_polygon(body,fill)
		body.append(body[0])
		draw_polyline(body,c,1.5,true)
		draw_line(pos+Vector2(-29,-7),pos+Vector2(-29,7),Color(c,0.5),2,true)
		draw_line(pos+Vector2(29,-7),pos+Vector2(29,7),Color(c,0.5),2,true)
		draw_rect(Rect2(pos-Vector2(3,3),Vector2(6,6)),aperture)
	elif e.kind == "frame":
		draw_circle(pos,24,fill)
		# Four separated corners read as a heavier, square chassis.
		for i in 4:
			var angle = i*PI/2+PI/4
			var corner = pos+Vector2.from_angle(angle)*36
			var edge_a = corner+Vector2.from_angle(angle+PI*0.75)*18
			var edge_b = corner+Vector2.from_angle(angle-PI*0.75)*18
			draw_polyline(PackedVector2Array([edge_a,corner,edge_b]),c,2,true)
		draw_arc(pos,15,0,TAU,32,Color(c,0.45),1,true)
		draw_line(pos-Vector2(5,0),pos+Vector2(5,0),aperture,3,true)
	else:
		# A single hollow hub, with two slow counter-rotating broken rings.
		draw_circle(pos,40,fill)
		draw_arc(pos,40,0,TAU,64,c,1.8,true)
		for i in 4:
			var start = i*PI/2+e.age*0.16
			draw_arc(pos,53,start,start+0.85,16,Color(c,0.7),2,true)
		for i in 2:
			var start = i*PI-e.age*0.12
			draw_arc(pos,63,start,start+0.5,12,Color(c,0.3),1,true)
		draw_arc(pos,21,0,TAU,40,Color(c,0.3),1,true)
		var core = PackedVector2Array([pos+Vector2(0,-8),pos+Vector2(8,0),pos+Vector2(0,8),pos+Vector2(-8,0)])
		draw_colored_polygon(core,Color(aperture,0.65+pulse*0.35))
	# A brief bloom confirms hits without labels or health bars.
	if e.flash > 0:
		draw_circle(pos,e.radius+5,Color(WHITE,e.flash*0.07))

func _ship(pos: Vector2, dir: Vector2, scale_factor: float, color: Color):
	var points = PackedVector2Array()
	for v in [Vector2(0,-17),Vector2(12,13),Vector2(0,7),Vector2(-12,13)]:
		points.append(pos+v.rotated(dir.angle()+PI/2)*scale_factor)
	draw_colored_polygon(points,color)
	var tail = pos-dir*12*scale_factor
	draw_line(tail,tail-dir*(12+sin(clock*45)*5)*scale_factor,Color(0.75,0.82,0.85,0.7),3,true)
	draw_line(pos-dir*5,pos+dir*9,BG,1.2,true)

func _draw_hud():
	# Only remaining lives stay on screen; instructions live in Controls.
	for i in 3:
		draw_rect(Rect2(38+i*16,35,10,3),Color(WHITE,0.65) if i<hp else Color(WHITE,0.1))
	var score_text = str(score).pad_zeros(6)
	_text(score_text,Vector2(1242-font.get_string_size(score_text,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x,38),17,Color(WHITE,0.7))
	var progress = 1.0 if weapon_level >= MAX_LEVEL else float(energy)/_energy_needed()
	draw_line(Vector2(38,45),Vector2(80,45),Color(WHITE,0.1),1)
	draw_line(Vector2(38,45),Vector2(38+42*progress,45),Color(WHITE,0.45),1)

func _text(content: String, pos: Vector2, size: int, color: Color = WHITE, center: bool = false):
	var p = pos
	if center: p.x -= font.get_string_size(content,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x/2
	draw_string(font,p,content,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func _rule(y: float, width: float = 720):
	draw_line(Vector2(640-width/2,y),Vector2(640+width/2,y),Color(0.8,0.78,0.7,0.32),1)
	for x in [640-width/2,640+width/2]:
		draw_colored_polygon(PackedVector2Array([Vector2(x,y-3),Vector2(x+3,y),Vector2(x,y+3),Vector2(x-3,y)]),MUTED)

func _button(label: String, index: int, y: float):
	if selection==index:
		draw_rect(Rect2(440,y-26,400,44),Color("c9c6bb"))
		_text(label,Vector2(640,y+2),17,BG,true)
	else:
		_text(label,Vector2(640,y+2),17,MUTED,true)

func _draw_menu():
	match mode:
		"title":
			_text("BULLET STORM",Vector2(640,293),64,WHITE,true)
			_button("START",0,460)
			_button("CONTROLS",1,518)
		"controls":
			_text("CONTROLS",Vector2(640,195),30,WHITE,true)
			_rule(230)
			var rows = ["WASD / ARROWS     Move", "SPACE / CLICK     Fire", "SHIFT     Slow movement", "ESC     Pause"]
			for i in rows.size(): _text(rows[i],Vector2(640,290+i*44),18,WHITE,true)
			_button("RETURN",0,554)
		"dead":
			_text("%02d:%02d   /   %d" % [int(survival_time)/60,int(survival_time)%60,score],Vector2(640,220),16,MUTED,true)
			_text("BEST  "+str(maxi(best_score,score)).pad_zeros(6),Vector2(640,247),12,MUTED,true)
			_text("Do you accept defeat?",Vector2(640,296),36,WHITE,true)
			_rule(335)
			_text(ENCOURAGEMENT[mini(deaths-1,3)],Vector2(640,378),17,MUTED,true)
			_button("TRY AGAIN",0,444)
			_button("RETURN TO TITLE",1,500)
		"help":
			_text("You do not have to do this alone.",Vector2(640,288),32,WHITE,true)
			_rule(325)
			_text("Accept assistance from six other units?",Vector2(640,370),19,WHITE,true)
			_button("ACCEPT SUPPORT",0,442)
			_button("KEEP FIGHTING ALONE",1,498)
		"paused":
			_text("PAUSED",Vector2(640,281),30,WHITE,true)
			_rule(322)
			_button("RESUME",0,420)
			_button("RETURN TO TITLE",1,478)

func _capture():
	var path = "res://build/preview.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE: ",path)

func _smoke(_dt: float):
	if test_phase > 0: return
	test_phase = 1
	_update_director(4)
	assert(total_spawned > 0,"Continuous spawning failed")
	_gain_energy(10000)
	assert(weapon_level==6 and wingmen_count==0,"XP must upgrade weapons without granting wingmen")
	enemies.clear()
	shots.clear()
	bullets.clear()
	spawn_cd = 99
	core_cd = 99
	_add_enemy("drone",Vector2(300,120),1,0)
	enemies[0].hp = 0
	_update_game(1.0/60)
	assert(pickups.is_empty(),"Ordinary enemy must not drop a wingman")
	assert(score==100,"Drone score failed")
	_add_enemy("core",Vector2(640,120),1,0)
	enemies[0].p = Vector2(640,120)
	enemies[0].hp = 0
	_update_game(1.0/60)
	assert(pickups.size()==1 and wingmen_count==0,"Key enemy must drop physical loot, not grant a wingman")
	assert(score==1600,"Core score failed or awarded twice")
	player = pickups[0].p
	_update_pickups(0)
	assert(wingmen_count==1 and pickups.is_empty(),"Contact must collect the wingman")
	for i in 5:
		_drop_key_loot({"kind":"frame","p":player})
		_update_pickups(0)
	assert(wingmen_count==6,"Pickup cap failed")
	_drop_key_loot({"kind":"core","p":player})
	_update_pickups(0)
	assert(wingmen_count==6 and pickups.size()==1,"Full formation must leave loot available")
	shots.clear()
	_fire(player,Vector2.UP)
	var damage: float = shots[0].damage
	var shot_count = shots.size()
	var interval = _weapon_interval()
	invincible = 0
	_damage()
	assert(wingmen_count==5 and hp==3 and weapon_level==6,"Hit must lose escort while retaining hull weapon")
	shots.clear()
	_fire(player,Vector2.UP)
	assert(shots.size()==shot_count and shots[0].damage==damage and _weapon_interval()==interval,"Damage/rate/spread decreased after losing a wingman")
	_update_pickups(0)
	assert(wingmen_count==6,"A later pickup must replace a lost wingman")
	# Even complete escort loss must leave full primary firepower.
	for i in 6:
		invincible = 0
		_damage()
	assert(wingmen_count==0 and weapon_level==6 and hp==3,"Escort losses weakened the main ship")
	_drop_key_loot({"kind":"frame","p":player})
	_update_pickups(0)
	assert(wingmen_count==1,"Comeback pickup failed")
	_drop_key_loot({"kind":"core","p":Vector2(300,100)})
	_update_pickups(13)
	assert(pickups.is_empty(),"Uncollected loot must expire")
	enemies.clear()
	bullets.clear()
	shots.clear()
	_fire(player,Vector2.UP)
	var velocities: Array = []
	for shot in shots: velocities.append(shot.v)
	var was_demo = demo_mode
	demo_mode = true
	pilot_move = Vector2.RIGHT
	fire_cd = 1
	aim = Vector2.LEFT
	_update_game(1.0/60)
	assert(aim==Vector2.UP,"Moving must not turn the ship or shot direction")
	for i in shots.size(): assert(shots[i].v==velocities[i],"In-flight trajectories must not change")
	demo_mode = was_demo
	_retry()
	assert(weapon_level==0 and wingmen_count==0 and pickups.is_empty() and score==0,"Restart must reset progression and score")
	print("SMOKE PASS: key enemy drops, contact pickup, six cap, no automatic escorts, retained primary damage/rate/spread after all escort losses, recovery, expiry, fixed upward aim, straight projectile paths, kill scoring, restart")
	get_tree().quit()

func _test_endless(dt: float):
	endless_test_time += dt
	if endless_test_time >= 180:
		assert(survival_time > 179,"Simulation did not advance continuously")
		assert(total_spawned > 60,"Director stopped spawning")
		assert(weapon_level >= 4,"Weapon progression failed")
		assert(pickups_collected>0,"Pilot did not collect physical loot")
		assert(mode == "playing","Unexpected finite ending")
		assert(shots.size()<=550 and bullets.size()<=1000 and enemies.size()<=20,"Object limits exceeded")
		print("ENDLESS PASS seconds=",survival_time," spawned=",total_spawned," kills=",kills," escorts=",wingmen_count," weapon=",weapon_level," hp=",hp," hits=",pilot_hits," bullets=",bullets.size())
		get_tree().quit()

# Autopilot uses the same movement, weapon cooldown and collision rules as a player.
# Only visible projectile positions and velocities inform its short lookahead.
func _update_pilot(dt: float):
	pilot_elapsed += dt
	if pilot_elapsed >= pilot_report:
		print("PILOT time=",snappedf(pilot_elapsed,0.1)," hp=",hp," hits=",pilot_hits," pressure=",stage+1," kills=",kills," escorts=",wingmen_count," weapon=",weapon_level," bullets=",bullets.size()," assist=",assist)
		pilot_report += 10.0
	if recording_limit > 0 and mode == "dead":
		recording_death_hold += dt
		if recording_death_hold < 3.0: return
	if mode == "dead" or (pilot_test and pilot_elapsed >= 120.0) or (recording_limit > 0 and pilot_elapsed >= recording_limit):
		print("PILOT RESULT mode=",mode," seconds=",pilot_elapsed," hp=",hp," hits=",pilot_hits," pressure=",stage+1," kills=",kills)
		get_tree().quit(1 if mode == "dead" else 0)
		return
	if mode != "playing": return
	pilot_think -= dt
	if pilot_think > 0: return
	pilot_think = 0.065
	var nearby: Array = []
	for b in bullets:
		if b.p.distance_squared_to(player)<pow(540,2): nearby.append(b)
	var preferred = Vector2(640,550)
	var pickup_target = false
	var target_cost = INF
	for enemy in enemies:
		if enemy.p.y < 55 or enemy.p.y > player.y-70: continue
		var score = absf(enemy.p.x-player.x)*0.6+enemy.hp*0.12
		if enemy.boss: score += 120
		if enemy.kind == "frame" and wingmen_count < MAX_LEVEL: score -= 90
		if score < target_cost:
			target_cost = score
			preferred.x = clampf(enemy.p.x,70,1210)
	if wingmen_count < MAX_LEVEL:
		var nearest = INF
		for item in pickups:
			if item.p.y < 300 or item.p.y > 675: continue
			var distance = item.p.distance_squared_to(player)
			if distance > 360*360: continue
			if distance < nearest:
				nearest = distance
				pickup_target = true
				preferred = Vector2(clampf(item.p.x,70,1210),clampf(item.p.y+12,370,630))

	var escape_edge = player.x < 190 or player.x > 1090
	if escape_edge:
		preferred.y = 270
	var best_cost = INF
	var best_move = Vector2.ZERO
	for candidate in 33:
		var direction = Vector2.ZERO
		if candidate > 0:
			var speed = 1.0 if candidate <= 16 else 0.47
			direction = Vector2.from_angle(float((candidate-1)%16)*TAU/16)*speed
		var velocity = direction*310
		var end = player+velocity*0.65
		var tracking_end = player+velocity*0.16
		var cost = absf(tracking_end.x-preferred.x)*2.5
		cost += absf(tracking_end.y-preferred.y)*1.5 if (pickup_target or escape_edge) else pow(tracking_end.y-preferred.y,2)*0.0002
		cost += direction.distance_squared_to(pilot_move)*1.4
		if end.x<62: cost += pow(62-end.x,2)*0.3
		if end.x>1218: cost += pow(end.x-1218,2)*0.3
		if end.y<120: cost += pow(120-end.y,2)*0.3
		if end.y>645: cost += pow(end.y-645,2)*0.3
		for enemy in enemies:
			var body_distance = (player+velocity*0.35).distance_to(enemy.p)
			if body_distance < enemy.radius+45: cost += pow(enemy.radius+45-body_distance,2)*4
		for b in nearby:
			var relative: Vector2 = b.p-player
			var relative_v: Vector2 = b.v-velocity
			var time = clampf(-relative.dot(relative_v)/maxf(relative_v.length_squared(),1),0,0.5)
			# Use the ordinary post-hit protection to escape a closing lane.
			# This reads the existing timer; it never grants or extends protection.
			if invincible > time+0.15: continue
			var distance = (relative+relative_v*time).length()
			var safe = b.r+4+23
			if distance < safe:
				cost += pow(safe-distance,2)*2.0/(0.25+time)
			if distance < b.r+6:
				cost += 100000.0/(0.2+time)
		if cost < best_cost:
			best_cost = cost
			best_move = direction
	pilot_move = best_move

func _combat_test(_dt: float):
	# Kept as a CLI alias for the current continuous combat validation.
	combat_test = false
	endless_test = true
	demo_mode = true

func _exit_tree():
	if demo_mode: print("AUDIO EVENTS ",sound_counts)
	if demo_mode:
		print("RECORD SUMMARY score=",score," seconds=",survival_time," escorts=",wingmen_count," weapon=",weapon_level," hp=",hp," hits=",pilot_hits," kills=",kills," spawned=",total_spawned," assist=",assist)
	music.stop()
	for pool in sounds.values():
		for voice in pool: voice.stop()
	sounds.clear()
