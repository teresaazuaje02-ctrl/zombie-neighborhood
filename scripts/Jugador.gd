extends CharacterBody3D

# Controlador de Personaje (FPS) para el Escuadrón de Supervivientes
# Compatible con replicación multijugador nativa de Godot 4.

@export var velocidad_base: float = 4.5
@export var velocidad_sprint: float = 7.0
@export var fuerza_salto: float = 4.5
@export var sensibilidad_raton: float = 0.003

# Atributos de Supervivencia
@export var salud_maxima: float = 100.0
var salud_actual: float = 100.0
var esta_derribado: bool = false
var rol: int = 1 # Por defecto Militar (RedManager.Rol)

# Variables de rol / pasivas
var multiplicador_velocidad: float = 1.0
var multiplicador_recarga: float = 1.0
var multiplicador_reparacion: float = 1.0

@onready var cabeza: Node3D = $Cabeza
@onready var camara: Camera3D = $Cabeza/Camera3D
@onready var raycast_disparo: RayCast3D = $Cabeza/RayCastDisparo
@onready var sincronizador: MultiplayerSynchronizer = $MultiplayerSynchronizer

var gravedad: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _enter_tree() -> void:
	# El nombre del nodo coincide con el peer_id generado por MultiplayerSpawner
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	salud_actual = salud_maxima
	aplicar_bonificaciones_rol()

	if is_multiplayer_authority():
		camara.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		camara.current = false

func aplicar_bonificaciones_rol() -> void:
	match rol:
		0: # MEDICO
			multiplicador_reparacion = 1.0
		1: # MILITAR
			multiplicador_recarga = 0.6 # -40% tiempo recarga
		2: # CARPINTERO
			multiplicador_reparacion = 2.0 # Doble velocidad / doble tablón
		3: # EXPLORADOR
			multiplicador_velocidad = 1.15 # +15% velocidad

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
		# En estado derribado el movimiento es mínimo
		velocity.x = move_toward(velocity.x, 0.0, 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 5.0 * delta)
		move_and_slide()
		return

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

@rpc("authority", "call_local")
func sincronizar_derribo(derribado: bool) -> void:
	esta_derribado = derribado
	print("Estado de derribo de %s actualizado a: %s" % [name, derribado])
