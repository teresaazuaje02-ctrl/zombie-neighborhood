extends Node3D

@onready var contenedor_jugadores: Node3D = $ContenedorJugadores
@onready var spawner_jugadores: MultiplayerSpawner = $MultiplayerSpawner
@onready var menu_lobby: CanvasLayer = $MenuLobby
@onready var ip_input: LineEdit = $MenuLobby/Panel/VBoxContainer/HBoxContainer/IPInput
@onready var rol_selector: OptionButton = $MenuLobby/Panel/VBoxContainer/RolSelector

const ESCENA_JUGADOR = preload("res://escenas/jugadores/Jugador.tscn")

func _ready() -> void:
	# Configurar opciones de roles
	rol_selector.clear()
	rol_selector.add_item("Médico (Soporte)", RedManager.Rol.MEDICO)
	rol_selector.add_item("Militar (Armas de fuego)", RedManager.Rol.MILITAR)
	rol_selector.add_item("Carpintero (Fortificaciones)", RedManager.Rol.CARPINTERO)
	rol_selector.add_item("Explorador (Movilidad y Saqueo)", RedManager.Rol.EXPLORADOR)
	rol_selector.select(1) # Militar por defecto

	RedManager.jugador_conectado.connect(_al_jugador_conectado)
	RedManager.jugador_desconectado.connect(_al_jugador_desconectado)

func _on_host_pressed() -> void:
	RedManager.mi_info["rol"] = rol_selector.get_selected_id()
	var error = RedManager.crear_partida()
	if error == OK:
		menu_lobby.visible = false
		_instanciar_jugador(1)

func _on_unirse_pressed() -> void:
	RedManager.mi_info["rol"] = rol_selector.get_selected_id()
	var ip = ip_input.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	var error = RedManager.unirse_a_partida(ip)
	if error == OK:
		menu_lobby.visible = false

func _al_jugador_conectado(peer_id: int, info: Dictionary) -> void:
	# El anfitrión se encarga de instanciar a los nuevos participantes
	if multiplayer.is_server() and peer_id != 1:
		_instanciar_jugador(peer_id)

func _instanciar_jugador(peer_id: int) -> void:
	var nuevo_jugador = ESCENA_JUGADOR.instantiate()
	nuevo_jugador.name = str(peer_id)
	nuevo_jugador.position = Vector3(randf_range(-2.0, 2.0), 1.0, randf_range(-2.0, 2.0))
	if RedManager.jugadores.has(peer_id):
		nuevo_jugador.rol = RedManager.jugadores[peer_id].get("rol", RedManager.Rol.MILITAR)
	contenedor_jugadores.add_child(nuevo_jugador, true)

func _al_jugador_desconectado(peer_id: int) -> void:
	if multiplayer.is_server():
		var nodo = contenedor_jugadores.get_node_or_null(str(peer_id))
		if nodo:
			nodo.queue_free()
