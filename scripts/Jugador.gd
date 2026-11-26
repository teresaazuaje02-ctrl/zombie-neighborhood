extends CharacterBody3D

# Controlador de Personaje (FPS) para el Escuadrón de Supervivientes
# Compatible con replicación multijugador nativa de Godot 4.
# Incluye soporte para modelos 3D de armas (.glb de Tripo3D), retroceso y balanceo (sway).

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

# Inventario y Munición
var cargador_maximo: int = 15
var cargador_actual: int = 15
var municion_reserva: int = 60
var recargando: bool = false
var tiempo_recarga_base: float = 1.4

var suministros: int = 0
var botiquines_auto_reanimar: int = 0

# Timers de disparo
var puede_disparar: bool = true
var cadencia_disparo: float = 0.25

# Referencias de Nodos
@onready var cabeza: Node3D = $Cabeza
@onready var camara: Camera3D = $Cabeza/Camera3D
@onready var raycast_disparo: RayCast3D = $Cabeza/RayCastDisparo
@onready var sincronizador: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var hud: CanvasLayer = $HUD

# Socket de Armas en Primera Persona
@onready var socket_arma: Node3D = $Cabeza/Camera3D/SocketArma
@onready var malla_pistola: Node3D = $Cabeza/Camera3D/SocketArma/Pistola9mm
@onready var malla_bate: Node3D = $Cabeza/Camera3D/SocketArma/BateClavos
@onready var fogonazo: OmniLight3D = $Cabeza/Camera3D/SocketArma/Fogonazo

var posicion_original_arma: Vector3 = Vector3(0.24, -0.22, -0.42)
var retroceso_actual: Vector3 = Vector3.ZERO
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
		socket_arma.visible = true
		actualizar_modelo_arma_visible()
		hud.actualizar_salud(salud_actual, salud_maxima)
		hud.actualizar_municion(cargador_actual, municion_reserva)
		hud.actualizar_suministros(suministros)
		hud.configurar_rol(_obtener_nombre_rol())
		hud.mostrar_regla(1, "Cardio", "Mantén el ritmo al correr; los infectados no se cansan.")
	else:
		camara.current = false
		hud.visible = false
		# Ocultar arma en primera persona para otros clientes
		socket_arma.visible = false

func actualizar_modelo_arma_visible() -> void:
	if rol == 1: # Militar inicia con arma de fuego (Pistola)
		malla_pistola.visible = true
		malla_bate.visible = false
	else: # Médico, Carpintero y Explorador inician con Bate
		malla_pistola.visible = false
		malla_bate.visible = true

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
			botiquines_auto_reanimar = 1
		1: # MILITAR (+35% cargador, -40% tiempo recarga)
			multiplicador_recarga = 0.6
			danio_arma_inicial = 28.0
			cargador_maximo = int(15 * 1.35)
			cargador_actual = cargador_maximo
		2: # CARPINTERO (Doble velocidad / doble tablón)
			multiplicador_reparacion = 2.0
			danio_arma_inicial = 35.0
		3: # EXPLORADOR (+15% velocidad, +35% botín)
			multiplicador_velocidad = 1.15
			danio_arma_inicial = 35.0

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * sensibilidad_raton)
		cabeza.rotate_x(-event.relative.y * sensibilidad_raton)
		cabeza.rotation.x = clamp(cabeza.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
		
		# Balanceo de arma por rotación de cámara (Weapon Sway)
		socket_arma.position.x = posicion_original_arma.x - (event.relative.x * 0.0003)
		socket_arma.position.y = posicion_original_arma.y + (event.relative.y * 0.0003)

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

	# Suavizar recuperación del retroceso y posición del arma
	socket_arma.position = socket_arma.position.lerp(posicion_original_arma + retroceso_actual, 12.0 * delta)
	retroceso_actual = retroceso_actual.lerp(Vector3.ZERO, 15.0 * delta)

	if esta_derribado:
		velocity.x = move_toward(velocity.x, 0.0, 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 5.0 * delta)
		move_and_slide()
		return

	actualizar_prompt_interaccion()

	if Input.is_action_just_pressed("disparar") and puede_disparar and not recargando:
		ejecutar_disparo()

	if Input.is_action_just_pressed("recargar") and not recargando:
		ejecutar_recarga()

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
		if col and col.has_method("intentar_reparar") and col.tablones_actuales < 4:
			hud.mostrar_prompt_interaccion("[E] Reparar Barricada", true)
			return
		elif col and col.has_method("saquear") and not col.ya_saqueado:
			hud.mostrar_prompt_interaccion("[E] Saquear Contenedor", true)
			return
	hud.mostrar_prompt_interaccion("", false)

func ejecutar_disparo() -> void:
	if rol == 1 and cargador_actual <= 0:
		ejecutar_recarga()
		return

	puede_disparar = false

	if rol == 1: # Militar dispara con munición
		cargador_actual -= 1
		hud.actualizar_municion(cargador_actual, municion_reserva)
		# Retroceso de arma de fuego hacia atrás y hacia arriba
		retroceso_actual = Vector3(0.0, 0.03, 0.08)
		activar_fogonazo()
	else: # Ataque cuerpo a cuerpo (Bate con clavos)
		retroceso_actual = Vector3(-0.06, -0.04, 0.1)

	if raycast_disparo.is_colliding():
		var objetivo = raycast_disparo.get_collider()
		if objetivo and objetivo.is_in_group("enemigos"):
			rpc_id(1, "servidor_aplicar_danio_a_enemigo", objetivo.get_path(), danio_arma_inicial)

	await get_tree().create_timer(cadencia_disparo).timeout
	puede_disparar = true

func activar_fogonazo() -> void:
	fogonazo.visible = true
	await get_tree().create_timer(0.05).timeout
	fogonazo.visible = false

func ejecutar_recarga() -> void:
	if rol != 1 or cargador_actual == cargador_maximo or municion_reserva <= 0 or recargando:
		return

	recargando = true
	var tiempo = tiempo_recarga_base * multiplicador_recarga
	# Animación simple de bajada de arma durante la recarga
	retroceso_actual = Vector3(0.0, -0.2, 0.05)
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
		if objeto:
			if objeto.has_method("intentar_reparar"):
				var es_carpintero = (rol == 2)
				var pudo = objeto.intentar_reparar(es_carpintero)
				if pudo:
					hud.mostrar_regla(17, "No seas un héroe", "Mantener las barricadas en pie salva vidas.")
			elif objeto.has_method("saquear"):
				objeto.saquear(self)

func recibir_botin(botin: Dictionary) -> void:
	suministros += botin.get("suministros", 0)
	municion_reserva += botin.get("municion", 0)
	
	if botin.get("botiquin", false):
		botiquines_auto_reanimar += 1

	if is_multiplayer_authority():
		hud.actualizar_suministros(suministros)
		hud.actualizar_municion(cargador_actual, municion_reserva)
		
		var texto_botin = "+$%d Suministros | +%d Balas" % [botin.get("suministros", 0), botin.get("municion", 0)]
		if botin.get("botiquin", false):
			texto_botin += " | ¡Botiquín encontrado!"

		hud.mostrar_regla(32, "Disfruta las pequeñas cosas", texto_botin)

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
