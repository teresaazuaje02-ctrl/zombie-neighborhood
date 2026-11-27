extends CharacterBody3D

# Controlador de Personaje (FPS) para el Escuadrón de Supervivientes
# Compatible con replicación multijugador nativa de Godot 4.
# Incluye soporte para modelos 3D de armas, retroceso, sistema de compra en TiendaNPC y saqueo.

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
var tienda_actual: Node = null
var puesto_mejoras_actual: Node = null
var mejoras_desbloqueadas: Dictionary = {
	"bate_electrico": false,
	"pistola_doble": false,
	"escopeta_dragon": false,
	"rifle_segador": false,
	"placas_hierro": false
}

# Timers de disparo
var puede_disparar: bool = true
var cadencia_disparo: float = 0.25

# Referencias de Nodos
@onready var cabeza: Node3D = $Cabeza
@onready var camara: Camera3D = $Cabeza/Camera3D
@onready var raycast_disparo: RayCast3D = $Cabeza/RayCastDisparo
@onready var sincronizador: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var hud: CanvasLayer = $HUD
@onready var malla_propia: MeshInstance3D = $MallaPlaceholder

# Socket de Armas en Primera Persona
@onready var socket_arma: Node3D = $Cabeza/Camera3D/SocketArma
@onready var malla_pistola: Node3D = $Cabeza/Camera3D/SocketArma/Pistola9mm
@onready var malla_bate: Node3D = $Cabeza/Camera3D/SocketArma/BateClavos
@onready var fogonazo: OmniLight3D = $Cabeza/Camera3D/SocketArma/Fogonazo

var posicion_original_arma: Vector3 = Vector3(0.22, -0.18, -0.38)
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
		if malla_propia:
			malla_propia.visible = false
		hud.visible = true
		socket_arma.visible = true
		actualizar_modelo_arma_visible()
		hud.actualizar_salud(salud_actual, salud_maxima)
		hud.actualizar_municion(cargador_actual, municion_reserva)
		hud.actualizar_suministros(suministros)
		hud.configurar_rol(_obtener_nombre_rol())
		hud.mostrar_regla(1, "Cardio", "Mantén el ritmo al correr; los infectados no se cansan.")
		hud.compra_solicitada.connect(_al_procesar_compra)
		hud.mejora_solicitada.connect(_al_procesar_mejora)
	else:
		camara.current = false
		hud.visible = false
		socket_arma.visible = false
		if malla_propia:
			malla_propia.visible = true

