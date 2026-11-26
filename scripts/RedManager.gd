extends Node

# Gestor de Red y Lobby para Cooperativo de 4 Jugadores
# Diseñado para Godot 4.x utilizando ENetMultiplayerPeer (LAN / IP Directa)
# Preparado para acoplarse posteriormente a GodotSteam sin modificar la lógica del juego.

signal jugador_conectado(id: int, info: Dictionary)
signal jugador_desconectado(id: int)
signal conexion_exitosa()
signal conexion_fallida()
signal servidor_cerrado()

const PUERTO_DEFECTO: int = 7000
const MAX_JUGADORES: int = 4

enum Rol {
	MEDICO,
	MILITAR,
	CARPINTERO,
	EXPLORADOR
}

# Diccionario de jugadores: { peer_id: { "nombre": String, "rol": Rol } }
var jugadores: Dictionary = {}
var mi_info: Dictionary = {
	"nombre": "Superviviente",
	"rol": Rol.MILITAR
}

var peer: ENetMultiplayerPeer

func _ready() -> void:
	multiplayer.peer_connected.connect(_al_conectar_peer)
	multiplayer.peer_disconnected.connect(_al_desconectar_peer)
	multiplayer.connected_to_server.connect(_al_conectar_exitoso)
	multiplayer.connection_failed.connect(_al_conectar_fallido)
	multiplayer.server_disconnected.connect(_al_desconectar_servidor)

# Iniciar partida como Host (Listen Server)
func crear_partida(puerto: int = PUERTO_DEFECTO) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(puerto, MAX_JUGADORES)
	if error != OK:
		push_error("Error al iniciar el servidor en el puerto: %d" % puerto)
		return error
	
	multiplayer.multiplayer_peer = peer
	jugadores[1] = mi_info
	jugador_conectado.emit(1, mi_info)
	print("Servidor iniciado como Host en puerto: ", puerto)
	return OK

# Unirse a una partida como Cliente
func unirse_a_partida(direccion_ip: String = "127.0.0.1", puerto: int = PUERTO_DEFECTO) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(direccion_ip, puerto)
	if error != OK:
		push_error("Error al conectar con el servidor: %s:%d" % [direccion_ip, puerto])
		return error
	
	multiplayer.multiplayer_peer = peer
	print("Conectando a %s:%d..." % [direccion_ip, puerto])
	return OK

func desconectar_red() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	jugadores.clear()

# Callbacks de señal de red
func _al_conectar_peer(id: int) -> void:
	print("Peer conectado a la red: ", id)

func _al_desconectar_peer(id: int) -> void:
	print("Peer desconectado: ", id)
	jugadores.erase(id)
	jugador_desconectado.emit(id)

func _al_conectar_exitoso() -> void:
	var mi_id = multiplayer.get_unique_id()
	print("Conexión establecida con éxito. Mi peer ID: ", mi_id)
	rpc_id(1, "registrar_jugador", mi_info)
	conexion_exitosa.emit()

func _al_conectar_fallido() -> void:
	push_warning("Fallo al conectar con el host.")
	multiplayer.multiplayer_peer = null
	conexion_fallida.emit()

func _al_desconectar_servidor() -> void:
	print("El servidor anfitrión ha cerrado la partida.")
	multiplayer.multiplayer_peer = null
	jugadores.clear()
	servidor_cerrado.emit()

# RPCs de registro e intercambio de información
@rpc("any_peer", "reliable")
func registrar_jugador(info: Dictionary) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	jugadores[sender_id] = info
	jugador_conectado.emit(sender_id, info)
	# Si somos el servidor, reenviamos la lista completa a todos los clientes
	if multiplayer.is_server():
		for id in jugadores.keys():
			rpc("actualizar_lista_jugadores", jugadores)

@rpc("authority", "reliable")
func actualizar_lista_jugadores(nueva_lista: Dictionary) -> void:
	jugadores = nueva_lista
	for id in jugadores.keys():
		jugador_conectado.emit(id, jugadores[id])
