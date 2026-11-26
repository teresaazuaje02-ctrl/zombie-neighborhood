extends Node3D

# Controlador del Vecindario (Barrio de 4 a 6 Cuadras)
# Gestiona zonas del mapa, iluminación de farolas retro y puntos de aparición de hordas.

@export var nombre_zona: String = "Distrito Costero (Verano 2002)"
@export var tienda_liberada: bool = false

# Puntos de referencia y rutas
@onready var spawns_jugadores: Node3D = $PuntosSpawn/Jugadores
@onready var spawns_zombis: Node3D = $PuntosSpawn/Zombis
@onready var zona_tienda_npc: Node3D = $PuntosInteres/TiendaNPC
@onready var zona_extraccion: Node3D = $PuntosInteres/ZonaExtraccion

func _ready() -> void:
	print("Inicializado mapa del vecindario: ", nombre_zona)

func obtener_spawn_jugador_aleatorio() -> Vector3:
	var puntos = spawns_jugadores.get_children()
	if puntos.size() > 0:
		var elegido = puntos[randi() % puntos.size()]
		return elegido.global_position
	return Vector3.ZERO

func obtener_spawn_zombi_aleatorio() -> Vector3:
	var puntos = spawns_zombis.get_children()
	if puntos.size() > 0:
		var elegido = puntos[randi() % puntos.size()]
		return elegido.global_position
	return Vector3(randf_range(-20.0, 20.0), 0.5, randf_range(-20.0, 20.0))