func actualizar_modelo_arma_visible() -> void:
	if rol == 1:
		malla_pistola.visible = true
		malla_bate.visible = false
	else:
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
		0:
			multiplicador_reparacion = 1.0
			danio_arma_inicial = 35.0
			cargador_maximo = 15
			botiquines_auto_reanimar = 1
		1:
			multiplicador_recarga = 0.6
			danio_arma_inicial = 28.0
			cargador_maximo = int(15 * 1.35)
			cargador_actual = cargador_maximo
		2:
			multiplicador_reparacion = 2.0
			danio_arma_inicial = 35.0
		3:
			multiplicador_velocidad = 1.15
			danio_arma_inicial = 35.0

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * sensibilidad_raton)
		cabeza.rotate_x(-event.relative.y * sensibilidad_raton)
		cabeza.rotation.x = clamp(cabeza.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
		
		socket_arma.position.x = posicion_original_arma.x - (event.relative.x * 0.0003)
		socket_arma.position.y = posicion_original_arma.y + (event.relative.y * 0.0003)

	if event.is_action_pressed("ui_cancel"):
		if hud and hud.panel_tienda and hud.panel_tienda.visible:
			hud.cerrar_tienda()
			return

		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity.y -= gravedad * delta

	socket_arma.position = socket_arma.position.lerp(posicion_original_arma + retroceso_actual, 12.0 * delta)
	retroceso_actual = retroceso_actual.lerp(Vector3.ZERO, 15.0 * delta)

	if esta_derribado:
		if Input.is_action_just_pressed("saltar"):
			rpc("sincronizar_auto_reanimacion")
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
		if col:
			if col.has_method("intentar_reparar") and col.tablones_actuales < 4:
				hud.mostrar_prompt_interaccion("[E] Reparar Barricada", true)
				return
			elif col.has_method("saquear") and not col.ya_saqueado:
				hud.mostrar_prompt_interaccion("[E] Saquear Contenedor", true)
				return
			elif col.has_method("interactuar"):
				var txt = "[E] Comerciar en la Tienda" if col.get("esta_liberada") else "[E] Hablar con el Tendero"
				hud.mostrar_prompt_interaccion(txt, true)
				return
	hud.mostrar_prompt_interaccion("", false)

func ejecutar_disparo() -> void:
	if rol == 1 and cargador_actual <= 0:
		ejecutar_recarga()
		return

	puede_disparar = false

	if rol == 1:
		cargador_actual -= 1
		hud.actualizar_municion(cargador_actual, municion_reserva)
		retroceso_actual = Vector3(0.0, 0.03, 0.08)
		activar_fogonazo()
	else:
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
			elif objeto.has_method("interactuar"):
				objeto.interactuar(self)

func recibir_botin(botin: Dictionary) -> void:
	suministros += botin.get("suministros", 0)
	municion_reserva += botin.get("municion", 0)
	
	if botin.get("botiquin", false):
		botiquines_auto_reanimar += 1

	actualizar_hud_suministros()
	
	var texto_botin = "+$%d Suministros | +%d Balas" % [botin.get("suministros", 0), botin.get("municion", 0)]
	if botin.get("botiquin", false):
		texto_botin += " | ¡Botiquín encontrado!"

	hud.mostrar_regla(32, "Disfruta las pequeñas cosas", texto_botin)

func actualizar_hud_suministros() -> void:
	if is_multiplayer_authority():
		hud.actualizar_suministros(suministros)
		hud.actualizar_municion(cargador_actual, municion_reserva)

# Sistema de Comercio
func abrir_tienda(tienda_ref: Node) -> void:
	tienda_actual = tienda_ref
	if is_multiplayer_authority():
		hud.abrir_tienda(tienda_ref, suministros)

func _al_procesar_compra(articulo: String) -> void:
	if not tienda_actual:
		return

	var exito: bool = false
	match articulo:
		"escopeta":
			exito = tienda_actual.intentar_comprar_escopeta(self)
		"rifle":
			exito = tienda_actual.intentar_comprar_rifle(self)
		"botiquin":
			exito = tienda_actual.intentar_comprar_botiquin(self)
		"municion":
			exito = tienda_actual.intentar_comprar_municion(self)

	if exito:
		actualizar_hud_suministros()
		hud.mostrar_regla(2, "Doble Tiro", "¡Nueva arma / suministro adquirido en la tienda!")

func equipar_arma_comprada(nombre: String, danio: float, cargador: int, reserva: int) -> void:
	danio_arma_inicial = danio
	cargador_maximo = cargador
	cargador_actual = cargador
	municion_reserva += reserva
	rol = 1 # Pasa a empuñar arma de fuego
	actualizar_modelo_arma_visible()
	
	if is_multiplayer_authority():
		hud.actualizar_arma_nombre(nombre)
		hud.actualizar_municion(cargador_actual, municion_reserva)
		hud.actualizar_suministros(suministros)

# Sistema de Puesto de Mejoras MK-II
func abrir_puesto_mejoras(puesto_ref: Node) -> void:
	puesto_mejoras_actual = puesto_ref
	if is_multiplayer_authority():
		hud.abrir_puesto_mejoras(puesto_ref, suministros, rol, mejoras_desbloqueadas)

func _al_procesar_mejora(tipo_mejora: String) -> void:
	if not puesto_mejoras_actual:
		return
	
	if mejoras_desbloqueadas.get(tipo_mejora, false):
		if is_multiplayer_authority():
			hud.mostrar_regla(31, "Revisa el asiento trasero", "¡Ya tienes instalada esta mejora MK-II!")
		return

	var exito = puesto_mejoras_actual.procesar_mejora(tipo_mejora, self)
	if exito:
		mejoras_desbloqueadas[tipo_mejora] = true
		actualizar_hud_suministros()
		hud.mostrar_regla(2, "Doble Tiro", "¡Mejora experimental MK-II ensamblada con éxito!")

func aplicar_mejora_mk2(tipo_mejora: String) -> void:
	match tipo_mejora:
		"bate_electrico":
			danio_arma_inicial = 85.0
			if is_multiplayer_authority():
				hud.actualizar_arma_nombre("Bate Eléctrico MK-II")
		"pistola_doble":
			danio_arma_inicial = 38.0
			cargador_maximo = 20
			cargador_actual = 20
			cadencia_disparo = 0.18
			if is_multiplayer_authority():
				hud.actualizar_arma_nombre("Pistola Doble Acción MK-II")
				hud.actualizar_municion(cargador_actual, municion_reserva)
		"escopeta_dragon":
			danio_arma_inicial = 140.0
			if is_multiplayer_authority():
				hud.actualizar_arma_nombre("Aliento de Dragón MK-II")
		"rifle_segador":
			danio_arma_inicial = 60.0
			cargador_maximo = 40
			cargador_actual = 40
			if is_multiplayer_authority():
				hud.actualizar_arma_nombre("Rifle Segador MK-II")
				hud.actualizar_municion(cargador_actual, municion_reserva)
		"placas_hierro":
			multiplicador_reparacion *= 1.5
			if is_multiplayer_authority():
				hud.mostrar_regla(17, "No seas un héroe", "Tus fortificaciones ahora están reforzadas con placas de hierro.")

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

@rpc("any_peer", "call_local")
func sincronizar_auto_reanimacion() -> void:
	salud_actual = 50.0
	esta_derribado = false
	if is_multiplayer_authority():
		hud.actualizar_salud(salud_actual, salud_maxima)
		hud.mostrar_estado_derribado(false)
