extends CharacterBody3D

# Controlador de Personaje (FPS) para el Escuadrón de Supervivientes
# Compatible con replicación multijugador nativa de Godot 4.

@export var velocidad_base: float = 4.5
@export var velocidad_sprint: float = 7.0
@export var fuerza_salto: float = 4.5
@export var sensibilidad_raton: float = 0.003

# Atributos de Supervivencia y Combate
@export var salud_maxima: float = 100.0
@export var danio_arma_inicial: float = 28.0
var salud_actual: float = 100.0
var esta_derribado: bool = false
var rol: int = 1 # Por defecto Militar (RedManager.Rol)

# Variables de rol / pasivas
var multiplicador_velocidad: float = 1.0
var multiplicador_recarga: float = 1.0
var multiplicador_reparacion: float = 1.0

# Sistema de Munición y Recarga
var cargador_maximo: int = 15
var cargador_actual: int = 15
var municion_reserva: int = 60
var recargando: bool = false
var tiempo_recarga_base: float = 1.4

# Economía / Suministros acumulados
var suministros: int = 0

# Timers de disparo
var puede_disparar: bool = true
var cadencia_disparo: float = 0.25

@onready var cabeza: Node3D = $Cabeza
@onready var camara: Camera3D = $Cabeza/Camera3D
@onready var raycast_disparo: RayCast3D = $Cabeza/RayCastDisparo
@onready var sincronizador: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var hud: CanvasLayer = $HUD

var gravedad: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	salud_actual = salud_maxima
	aplicar_bonificaciones_rol()

	if is_multiplayer_authority():
		camara.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		hud.visible = true
		hud.actualizar_salud(salud_actual, salud_maxima)
		hud.actualizar_municion(cargador_actual, municion_reserva)
		hud.actualizar_suministros(suministros)
		hud.configurar_rol(_obtener_nombre_rol())
		# Mostrar regla inicial estilo Zombieland
		hud.mostrar_regla(1, "Cardio", "Mantén el ritmo al correr; los infectados no se cansan.")
	else:
		camara.current = false
		hud.visible = false

func _obtener_nombre_rol() -> String:
	match rol:
		0: return "Médico"
		1: return "Militar"
		2: return "Carpintero"
		3: return "Explorador"
		_: return "Superviviente"

