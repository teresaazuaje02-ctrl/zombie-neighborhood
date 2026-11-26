extends StaticBody3D

# Sistema de Barricadas Dinámicas (1 a 4 Tablones)
# Controla la colisión contra enemigos y la fortificación por interacción.

signal barricada_reparada(tablones: int)
signal barricada_destruida()

const MAX_TABLONES: int = 4

@export var tablones_actuales: int = 4:
	set(valor):
		tablones_actuales = clamp(valor, 0, MAX_TABLONES)
		actualizar_visuales()

@onready var bloqueo_colision: CollisionShape3D = $BloqueoZombis
@onready var tablones_visuales: Array[Node3D] = [
	$Tablon1,
	$Tablon2,
	$Tablon3,
	$Tablon4
]

func _ready() -> void:
	actualizar_visuales()

func actualizar_visuales() -> void:
	for i in range(MAX_TABLONES):
		if i < tablones_visuales.size() and tablones_visuales[i]:
			tablones_visuales[i].visible = (i < tablones_actuales)
	
	if bloqueo_colision:
		# Se desactiva la colisión física si no quedan tablones
		bloqueo_colision.disabled = (tablones_actuales == 0)

# Interacción del jugador (pulsar 'E')
func intentar_reparar(es_carpintero: bool) -> bool:
	if tablones_actuales >= MAX_TABLONES:
		return false

	var incremento = 2 if es_carpintero else 1
	rpc("sincronizar_reparacion", incremento)
	return true

# Daño recibido por zombis
func zombi_atacar_barricada(es_bruto: bool = false) -> void:
	if not multiplayer.is_server():
		return

	if tablones_actuales <= 0:
		return

	var reduccion = MAX_TABLONES if es_bruto else 1
	rpc("sincronizar_dano", reduccion)

@rpc("any_peer", "call_local")
func sincronizar_reparacion(cantidad: int) -> void:
	tablones_actuales += cantidad
	barricada_reparada.emit(tablones_actuales)

@rpc("any_peer", "call_local")
func sincronizar_dano(cantidad: int) -> void:
	tablones_actuales -= cantidad
	if tablones_actuales == 0:
		barricada_destruida.emit()
