extends StaticBody3D

# Tienda del NPC (El Tendero del Barrio)
# Administra la misión de liberación y el catálogo de compras para el escuadrón.

signal tienda_desbloqueada()

@export var esta_liberada: bool = false
@export var zombis_necesarios_limpiar: int = 3
var zombis_eliminados_tienda: int = 0

# Precios estipulados en el Documento Maestro
const PRECIO_ESCOPETA: int = 600
const PRECIO_RIFLE: int = 900
const PRECIO_BOTIQUIN: int = 400
const PRECIO_MUNICION: int = 150

@onready var sincronizador: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var cartel_cerrado: Label3D = $CartelCerrado
@onready var cartel_abierto: Label3D = $CartelAbierto
@onready var zona_interaccion: Area3D = $ZonaInteraccion
@onready var modelo_npc: Node3D = $ModeloTendero

func _ready() -> void:
	actualizar_estado_visual()

func actualizar_estado_visual() -> void:
	if cartel_cerrado and cartel_abierto:
		cartel_cerrado.visible = not esta_liberada
		cartel_abierto.visible = esta_liberada

# Llamado por Jugador.gd al pulsar 'E' mirando al NPC o al mostrador
func interactuar(jugador: CharacterBody3D) -> void:
	if not esta_liberada:
		# Mensaje icónico del documento maestro estilo Zombieland
		if jugador.has_node("HUD"):
			var hud = jugador.get_node("HUD")
			hud.mostrar_regla(1, "Cardio", "¡Limpia los zombis de mi tienda antes de pedir descuentos!")
	else:
		# Abrir menú de compras en el HUD del jugador
		if jugador.has_method("abrir_tienda"):
			jugador.abrir_tienda(self)

# Registrar muerte de un zombi en la zona de la tienda
func registrar_baja_zombi() -> void:
	if esta_liberada:
		return

	zombis_eliminados_tienda += 1
	if zombis_eliminados_tienda >= zombis_necesarios_limpiar:
		rpc("sincronizar_liberacion_tienda")

@rpc("any_peer", "call_local")
func sincronizar_liberacion_tienda() -> void:
	esta_liberada = true
	actualizar_estado_visual()
	tienda_desbloqueada.emit()
	print("¡La tienda del Tendero ha sido liberada permanentemente!")

# Funciones de transacción económica
func intentar_comprar_escopeta(jugador: CharacterBody3D) -> bool:
	if jugador.suministros >= PRECIO_ESCOPETA:
		jugador.suministros -= PRECIO_ESCOPETA
		jugador.equipar_arma_comprada("Escopeta Corredera", 90.0, 8, 32)
		return true
	return false

func intentar_comprar_rifle(jugador: CharacterBody3D) -> bool:
	if jugador.suministros >= PRECIO_RIFLE:
		jugador.suministros -= PRECIO_RIFLE
		jugador.equipar_arma_comprada("Rifle de Asalto", 42.0, 30, 90)
		return true
	return false

func intentar_comprar_botiquin(jugador: CharacterBody3D) -> bool:
	if jugador.suministros >= PRECIO_BOTIQUIN:
		jugador.suministros -= PRECIO_BOTIQUIN
		jugador.botiquines_auto_reanimar += 1
		jugador.actualizar_hud_suministros()
		return true
	return false

func intentar_comprar_municion(jugador: CharacterBody3D) -> bool:
	if jugador.suministros >= PRECIO_MUNICION:
		jugador.suministros -= PRECIO_MUNICION
		jugador.municion_reserva += 60
		jugador.actualizar_hud_suministros()
		return true
	return false