func aplicar_bonificaciones_rol() -> void:
	match rol:
		0: # MEDICO
			multiplicador_reparacion = 1.0
			danio_arma_inicial = 35.0
			cargador_maximo = 15
		1: # MILITAR (+35% cargador, -40% tiempo recarga)
			multiplicador_recarga = 0.6
			danio_arma_inicial = 28.0
			cargador_maximo = int(15 * 1.35) # ~20 balas
			cargador_actual = cargador_maximo
		2: # CARPINTERO
			multiplicador_reparacion = 2.0
			danio_arma_inicial = 35.0
		3: # EXPLORADOR (+15% velocidad)
			multiplicador_velocidad = 1.15
			danio_arma_inicial = 35.0

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * sensibilidad_raton)
		cabeza.rotate_x(-event.relative.y * sensibilidad_raton)
		cabeza.rotation.x = clamp(cabeza.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity.y -= gravedad * delta

	if esta_derribado:
		velocity.x = move_toward(velocity.x, 0.0, 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 5.0 * delta)
		move_and_slide()
		return

	# Detección de objetos interactuables al mirar hacia ellos
	actualizar_prompt_interaccion()

	# Procesar Disparo
	if Input.is_action_just_pressed("disparar") and puede_disparar and not recargando:
		ejecutar_disparo()

	# Procesar Recarga (Tecla R)
	if Input.is_action_just_pressed("recargar") and not recargando:
		ejecutar_recarga()

	# Procesar Interacción (Tecla E)
	if Input.is_action_just_pressed("interactuar"):
		ejecutar_interaccion()

	if Input.is_action_just_pressed("saltar") and is_on_floor():
		velocity.y = fuerza_salto

	var sprint = Input.is_action_pressed("correr")
	var vel_objetivo = (velocidad_sprint if sprint else velocidad_base) * multiplicador_velocidad

	var input_dir = Input.get_vector("izquierda", "derecha", "adelante", "atras")
	var direccion = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direccion != Vector3.ZERO:
		velocity.x = direccion.x * vel_objetivo
		velocity.z = direccion.z * vel_objetivo
	else:
		velocity.x = move_toward(velocity.x, 0.0, vel_objetivo)
		velocity.z = move_toward(velocity.z, 0.0, vel_objetivo)

	move_and_slide()

func actualizar_prompt_interaccion() -> void:
	if raycast_disparo.is_colliding():
		var col = raycast_disparo.get_collider()
		if col and col.has_method("intentar_reparar"):
			hud.mostrar_prompt_interaccion("[E] Reparar Barricada", true)
			return
		elif col and col.has_method("saquear"):
			hud.mostrar_prompt_interaccion("[E] Saquear Suministros", true)
			return
	hud.mostrar_prompt_interaccion("", false)

func ejecutar_disparo() -> void:
	if cargador_actual <= 0:
		ejecutar_recarga()
		return

	puede_disparar = false
	cargador_actual -= 1
	hud.actualizar_municion(cargador_actual, municion_reserva)
	
	if raycast_disparo.is_colliding():
		var objetivo = raycast_disparo.get_collider()
		if objetivo and objetivo.is_in_group("enemigos"):
			rpc_id(1, "servidor_aplicar_danio_a_enemigo", objetivo.get_path(), danio_arma_inicial)

	await get_tree().create_timer(cadencia_disparo).timeout
	puede_disparar = true

func ejecutar_recarga() -> void:
	if cargador_actual == cargador_maximo or municion_reserva <= 0 or recargando:
		return

	recargando = true
	var tiempo = tiempo_recarga_base * multiplicador_recarga
	await get_tree().create_timer(tiempo).timeout

	var faltante = cargador_maximo - cargador_actual
	var a_cargar = min(faltante, municion_reserva)
	cargador_actual += a_cargar
	municion_reserva -= a_cargar
	recargando = false

	hud.actualizar_municion(cargador_actual, municion_reserva)

func ejecutar_interaccion() -> void:
	if raycast_disparo.is_colliding():
		var objeto = raycast_disparo.get_collider()
		if objeto and objeto.has_method("intentar_reparar"):
			var es_carpintero = (rol == 2)
			objeto.intentar_reparar(es_carpintero)
			hud.mostrar_regla(17, "No seas un héroe", "Mantener las barricadas en pie salva vidas.")

@rpc("any_peer", "call_local")
func servidor_aplicar_danio_a_enemigo(ruta_enemigo: NodePath, cantidad: float) -> void:
	if not multiplayer.is_server():
		return
	
	var enemigo = get_node_or_null(ruta_enemigo)
	if enemigo and enemigo.has_method("recibir_danio"):
		enemigo.recibir_danio(cantidad)

@rpc("any_peer", "call_local")
func recibir_danio(cantidad: float) -> void:
	if not multiplayer.is_server():
		return

	if esta_derribado:
		return

	salud_actual -= cantidad
	if salud_actual <= 0.0:
		salud_actual = 0.0
		esta_derribado = true
		rpc("sincronizar_derribo", true)
	else:
		rpc("sincronizar_salud", salud_actual)

@rpc("authority", "call_local")
func sincronizar_salud(nueva_salud: float) -> void:
	salud_actual = nueva_salud
	if is_multiplayer_authority():
		hud.actualizar_salud(salud_actual, salud_maxima)

@rpc("authority", "call_local")
func sincronizar_derribo(derribado: bool) -> void:
	esta_derribado = derribado
	if is_multiplayer_authority():
		hud.actualizar_salud(0.0, salud_maxima)
		hud.mostrar_estado_derribado(derribado)
