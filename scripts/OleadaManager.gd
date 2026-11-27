extends Node

# Administrador de Rondas y Oleadas de Zombis (Estilo CoD Zombies / Left 4 Dead)
# Controla el flujo de rondas, spawn progresivo, dificultad escalonada, treguas y recompensas.
# Es autoritario en el Servidor/Host y sincroniza estados y contadores en todos los clientes.

signal ronda_iniciada(numero_ronda: int, total_zombis: int)
signal ronda_completada(numero_ronda: int, bonificacion: int)
signal tregua_actualizada(segundos_restantes: int)
signal zombis_actualizados(vivos: int, por_generar: int)

enum EstadoOleada {
	DESCANSO,
	EN_CURSO,
	FIN_PARTIDA
}

@export var ronda_actual: int = 0
@export var estado: EstadoOleada = EstadoOleada.DESCANSO
@export var duracion_descanso: float = 20.0
@export var max_zombis_simultaneos: int = 20

var zombis_totales_ronda: int = 0
var zombis_por_generar: int = 0
var zombis_vivos: int = 0
var tiempo_restante_descanso: float = 0.0
var timer_spawn_acumulado: float = 0.0
var cadencia_spawn_actual: float = 2.0

const ESCENA_ZOMBI = preload("res://escenas/enemigos/Zombi.tscn")

var contenedor_zombis: Node3D = null
var barrio_ref: Node3D = null

func _ready() -> void:
	pass

func inicializar(contenedor: Node3D, barrio: Node3D) -> void:
	contenedor_zombis = contenedor
	barrio_ref = barrio

func iniciar_partida() -> void:
	if not multiplayer.is_server():
		return
	
	ronda_actual = 0
	iniciar_cuenta_regresiva_descanso(5.0) # 5 segundos de gracia al empezar

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	match estado:
		EstadoOleada.DESCANSO:
			tiempo_restante_descanso -= delta
			var segundos_int = int(ceil(tiempo_restante_descanso))
			rpc("sincronizar_tregua", segundos_int)

			if tiempo_restante_descanso <= 0.0:
				comenzar_siguiente_ronda()

		EstadoOleada.EN_CURSO:
			# Generar zombis de forma dosificada si hay cupo y quedan por spawnear
			if zombis_por_generar > 0 and zombis_vivos < max_zombis_simultaneos:
				timer_spawn_acumulado += delta
				if timer_spawn_acumulado >= cadencia_spawn_actual:
					timer_spawn_acumulado = 0.0
					_generar_zombi_individual()

func comenzar_siguiente_ronda() -> void:
	ronda_actual += 1
	estado = EstadoOleada.EN_CURSO

	# Fórmula de zombis: Base + escalado por ronda + bonus por jugadores conectados
	var num_jugadores = max(1, RedManager.jugadores.size())
	zombis_totales_ronda = int(6 + (ronda_actual * 3.5) + (num_jugadores * 2))
	zombis_por_generar = zombis_totales_ronda
	zombis_vivos = 0
	timer_spawn_acumulado = 0.0

	# Ajustar cadencia según ronda (más rápido en rondas altas)
	cadencia_spawn_actual = max(0.8, 2.5 - (ronda_actual * 0.12))

	rpc("sincronizar_inicio_ronda", ronda_actual, zombis_totales_ronda)
	print("¡Comenzando Ronda ", ronda_actual, "! Total de infectados: ", zombis_totales_ronda)

