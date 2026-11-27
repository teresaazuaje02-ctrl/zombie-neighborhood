extends Node3D

@onready var contenedor_jugadores: Node3D = $ContenedorJugadores
@onready var spawner_jugadores: MultiplayerSpawner = $MultiplayerSpawner
@onready var contenedor_zombis: Node3D = $ContenedorZombis
@onready var spawner_zombis: MultiplayerSpawner = $MultiplayerSpawnerZombis
@onready var menu_lobby: CanvasLayer = $MenuLobby
@onready var ip_input: LineEdit = $MenuLobby/Panel/VBoxContainer/HBoxContainer/IPInput
@onready var rol_selector: OptionButton = $MenuLobby/Panel/VBoxContainer/RolSelector
@onready var timer_oleadas: Timer = $TimerOleadas
@onready var barrio: Node3D = $Barrio
@onready var oleada_manager: Node = $OleadaManager

const ESCENA_JUGADOR = preload("res://escenas/jugadores/Jugador.tscn")
const ESCENA_ZOMBI = preload("res://escenas/enemigos/Zombi.tscn")

func _ready() -> void:
	rol_selector.clear()
	rol_selector.add_item("Médico (Soporte)", RedManager.Rol.MEDICO)
	rol_selector.add_item("Militar (Armas de fuego)", RedManager.Rol.MILITAR)
	rol_selector.add_item("Carpintero (Fortificaciones)", RedManager.Rol.CARPINTERO)
	rol_selector.add_item("Explorador (Movilidad y Saqueo)", RedManager.Rol.EXPLORADOR)
	rol_selector.select(1)

	RedManager.jugador_conectado.connect(_al_jugador_conectado)
	RedManager.jugador_desconectado.connect(_al_jugador_desconectado)

	oleada_manager.inicializar(contenedor_zombis, barrio)

func _on_host_pressed() -> void:
	RedManager.mi_info["rol"] = rol_selector.get_selected_id()
	var error = RedManager.crear_partida()
	if error == OK:
		menu_lobby.visible = false
		_instanciar_jugador(1)
		oleada_manager.iniciar_partida()

func _on_unirse_pressed() -> void:
	RedManager.mi_info["rol"] = rol_selector.get_selected_id()
	var ip = ip_input.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	var error = RedManager.unirse_a_partida(ip)
	if error == OK:
		menu_lobby.visible = false

func _al_jugador_conectado(peer_id: int, info: Dictionary) -> void:
	if multiplayer.is_server() and peer_id != 1:
		_instanciar_jugador(peer_id)

func _instanciar_jugador(peer_id: int) -> void:
	var nuevo_jugador = ESCENA_JUGADOR.instantiate()
	nuevo_jugador.name = str(peer_id)
	
	if barrio and barrio.has_method("obtener_spawn_jugador_aleatorio"):
		nuevo_jugador.position = barrio.obtener_spawn_jugador_aleatorio()
	else:
		nuevo_jugador.position = Vector3(0.0, 1.0, -55.0)

	if RedManager.jugadores.has(peer_id):
		nuevo_jugador.rol = RedManager.jugadores[peer_id].get("rol", RedManager.Rol.MILITAR)
	contenedor_jugadores.add_child(nuevo_jugador, true)

func _al_jugador_desconectado(peer_id: int) -> void:
	if multiplayer.is_server():
		var nodo = contenedor_jugadores.get_node_or_null(str(peer_id))
		if nodo:
			nodo.queue_free()

func _generar_oleada_barrio() -> void:
	if not multiplayer.is_server():
		return

	# Mantener una presencia activa de hasta 8 zombis simultáneos en el barrio
	if contenedor_zombis.get_child_count() < 8:
		var zombi = ESCENA_ZOMBI.instantiate()
		zombi.name = "Zombi_" + str(randi() % 100000)
		
		if barrio and barrio.has_method("obtener_spawn_zombi_aleatorio"):
			zombi.position = barrio.obtener_spawn_zombi_aleatorio()
		else:
			var angulo = randf() * TAU
			zombi.position = Vector3(cos(angulo) * 30.0, 0.5, sin(angulo) * 30.0)

		contenedor_zombis.add_child(zombi, true)
