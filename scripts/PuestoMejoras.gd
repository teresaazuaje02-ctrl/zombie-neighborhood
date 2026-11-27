extends StaticBody3D

# Puesto de Mejoras MK-II (Mesa de Trabajo / Workbench)
# Permite transformar armas y barricadas a sus variantes experimentales MK-II.
# El rol Carpintero cuenta con un 50% de descuento en mejoras de combate cuerpo a cuerpo y fortificaciones.

signal mejora_realizada(nombre_mejora: String, jugador: CharacterBody3D)

# Costes base estipulados en el Documento Maestro
const COSTE_BATE_MK2: int = 500
const COSTE_PISTOLA_MK2: int = 400
const COSTE_ESCOPETA_MK2: int = 800
const COSTE_RIFLE_MK2: int = 1000
const COSTE_BARRICADA_MK2: int = 350

@onready var cartel_3d: Label3D = $Cartel3D
@onready var luz_mesa: OmniLight3D = $LuzMesa

func _ready() -> void:
	pass

# Llamado por Jugador.gd al presionar 'E' mirando al puesto de mejoras
func interactuar(jugador: CharacterBody3D) -> void:
	if jugador.has_method("abrir_puesto_mejoras"):
		jugador.abrir_puesto_mejoras(self)

func obtener_coste(tipo_mejora: String, rol_jugador: int) -> int:
	var coste_base = 0
	match tipo_mejora:
		"bate_electrico":
			coste_base = COSTE_BATE_MK2
			if rol_jugador == 2: # Carpintero
				coste_base = int(coste_base * 0.5)
		"pistola_doble":
			coste_base = COSTE_PISTOLA_MK2
		"escopeta_dragon":
			coste_base = COSTE_ESCOPETA_MK2
		"rifle_segador":
			coste_base = COSTE_RIFLE_MK2
		"placas_hierro":
			coste_base = COSTE_BARRICADA_MK2
			if rol_jugador == 2: # Carpintero
				coste_base = int(coste_base * 0.5)
	return coste_base

func procesar_mejora(tipo_mejora: String, jugador: CharacterBody3D) -> bool:
	var coste = obtener_coste(tipo_mejora, jugador.rol)
	if jugador.suministros < coste:
		return false

	jugador.suministros -= coste
	jugador.actualizar_hud_suministros()
	jugador.aplicar_mejora_mk2(tipo_mejora)
	mejora_realizada.emit(tipo_mejora, jugador)
	return true