func _generar_zombi_individual() -> void:
	if not contenedor_zombis or zombis_por_generar <= 0:
		return

	var nuevo_zombi = ESCENA_ZOMBI.instantiate()
	nuevo_zombi.name = "Zombi_R%d_%d" % [ronda_actual, zombis_totales_ronda - zombis_por_generar + 1]

	# Determinar arquetipo según la ronda
	# Ronda 4+: 20% Corredores. Ronda 7+: 15% Brutos.
	if ronda_actual >= 7 and randf() < 0.15:
		nuevo_zombi.tipo = nuevo_zombi.TipoZombi.BRUTO
	elif ronda_actual >= 4 and randf() < 0.25:
		nuevo_zombi.tipo = nuevo_zombi.TipoZombi.CORREDOR
	else:
		nuevo_zombi.tipo = nuevo_zombi.TipoZombi.COMUN

	# Asignar posición de spawn aleatoria en el vecindario
	if barrio_ref and barrio_ref.has_method("obtener_spawn_zombi_aleatorio"):
		nuevo_zombi.position = barrio_ref.obtener_spawn_zombi_aleatorio()
	else:
		var angulo = randf() * TAU
		nuevo_zombi.position = Vector3(cos(angulo) * 35.0, 0.5, sin(angulo) * 35.0)

	contenedor_zombis.add_child(nuevo_zombi, true)
	zombis_por_generar -= 1
	zombis_vivos += 1

	rpc("sincronizar_conteo", zombis_vivos, zombis_por_generar)

func registrar_baja_zombi() -> void:
	if not multiplayer.is_server():
		return

	zombis_vivos = max(0, zombis_vivos - 1)
	rpc("sincronizar_conteo", zombis_vivos, zombis_por_generar)

	# Revisar si se completó la ronda
	if zombis_por_generar <= 0 and zombis_vivos <= 0 and estado == EstadoOleada.EN_CURSO:
		_finalizar_ronda_actual()

func _finalizar_ronda_actual() -> void:
	estado = EstadoOleada.DESCANSO
	var bonificacion = 100 + (ronda_actual * 35)

	# Otorgar suministros a todos los jugadores supervivientes
	var jugadores = get_tree().get_nodes_in_group("jugadores")
	for j in jugadores:
		if is_instance_valid(j):
			j.suministros += bonificacion
			j.actualizar_hud_suministros()

	rpc("sincronizar_fin_ronda", ronda_actual, bonificacion)
	iniciar_cuenta_regresiva_descanso(duracion_descanso)

func iniciar_cuenta_regresiva_descanso(tiempo: float) -> void:
	tiempo_restante_descanso = tiempo
	estado = EstadoOleada.DESCANSO

# RPCs de sincronización para todos los peers
@rpc("authority", "call_local")
func sincronizar_inicio_ronda(num_ronda: int, total_z: int) -> void:
	ronda_actual = num_ronda
	estado = EstadoOleada.EN_CURSO
	ronda_iniciada.emit(num_ronda, total_z)

	var jugadores = get_tree().get_nodes_in_group("jugadores")
	for j in jugadores:
		if is_instance_valid(j) and j.has_node("HUD"):
			var hud = j.get_node("HUD")
			hud.mostrar_banner_ronda(num_ronda)
			hud.actualizar_contador_ronda(num_ronda, total_z)

@rpc("authority", "call_local")
func sincronizar_fin_ronda(num_ronda: int, bonif: int) -> void:
	estado = EstadoOleada.DESCANSO
	ronda_completada.emit(num_ronda, bonif)

	var jugadores = get_tree().get_nodes_in_group("jugadores")
	for j in jugadores:
		if is_instance_valid(j) and j.has_node("HUD"):
			var hud = j.get_node("HUD")
			hud.mostrar_fin_ronda(num_ronda, bonif)

@rpc("authority", "call_local")
func sincronizar_tregua(segundos: int) -> void:
	tregua_actualizada.emit(segundos)
	var jugadores = get_tree().get_nodes_in_group("jugadores")
	for j in jugadores:
		if is_instance_valid(j) and j.has_node("HUD"):
			var hud = j.get_node("HUD")
			hud.actualizar_tiempo_tregua(segundos)

@rpc("authority", "call_local")
func sincronizar_conteo(vivos: int, por_gen: int) -> void:
	zombis_actualizados.emit(vivos, por_gen)
	var total_restantes = vivos + por_gen
	var jugadores = get_tree().get_nodes_in_group("jugadores")
	for j in jugadores:
		if is_instance_valid(j) and j.has_node("HUD"):
			var hud = j.get_node("HUD")
			hud.actualizar_contador_zombis_restantes(total_restantes)
