extends CanvasLayer

# Interfaz de Usuario Retro (Años 2000 / Estética PS2)
# Muestra vida, rol, munición, suministros, retícula, alertas y Menú de Compras.

signal compra_solicitada(articulo: String)

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

var tienda_actual: Node = null

func _ready() -> void:
	panel_derribado.visible = false
	label_interaccion.visible = false
	banner_regla.visible = false
	if panel_tienda:
		panel_tienda.visible = false
	timer_regla.timeout.connect(_ocultar_banner_regla)

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
