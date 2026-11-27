extends StaticBody3D

# Contenedor de Saqueo (Neveras, Cajas, Armarios)
# Permite a los jugadores saquear suministros y munición con la tecla E.
# Aplica las pasivas del Explorador (+35% suministros) y del Médico (+probabilidad botiquín).

signal saqueado_por(jugador: Node, botin: Dictionary)

enum TipoContenedor {
	CAJA_SUMINISTROS,
	NEVERA,
	ARMARIO
}

@export var tipo: TipoContenedor = TipoContenedor.CAJA_SUMINISTROS
@export var suministros_base_min: int = 40
@export var suministros_base_max: int = 120
@export var municion_base_min: int = 10
@export var municion_base_max: int = 30

var ya_saqueado: bool = false

@onready var sincronizador: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var malla_tapa: Node3D = $MallaTapa
@onready var malla_base: MeshInstance3D = $MallaBase
@onready var cartel: Label3D = get_node_or_null("Cartel3D")

func _ready() -> void:
	actualizar_visual()

# Llamado por Jugador.gd al pulsar 'E'
func saquear(jugador: CharacterBody3D) -> bool:
	if ya_saqueado:
		return false

	rpc("sincronizar_saqueo", jugador.get_path())
	return true

@rpc("any_peer", "call_local")
func sincronizar_saqueo(ruta_jugador: NodePath) -> void:
	if ya_saqueado:
		return

	ya_saqueado = true
	actualizar_visual()

	var jugador = get_node_or_null(ruta_jugador)
	if jugador:
		var es_explorador = (jugador.get("rol") == 3) # Rol.EXPLORADOR
		var es_medico = (jugador.get("rol") == 0)     # Rol.MEDICO

		# Cálculo de suministros con pasiva del Explorador (+35%)
		var suministros_ganados = randi_range(suministros_base_min, suministros_base_max)
		if es_explorador:
			suministros_ganados = int(suministros_ganados * 1.35)

		# Munición obtenida
		var municion_ganada = randi_range(municion_base_min, municion_base_max)

		# Probabilidad de botiquín de auto-reanimamiento (Médico 25%, otros 10%)
		var prob_botiquin = 0.25 if es_medico else 0.10
		var encontro_botiquin = (randf() <= prob_botiquin)

		var botin = {
			"suministros": suministros_ganados,
			"municion": municion_ganada,
			"botiquin": encontro_botiquin
		}

		if jugador.has_method("recibir_botin"):
			jugador.recibir_botin(botin)

		saqueado_por.emit(jugador, botin)

func actualizar_visual() -> void:
	if cartel:
		cartel.visible = not ya_saqueado
	if malla_tapa:
		if ya_saqueado:
			# Abrir la tapa visualmente (rotación de 75 grados)
			malla_tapa.rotation_degrees.x = -75.0
		else:
			malla_tapa.rotation_degrees.x = 0.0
