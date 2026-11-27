extends CanvasLayer

# Interfaz de Usuario Retro (Años 2000 / Estética PS2)
# Muestra vida, rol, munición, suministros, retícula, alertas y Menú de Compras.

signal compra_solicitada(articulo: String)
signal mejora_solicitada(tipo_mejora: String)

@onready var barra_vida: ProgressBar = $Margen/InferiorIzquierda/VBox/BarraVida
@onready var label_salud: Label = $Margen/InferiorIzquierda/VBox/BarraVida/LabelSalud
@onready var label_rol: Label = $Margen/InferiorIzquierda/VBox/LabelRol
@onready var panel_derribado: PanelContainer = $CentroAlerta/PanelDerribado

@onready var label_arma: Label = $Margen/InferiorDerecha/VBox/LabelArma
@onready var label_municion: Label = $Margen/InferiorDerecha/VBox/LabelMunicion
@onready var label_suministros: Label = $Margen/InferiorDerecha/VBox/LabelSuministros

@onready var label_interaccion: Label = $CentroAlerta/LabelInteraccion
@onready var banner_regla: PanelContainer = $SuperiorCentro/BannerRegla
@onready var titulo_regla: Label = $SuperiorCentro/BannerRegla/VBox/TituloRegla
@onready var desc_regla: Label = $SuperiorCentro/BannerRegla/VBox/DescRegla
@onready var timer_regla: Timer = $SuperiorCentro/BannerRegla/TimerRegla

# Menú de la Tienda
@onready var panel_tienda: PanelContainer = $MenuTienda
@onready var label_fondos_tienda: Label = $MenuTienda/VBox/FondosLabel

# Menú del Puesto de Mejoras MK-II
@onready var panel_mejoras: PanelContainer = $MenuMejoras
@onready var label_fondos_mejoras: Label = $MenuMejoras/VBox/FondosLabel

# Indicadores de Ronda y Oleada
@onready var label_ronda: Label = $Margen/SuperiorIzquierda/VBox/LabelRonda
@onready var label_zombis_restantes: Label = $Margen/SuperiorIzquierda/VBox/LabelZombisRestantes
@onready var label_tregua: Label = $Margen/SuperiorIzquierda/VBox/LabelTregua
@onready var banner_gran_ronda: PanelContainer = $CentroAlerta/BannerGranRonda
@onready var titulo_gran_ronda: Label = $CentroAlerta/BannerGranRonda/VBox/Titulo
@onready var subtitulo_gran_ronda: Label = $CentroAlerta/BannerGranRonda/VBox/Subtitulo
@onready var timer_gran_ronda: Timer = $CentroAlerta/BannerGranRonda/TimerGranRonda

var tienda_actual: Node = null
var puesto_mejoras_actual: Node = null

func _ready() -> void:
	panel_derribado.visible = false
	label_interaccion.visible = false
	banner_regla.visible = false
	if panel_tienda:
		panel_tienda.visible = false
	if panel_mejoras:
		panel_mejoras.visible = false
	if banner_gran_ronda:
		banner_gran_ronda.visible = false
	timer_regla.timeout.connect(_ocultar_banner_regla)
	if timer_gran_ronda:
		timer_gran_ronda.timeout.connect(_ocultar_banner_gran_ronda)

func actualizar_salud(actual: float, maxima: float) -> void:
	barra_vida.max_value = maxima
	barra_vida.value = actual
	label_salud.text = "%d / %d HP" % [int(actual), int(maxima)]
	
	if actual < maxima * 0.3:
		barra_vida.modulate = Color(0.9, 0.2, 0.2)
	elif actual < maxima * 0.6:
		barra_vida.modulate = Color(0.9, 0.8, 0.2)
	else:
		barra_vida.modulate = Color(0.2, 0.8, 0.3)

func configurar_rol(nombre_rol: String) -> void:
	label_rol.text = "ROL: " + nombre_rol.to_upper()

func actualizar_municion(cargador: int, reserva: int) -> void:
	if cargador < 0 or reserva < 0:
		label_municion.text = "CUERPO A CUERPO"
	else:
		label_municion.text = "%d / %d" % [cargador, reserva]

func actualizar_arma_nombre(nombre: String) -> void:
	label_arma.text = nombre.to_upper()

func actualizar_suministros(cantidad: int) -> void:
	label_suministros.text = "$ %d SUMINISTROS" % cantidad
	if label_fondos_tienda:
		label_fondos_tienda.text = "TUS SUMINISTROS DISPONIBLES: $ %d" % cantidad

