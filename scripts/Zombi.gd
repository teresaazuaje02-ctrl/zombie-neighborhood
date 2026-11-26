extends CharacterBody3D

# Controlador de Inteligencia Artificial para Zombis
# Maneja navegación con NavigationAgent3D, ataque a jugadores, daño a barricadas
# y reproducción automática de animaciones esqueléticas (.glb de Tripo/Mixamo).

enum TipoZombi {
	COMUN,
	BRUTO,
	CORREDOR,
	ESCUPIDOR,
	AULLADOR
}

@export var tipo: TipoZombi = TipoZombi.COMUN
@export var velocidad_base: float = 3.2
@export var salud_maxima: float = 60.0
@export var danio_ataque: float = 15.0
@export var distancia_ataque: float = 1.6
@export var cadencia_ataque: float = 1.2

var salud_actual: float = 60.0
var objetivo_actual: Node3D = null
var puede_atacar: bool = true
var gravedad: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var anim_player: AnimationPlayer = null
var anim_carrera: String = ""

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var timer_ataque: Timer = $TimerAtaque
@onready var sincronizador: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var detector_barricada: RayCast3D = $RayCastBarricada
@onready var visuales: Node3D = $VisualesZombi

func _ready() -> void:
	salud_actual = salud_maxima
	configurar_arquetipo()
	
	timer_ataque.wait_time = cadencia_ataque
	timer_ataque.timeout.connect(_al_timeout_ataque)

	# Buscar y activar automáticamente el AnimationPlayer del modelo importado
	_buscar_animation_player(visuales)

func _buscar_animation_player(nodo: Node) -> void:
	if nodo is AnimationPlayer:
		anim_player = nodo
		var lista_animaciones = anim_player.get_animation_list()
		print("Animaciones detectadas en el Zombi: ", lista_animaciones)
		
		if lista_animaciones.size() > 0:
			# Priorizar la animación más agresiva/modificada
			anim_carrera = lista_animaciones[-1]
			for nombre in lista_animaciones:
				var n_min = nombre.to_lower()
				# Dar prioridad absoluta a la animación de ataque agresivo donde mueve brazos y cuerpo
				if "super agresivo" in n_min or "ataque" in n_min:
					anim_carrera = nombre
					break
				elif "agresivo" in n_min or "corra" in n_min:
					anim_carrera = nombre

			# Conectar señal de fin de animación para bucle ininterrumpido garantizado
			if not anim_player.animation_finished.is_connected(_al_terminar_animacion):
				anim_player.animation_finished.connect(_al_terminar_animacion)

			# Configurar modo bucle (loop) en todas las animaciones
			for nombre in lista_animaciones:
				var a = anim_player.get_animation(nombre)
				if a:
					a.loop_mode = Animation.LOOP_LINEAR

			anim_player.play(anim_carrera)
			print("Reproduciendo animacion agresiva continua: ", anim_carrera)
		return

	for hijo in nodo.get_children():
		_buscar_animation_player(hijo)

func _al_terminar_animacion(_nombre_anim: StringName) -> void:
	if anim_player and anim_carrera != "":
		anim_player.play(anim_carrera)

func configurar_arquetipo() -> void:
	match tipo:
		TipoZombi.COMUN:
			velocidad_base = 3.2
			salud_maxima = 60.0
			danio_ataque = 15.0
		TipoZombi.BRUTO:
			velocidad_base = 2.0
			salud_maxima = 300.0
			danio_ataque = 40.0
			distancia_ataque = 2.2
		TipoZombi.CORREDOR:
			velocidad_base = 5.2
			salud_maxima = 40.0
			danio_ataque = 12.0
		TipoZombi.ESCUPIDOR:
			velocidad_base = 2.8
			salud_maxima = 50.0
		TipoZombi.AULLADOR:
			velocidad_base = 3.5
			salud_maxima = 75.0

func _process(_delta: float) -> void:
	# Asegurar que el zombi NUNCA permanezca congelado o en pose T
	if anim_player and anim_carrera != "":
		if not anim_player.is_playing():
			anim_player.play(anim_carrera)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if not is_on_floor():
		velocity.y -= gravedad * delta

	buscar_jugador_cercano()

	if objetivo_actual and is_instance_valid(objetivo_actual):
		nav_agent.target_position = objetivo_actual.global_position
		
		# Revisar si hay una barricada bloqueando el paso frontal
		if detector_barricada.is_colliding():
			var objeto_colisionado = detector_barricada.get_collider()
			if objeto_colisionado is StaticBody3D and objeto_colisionado.has_method("zombi_atacar_barricada"):
				if puede_atacar:
					atacar_barricada(objeto_colisionado)
				velocity.x = move_toward(velocity.x, 0.0, 5.0 * delta)
				velocity.z = move_toward(velocity.z, 0.0, 5.0 * delta)
				move_and_slide()
				return

		var distancia = global_position.distance_to(objetivo_actual.global_position)

		if distancia <= distancia_ataque:
			velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
			if puede_atacar:
				atacar_jugador()
		else:
			if not nav_agent.is_navigation_finished():
				var siguiente_pos = nav_agent.get_next_path_position()
				var direccion = (siguiente_pos - global_position).normalized()
				direccion.y = 0.0
				velocity.x = direccion.x * velocidad_base
				velocity.z = direccion.z * velocidad_base
				
				# Orientar mirada hacia la dirección de avance
				if direccion.length() > 0.1:
					look_at(global_position + direccion, Vector3.UP)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 4.0 * delta)

	move_and_slide()

func buscar_jugador_cercano() -> void:
	var jugadores = get_tree().get_nodes_in_group("jugadores")
	var distancia_minima = INF
	var candidato_mas_cercano: Node3D = null

	for j in jugadores:
		if is_instance_valid(j):
			var esta_derribado = j.get("esta_derribado")
			var dist = global_position.distance_to(j.global_position)
			if esta_derribado != null and not esta_derribado:
				if dist < distancia_minima:
					distancia_minima = dist
					candidato_mas_cercano = j
			elif candidato_mas_cercano == null and dist < distancia_minima:
				distancia_minima = dist
				candidato_mas_cercano = j

	objetivo_actual = candidato_mas_cercano

func atacar_jugador() -> void:
	puede_atacar = false
	timer_ataque.start()
	if objetivo_actual and objetivo_actual.has_method("recibir_danio"):
		objetivo_actual.recibir_danio(danio_ataque)

func atacar_barricada(barricada: Node) -> void:
	puede_atacar = false
	timer_ataque.start()
	var es_bruto = (tipo == TipoZombi.BRUTO)
	barricada.zombi_atacar_barricada(es_bruto)

func _al_timeout_ataque() -> void:
	puede_atacar = true

@rpc("any_peer", "call_local")
func recibir_danio(cantidad: float) -> void:
	if not multiplayer.is_server():
		return

	salud_actual -= cantidad
	if salud_actual <= 0.0:
		morir()

func morir() -> void:
	# Notificar a la tienda del tendero si fue eliminado en su perímetro de defensa
	var tiendas = get_tree().get_nodes_in_group("tienda_npc")
	for t in tiendas:
		if is_instance_valid(t) and global_position.distance_to(t.global_position) <= 15.0:
			if t.has_method("registrar_baja_zombi"):
				t.registrar_baja_zombi()
	queue_free()