func mostrar_estado_derribado(derribado: bool) -> void:
	panel_derribado.visible = derribado

func mostrar_prompt_interaccion(texto: String, visible_prompt: bool) -> void:
	label_interaccion.text = texto
	label_interaccion.visible = visible_prompt

func mostrar_regla(numero: int, nombre: String, descripcion: String) -> void:
	titulo_regla.text = "★ REGLA #%d: %s ★" % [numero, nombre.to_upper()]
	desc_regla.text = descripcion
	banner_regla.visible = true
	timer_regla.start(4.5)

func _ocultar_banner_regla() -> void:
	banner_regla.visible = false

# Funciones del Menú de Comercio
func abrir_tienda(tienda: Node, suministros: int) -> void:
	tienda_actual = tienda
	actualizar_suministros(suministros)
	panel_tienda.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func cerrar_tienda() -> void:
	panel_tienda.visible = false
	tienda_actual = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_comprar_escopeta_pressed() -> void:
	compra_solicitada.emit("escopeta")

func _on_comprar_rifle_pressed() -> void:
	compra_solicitada.emit("rifle")

func _on_comprar_botiquin_pressed() -> void:
	compra_solicitada.emit("botiquin")

func _on_comprar_municion_pressed() -> void:
	compra_solicitada.emit("municion")

func _on_cerrar_tienda_pressed() -> void:
	cerrar_tienda()

# Funciones del Menú de Mejoras MK-II
func abrir_puesto_mejoras(puesto: Node, suministros: int, rol_jugador: int, mejoras_activas: Dictionary) -> void:
	puesto_mejoras_actual = puesto
	actualizar_suministros(suministros)
	if label_fondos_mejoras:
		var bonus_carpintero = " (50% Desc. en Armas Melee y Barricadas por Carpintero)" if rol_jugador == 2 else ""
		label_fondos_mejoras.text = "TUS SUMINISTROS: $ %d%s" % [suministros, bonus_carpintero]
	panel_mejoras.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func cerrar_puesto_mejoras() -> void:
	panel_mejoras.visible = false
	puesto_mejoras_actual = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_mejorar_bate_pressed() -> void:
	mejora_solicitada.emit("bate_electrico")

func _on_mejorar_pistola_pressed() -> void:
	mejora_solicitada.emit("pistola_doble")

func _on_mejorar_escopeta_pressed() -> void:
	mejora_solicitada.emit("escopeta_dragon")

func _on_mejorar_rifle_pressed() -> void:
	mejora_solicitada.emit("rifle_segador")

func _on_mejorar_barricada_pressed() -> void:
	mejora_solicitada.emit("placas_hierro")

func _on_cerrar_mejoras_pressed() -> void:
	cerrar_puesto_mejoras()

# Funciones de Rondas y Oleadas
func mostrar_banner_ronda(num_ronda: int) -> void:
	if banner_gran_ronda and titulo_gran_ronda:
		titulo_gran_ronda.text = "★ RONDA %d ★" % num_ronda
		subtitulo_gran_ronda.text = "SOBREVIVE AL ATAQUE"
		banner_gran_ronda.visible = true
		if label_tregua:
			label_tregua.visible = false
		if timer_gran_ronda:
			timer_gran_ronda.start(3.5)

func mostrar_fin_ronda(num_ronda: int, bonif: int) -> void:
	if banner_gran_ronda and titulo_gran_ronda:
		titulo_gran_ronda.text = "★ RONDA %d SUPERADA ★" % num_ronda
		subtitulo_gran_ronda.text = "+$%d Suministros por sobrevivir" % bonif
		banner_gran_ronda.visible = true
		if timer_gran_ronda:
			timer_gran_ronda.start(3.5)

func _ocultar_banner_gran_ronda() -> void:
	if banner_gran_ronda:
		banner_gran_ronda.visible = false

func actualizar_contador_ronda(num_ronda: int, total_zombis: int) -> void:
	if label_ronda:
		label_ronda.text = "RONDA %d" % num_ronda
	if label_zombis_restantes:
		label_zombis_restantes.text = "INFECTADOS RESTANTES: %d" % total_zombis

func actualizar_contador_zombis_restantes(total: int) -> void:
	if label_zombis_restantes:
		label_zombis_restantes.text = "INFECTADOS RESTANTES: %d" % total

func actualizar_tiempo_tregua(segundos: int) -> void:
	if label_tregua:
		if segundos > 0:
			label_tregua.visible = true
			label_tregua.text = "TREGUA: %ds (Repara y compra)" % segundos
		else:
			label_tregua.visible = false
