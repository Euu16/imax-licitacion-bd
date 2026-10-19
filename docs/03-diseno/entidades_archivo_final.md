# Identificación de Entidades y Atributos

**Proyecto:** Licitación para el Ecosistema Digital de Cines IMAX
**Fase:** 3, Diseño de la Base de Datos

Este documento identifica las entidades del sistema a partir de las reglas de negocio: para cada regla se determina qué información hay que guardar y en qué entidades. Los nombres de tablas y columnas son los mismos que se usan en `der.md`, donde se presentan el diagrama entidad-relación, las cardinalidades y las restricciones.

---

## 1. Criterios generales: para tomarlos como base y reglas a utilizar 


- **Cartelera no es una entidad.** Es una vista (consulta) que combina `funcion`, `pelicula`, `sala` y `cine`, filtrando funciones activas y futuras (RN-01).
- **Convención de nombres:** tablas en singular y `snake_case`. Las llaves foráneas se escriben `id_<tabla>`.
- **Fechas y horas:** siempre `timestamptz`, porque los cines están en distintos países.
- **Seguridad:** nunca se guarda el número de tarjeta ni el CVV; solo `token_pasarela` y los últimos 4 dígitos (RN-09). Las contraseñas se guardan como hash.
- **Dependencias:** una entidad dependiente lleva FK a la entidad de la que depende (función → película y sala, asiento → sala, boleto → orden).

---




## 2. De las reglas de negocio a las entidades

### 2.1 Catálogo y cartelera (RN-01, RN-02)

| Qué se necesita guardar | Entidades | Atributos |
|---|---|---|
| Detalle de cada película: título, sinopsis, clasificación de edad, duración, póster y si está activa | `pelicula` | `id_pelicula` [PK], `titulo`, `sinopsis`, `clasificacion_edad`, `duracion_minutos`, `poster_url`, `pelicula_esta_activa` |
| Género(s) de cada película. Una película puede tener varios, por eso no es una entidad simple | `genero`, `pelicula_genero` | `genero`: `id_genero` [PK], `nombre`. `pelicula_genero`: `id_pelicula` [PK, FK], `id_genero` [PK, FK] |
| Ubicación de los cines en el mundo (para filtrar por ubicación) | `cine` | `id_cine` [PK], `nombre`, `pais`, `ciudad`, `direccion` |
| Salas de cada cine | `sala` | `id_sala` [PK], `id_cine` [FK], `nombre_sala`, `capacidad_total`, `sala_esta_activa` |
| Programación: qué película se proyecta, en qué sala y cuándo | `funcion` | `id_funcion` [PK], `id_pelicula` [FK], `id_sala` [FK], `fecha_hora_inicio`, `fecha_hora_fin`, `estado_funcion` |

**Notas:**
- La ubicación exacta de la sala (RN-02) se obtiene por `sala → cine`, por lo que no se repite en `sala`.
- `fecha_hora_fin` permite evitar traslapes en una misma sala y calcular la ventana de tolerancia de RN-16.
- `estado_funcion` solo admite un valor a la vez: `programada`, `cancelada` o `finalizada` (restricción de constraint `CHECK`).
- 

### 2.2 Asientos y mapa de la sala (RN-03, RN-04, RN-05)

| Qué se necesita guardar | Entidades | Atributos |
|---|---|---|
| Zonas de la sala (platea, palco, VIP, general) | `zona` | `id_zona` [PK], `nombre` |
| Distribución física de cada sala: es decir los asientos | `asiento` | `id_asiento` [PK], `id_sala` [FK], `id_zona` [FK], `fila`, `numero`. Restricción `UNIQUE (id_sala, fila, numero)`, es decir que la combinacion de esos 3 atributos, no se puede repetir.|
| Estado de cada asiento en cada función, incluido el bloqueo temporal de 2 minutos | `estado_asiento_funcion` | `id_funcion` [PK, FK], `id_asiento` [PK, FK], `estado`, `id_usuario` [FK, nulo], `expiracion_bloqueo` (`timestamptz`, nulo) |

**Notas:**
- `estado_asiento_funcion.estado` admite `disponible`, `bloqueado` u `ocupado`. El estado "reservado" del enunciado corresponde a `bloqueado`: una reserva temporal mientras el usuario completa el pago.
- La PK compuesta `(id_funcion, id_asiento)` impide físicamente que un mismo asiento aparezca dos veces en una función.
- La fila se crea **bajo demanda**, cuando el asiento se bloquea por primera vez. La ausencia de fila equivale a "disponible".
- `expiracion_bloqueo` se fija en el momento del bloqueo más 2 minutos, e `id_usuario` identifica quién tiene el bloqueo.
- El límite de asientos por transacción (RN-04, máximo 6) no es una entidad: se valida en el procedimiento de reserva.

### 2.3 Tarifas y promociones (RN-06, RN-07, RN-08)

| Qué se necesita guardar | Entidades | Atributos |
|---|---|---|
| Tipos de entrada | `tipo_entrada` | `id_tipo_entrada` [PK], `nombre` (adulto, niño, tercera edad, estudiante), `requiere_credencial` |
| Precio según zona del asiento, tipo de entrada y día de la semana | `tarifa` | `id_tarifa` [PK], `id_zona` [FK], `id_tipo_entrada` [FK], `dia_semana` (0 a 6, nulo = todos los días), `precio_base` |
| Promociones y sus condiciones | `promocion` | `id_promocion` [PK], `nombre_promocion`, `tipo_regla` (2x1, descuento por día), `descuento_pct`, `condicion_minima`, `dia_semana`, `activa` |

**Notas:**

- Se va a crear un catálogo de franjas horarias al que apunta `tarifa`, esto permite que el horario de cada franja o "espacio" (es lo mismo) se defina una única vez y un cambio no va a obligar a modificar varias tarifas
- también debemos tomar en cuenta otro punto: el solapamiento. Con el catalogo de franjas, las mismas viven en una tabla pequeña y asi nunca hay solapamiento, pues se controla desde esa tabla. NOTA: EN NIVEL LOGICO LAS FRANJAS HORARIAS NO PUEDEN SOLAPARSE (podria usarse trigger)
- la franja de zona horaria se compara con la hora de inicio de la funcion específica
- para temas de duplicados: la regla que evita que 2 precios para la misma combinación de zona,tipo, dia y franja es una de UNIQUE
- existe otro problema. ahorita `dia_semana` significa todos los dias, por lo tanto debemos poner una regla NOT NULL y el "todos los dias se va a expresar con siete filas (una por dia), del 0 al 6
- en `promocion` cada promocion por dia tiene un solo `dia_semana`.Modelo se simplifica a una sola columna. Si descuento aplica para varios dias, se registra una promo por cada día.Pero la limitacion es que esas promos se repiten y se deben editar por separado
- orden.id_promocion sigue siendo opcional


- `tipo_entrada` es un catálogo con `UNIQUE` en `nombre`, de modo que solo existen los perfiles definidos.
- `promocion` **no lleva FK hacia `tarifa`**, porque el precio final se calcula combinando ambas. Lo que sí se guarda es qué promoción se aplicó en cada compra (campo `id_promocion` en `orden`).
- `requiere_credencial` indica si en la puerta hay que validar un documento de identidad o credencial (RN-06).

### 2.4 Usuarios, roles y permisos (RN-17)

| Qué se necesita guardar | Entidades | Atributos |
|---|---|---|
| Usuarios del sistema (clientes y personal) | `usuario` | `id_usuario` [PK], `id_rol` [FK], `nombre`, `correo` (`UNIQUE`), `telefono`, `contrasena_hash`, `activo`, `fecha_registro` |
| Roles | `rol` | `id_rol` [PK], `nombre_rol`, `descripcion` |
| Módulos del sistema | `modulo` | `id_modulo` [PK], `nombre` |
| Qué puede hacer cada rol en cada módulo (matriz de privilegio mínimo) | `rol_permiso` | `id_rol` [PK, FK], `id_modulo` [PK, FK], `nivel` (ninguno, lectura, ejecucion, escritura, total) |

**Nota:** los 5 roles son cliente, taquillero, operador de sala, contador y administrador/gerente. `rol_permiso` guarda la matriz del enunciado como datos, de modo que el RBAC pueda consultarse y demostrarse.

### 2.5 Compra y pago (RN-08, RN-09, RN-10)

| Qué se necesita guardar | Entidades | Atributos |
|---|---|---|
| Compra completa: quién, para qué función, montos y estado | `orden` | `id_orden` [PK] debe ser unica, pues un usuario va a realizar una orden a la ves (pero se debe verificar luego si se puede realizar otra orden en una nueva pestaña), `id_usuario` [FK], `id_funcion` [FK] debe ser unica, pues un usuario hace una orden para una sola funcion, `id_promocion` [FK, nulo], `canal` (web, app, taquilla), `estado_orden` (pendiente, pagada, fallida, anulada), `subtotal`, `descuento`, `cargo_servicio`, `total`, `fecha_creacion` |
| Intentos de pago y respuesta de la pasarela | `pago` | `id_pago` [PK], `id_orden` [FK], `id_metodo_pago` [FK], `estado_pago` (aprobado, rechazado, pendiente), `monto`, `token_pasarela`, `ultimos4`, `fecha_operacion` |
| Métodos de pago (para el reporte de métodos preferidos) | `metodo_pago` | `id_metodo_pago` [PK], `nombre` (tarjeta, PayPal, billetera, transferencia) |

**Notas:**
- (id_orden, id_funcion) deben ser unicas porque asi referencian ambas columnas juntas
- `orden` y `pago` están separadas porque una compra puede tener varios intentos de pago (uno rechazado y otro aprobado).
- `subtotal`, `descuento` y `total` se guardan como una fotografía financiera: no deben cambiar si luego cambia una tarifa.
- Si el pago es rechazado, la orden pasa a `fallida` y los asientos se liberan de inmediato (RN-10).



### 2.6 Emisión del boleto (RN-11, RN-12, RN-13)

| Qué se necesita guardar | Entidades | Atributos |
|---|---|---|
| Boleto digital único con su código QR, creado solo después de un pago aprobado | `boleto` | `id_boleto` [PK], `id_orden` [FK], `id_funcion` [FK], `id_asiento` [FK], `id_tipo_entrada` [FK], `precio_final`, `codigo_qr` (`UUID`, `UNIQUE`, `NOT NULL`), `estado_boleto` (emitido, usado, anulado), `origen` (online, taquilla, cortesia), `fecha_emision`, `fecha_uso` |

**Notas:**
-se debe realizar una FK compuesta que va en asiento_funcion : (id_funcion, id_asiento)
- Un boleto **no existe** hasta que el pago es aprobado. Por eso no hay estado "pendiente" ni boletos sin QR: la condición de RN-11 se cumple por construcción.
- `(id_funcion, id_asiento)` es una **FK compuesta** hacia `estado_asiento_funcion`: un boleto solo puede existir sobre un asiento que fue bloqueado antes por el flujo de compra.
- `id_tipo_entrada` permite validar la credencial en la puerta (RN-06), y `precio_final` conserva lo realmente cobrado.
- Como red de seguridad contra la doble venta, se agrega un índice único parcial: `UNIQUE (id_funcion, id_asiento) WHERE estado_boleto <> 'anulado'`.
- Un boleto anulado libera el asiento para una nueva venta.

**RESUMEN DE 2.5 y 2.6**
 - Una orden solo se relaciona con una sola función, por eso id_funcion se debe guardar en orden, pero tambien debe guardarse en boleto, porque así se referencia estado_aiento_funcion, y asi las fk compuestas obligan a que ambas coincidad.
- Se necesitan 2 fk compuestas, para verificar casos: la fk compuesta 1 (id_orden,id_funcion) revisa si existe una orden con tal funcion seleccionada y si coincide con lo del boleto, se acepta. La fk compuesta 2 dice que si existe un asiento en x funcion seleccionada dentro de estado_asiento_funcion y coincide con lo del boleto, pues se acepta.
- en el contexto que termina una función, lo que se hace es purgar los datos que se bloquearon y se abandonaron(que no tenian boleto), y ademas se mantiene FK compuesta 2, porque eso va a garantizar que todo boleto nace de que un usuario lo bloquea y se van a purgar solo filas(registros) de funciones finalizadas que no tienen boleto. No se puede hacer cascada porque borraría todo el historial de datos de venta (boletos vendidos), con los otros no hay problema porque no se generaron ventas ni afectaciones ahi
- los registros con su boleto se mantienen en la BD, y con las estimaciones realizadas en el der(que pueden ser aprox unos 15 millones de boletos al mes y 60 bytes por fila) lo cual puede ser como 1GB al mes, como 60 GB a 5 años.Es llevadero para lo dado en el contexto
- Tomemos en cuenta un caso límite: que pasa si un cliente obtiene un reembolso. En ese caso entonces vamos a purgar filas de funciones finalizadas sin ningún boleto (ni activo ni anulado).En este caso borra filas de estado_asiento_funcion y solo en funciones finalizadas que no tienen un boleto asociado; es decir que los asientos con boleto activo no se borra, los asientos con boleto anulado tampoco, y un asiento bloqueado(osea que el usuario lo reservó, pero nunca siguió con el pago) y abandonado si se purga.
-Básicamente los boletos no se borran para que sirvan como registros fiscales

**Problema 4 a resolver**
Se crea un catálogo de franjas horaria al que apunta tarifa, asi el horario de cada franja se define una sola vez y un cambio no obliga a modificar varias tarifas.


- También debemos registrar quien hizo la venta para un cliente, para eso vamos a crear una columna extra en `orden` como `vendedor_asociado` y de por medio en `usuario` haremos un usuario generico. Luego dejamos activo=verdadero y que el usuario genérico tenga un correo interno fijo y un contrasena_hash que ninguna contraseña produce, así no puede iniciar sesión

En eso tenemos una limitación, la cual es que un solo registro con un id_usuario se comparte por todos los clientes de mostrador. Luego hacemos un marcador en este modelo: agregar un sexto rol `cliente_administrador` en tabla `rol`, sin filas en `rol_permiso`, ese usuario genérico tiene ese rol y asi lo reconocemos

- un cliente recibe una entrada en el mostrador (para los genéricos), ya sea físico o solo con qr (pero ambos tienen ese codigo). RN-13 solo aplica a ventas online, y la venta de taquilla es una excepción declarada.Lo que la FK garantiza es que, si hay vendedor, exista como usuario. Se localiza boleto por `codigo_qr` y el reembolso se va a registrar con `id_usuario_autoriza`
- constraint obligatorio: si canal = 'taquilla', eso implica que vendedor_asociado no puede ser nulo, en otro caso se pone vacio. Regla: si canal es taquilla, vendedor_asociado es obligatorio; en los demás casos debe estar vacío

- `vendedor_asociado`: Es opcional porque las ventas online no tienen vendedor. La FK garantiza que, si hay vendedor, exista como usuario
- estado_asiento_funcion.id_usuario guarda al vendedor solo en ventas presenciales
- reembolso sigue aplicando. Sigue la regla de 2 horas (RN-19) y que quien tenga el QR puede solicitarlo
- Los reportes de clientes excluyen al usuario genérico

- pero deberiamos hacer un trigger para tabla `orden`, pues la fk solo comprueba q usuario exista, no su rol. Ese trigger se ejecuta aunque alguien inserte la orden sin pasar por procedimiento de venta.
- agregamos efectivo en `metodo_pego`. Ahi en ese caso `token_pasarela` y `ultimos4` en `pago` deben ser opcionales y ahi pago rechazado por pasarela no aplica 
-  `cliente_mostrador` no se puede asignar como rol a un usuario real porque solo puede existir un usuario con ese rol y ademas una orden con canal web o app no puede usar a ese usuario


### 2.7 Control de acceso en puerta (RN-14, RN-15, RN-16)

| Qué se necesita guardar | Entidades | Atributos |
|---|---|---|
| Dispositivos de escaneo (tótems y lectores) | `dispositivo_puerta` | `id_dispositivo` [PK], `id_sala` [FK], `nombre` |
| Cada intento de escaneo, aunque sea rechazado | `acceso_puerta_log` | `id_log` [PK], `fecha_hora` [PK, llave de partición], `id_boleto`, `id_dispositivo`, `resultado` (exitoso, duplicado, rechazado_horario, funcion_incorrecta, invalido), `motivo` |

### 2.8 Reembolsos (RN-19)

| Qué se necesita guardar | Entidades | Atributos |
|---|---|---|
| Devolución de dinero y anulación del boleto | `reembolso` | `id_reembolso` [PK], `id_boleto` [FK], `id_pago` [FK], `id_usuario_autoriza` [FK], `monto_reembolso`, `motivo`, `forzado`, `fecha_reembolso` |

**Nota:** la política de "hasta 2 horas antes de la función" se valida en el procedimiento de reembolso, no en una entidad. Si el reembolso es forzado, además se registra en `admin_operacion_audit`.

### 2.9 Auditoría a 5 años (RN-20)

El enunciado exige **cuatro tablas separadas**, con estos nombres, particionadas por fecha. No llevan FK físicas (son masivas y de solo inserción); guardan los identificadores como referencias lógicas.

| Tabla | Qué registra | Atributos |
|---|---|---|
| `transaccion_log` | Cada intento de pago, confirmación de pasarela, montos, impuestos y emisión de boletos | `id_log` [PK], `fecha_hora` [PK], `id_orden`, `id_pago`, `evento`, `monto`, `impuesto`, `moneda`, `ref_pasarela`, `detalle` (`jsonb`) |
| `asiento_auditoria_log` | Bloqueo, liberación por expiración o venta de un asiento | `id_log` [PK], `fecha_hora` [PK], `id_funcion`, `id_asiento`, `id_usuario`, `evento`, `expira_en` |
| `acceso_puerta_log` | Cada escaneo de QR (ver sección 2.7) | Ver sección 2.7 |
| `admin_operacion_audit` | Toda modificación manual de un administrador: cortesías, cambios de asiento, reembolsos forzados y cambios de configuración | `id_log` [PK], `fecha_hora` [PK], `id_usuario`, `id_rol`, `ip_origen`, `operacion`, `entidad`, `id_entidad`, `valor_anterior` (`jsonb`), `valor_nuevo` (`jsonb`) |

### 2.10 Restricción de salas con ventas activas (RN-18)

No requiere una entidad nueva. Se implementa con un **trigger** sobre `sala` y `asiento` que rechaza eliminar o modificar la distribución si existen boletos vendidos o reservas para funciones futuras de esa sala.

---

## 3. Cobertura de reglas de negocio

| Regla | Cubierta por |
|---|---|
| RN-01 | `funcion`, `pelicula` (vista de cartelera) |
| RN-02 | `pelicula`, `funcion`, `sala`, `cine` |
| RN-03 | `asiento`, `asiento_funcion` |
| RN-04 | Validación en el procedimiento de reserva |
| RN-05 | `asiento_funcion.expiracion_bloqueo` y `asiento_auditoria_log` |
| RN-06 | `tipo_entrada.requiere_credencial`, `boleto.id_tipo_entrada` |
| RN-07 | `promocion`, `orden.id_promocion` |
| RN-08 | `tarifa`, `orden` (subtotal, descuento, cargo, total) |
| RN-09 | `pago` (solo token y últimos 4 dígitos) |
| RN-10 | `pago.estado_pago`, `orden.estado_orden` |
| RN-11 | `boleto` solo se crea con pago aprobado |
| RN-12 | `boleto.codigo_qr` único |
| RN-13 | `boleto` consultado desde el perfil del usuario |
| RN-14 | `boleto.estado_boleto`, `acceso_puerta_log` |
| RN-15 | `acceso_puerta_log`, `funcion` |
| RN-16 | `funcion.fecha_hora_inicio` y ventana de tolerancia en el procedimiento de check-in |
| RN-17 | `rol`, `modulo`, `rol_permiso`, `usuario` |
| RN-18 | Trigger sobre `sala` y `asiento` |
| RN-19 | `reembolso` |
| RN-20 | Las 4 tablas de la sección 2.9 |

Todas las reglas de negocio (RN-01 a RN-20) quedan cubiertas.

---

## 4. Lista final de entidades

`cine`, `sala`, `zona`, `asiento`, `pelicula`, `genero`, `pelicula_genero`, `funcion`, `asiento_funcion`, `tipo_entrada`, `tarifa`, `promocion`, `rol`, `modulo`, `rol_permiso`, `usuario`, `metodo_pago`, `orden`, `pago`, `boleto`, `dispositivo_puerta`, `reembolso`, `transaccion_log`, `asiento_auditoria_log`, `acceso_puerta_log`, `admin_operacion_audit`.

Total: **26 tablas** (22 de negocio y 4 de auditoría).

---

## 5. Decisión de diseño: estado del asiento por función

El estado de cada asiento en cada función se modela con la tabla `asiento_funcion`, de PK compuesta `(id_funcion, id_asiento)`, creada bajo demanda.

| Criterio | Justificación |
|---|---|
| Unicidad anti doble venta | La PK compuesta impide físicamente dos filas para el mismo asiento en la misma función |
| Reserva atómica | Una única sentencia `INSERT ... ON CONFLICT DO UPDATE ... WHERE` concede el bloqueo a una sola solicitud; las demás obtienen 0 filas afectadas |
| Mapa de asientos | Una consulta sobre `asiento` con un `LEFT JOIN` a `asiento_funcion` para la función elegida |
| Volumen | Solo se almacenan los asientos bloqueados o vendidos (unos 20 millones de filas al mes), no todos los asientos de todas las funciones (unos 67 millones al mes) |
| Orden bloqueo → venta | `boleto` referencia a `asiento_funcion` con una FK compuesta |

La alternativa considerada fue modelar los bloqueos en una tabla `bloqueo_asiento` separada de `boleto`, con índices únicos parciales en ambas. Se descartó porque obliga a consultar y mantener dos tablas para conocer el estado de un asiento, y porque la unicidad se apoya en índices parciales en lugar de una llave primaria. El detalle de la sentencia de bloqueo está en `der.md`.


# Problemas identificados con diseño presentado

## 1.moneda y zona horaria
- como IMAX tiene varios cines en el mundo tenemos que generalizar la moneda para `precio_base`

Por ende, vamos a guardar la moneda en una tabla pais (por eso ocupamos timestamp)
- la zona horaria se guarda en `cine`, pues un pais puede tener varias zonas horarias y con la zona por cien, cada cine ubica hora local.
- la ciudad se mantiene como texto en `cine`
- La tarifa se relaciona a un país con un `id_pais`. Y aplica lo de temas de duplicados: la regla que evita que 2 precios para la misma combinación de zona,tipo, dia y franja es una de UNIQUE.

- el dinero de cada compra: `orden` va a guardar la moneda. `pago`,`boleto` y `reembolso` se basan en la moneda de su orden específica
- el dia y franja se calculan con hora local del cine se hace `fecha_hora_inicio`

DETALLES A TOMAR EN CUENTA: se usarán reportes por moneda
- ninguna FK impide que una funcion use tarifa de otro país. El procedimiento de compra válida que la tarifa pertenezca al país de la función, cruzando `funcion->sala->cine->pais`
- asumimos solo una moneda por pais (no se modelan paises con varias monedas). En el caso de `impuesto` en `transaccion_log `, su valor se registra por transacción.



# Otros pendientes 
#1: Parametros configurables. En las RN o casos de prueba vienen ejemplos aleatorios, pero IMAX puede desear otros. Se presenta una solucion para eso

Crear una tabla `configuracion` con una sola fila y una columna por parámetro
Sus columnas son: `bloqueo_minutos` (entre 1 y 15 mins, con propuesta de 2 mins),`max_asientos_en_orden` (entre 1 y 10),`tolerancia_antes_min` (entre 0 y 120),`tolerancia_despues_min` (entre 0 y 60), `reembolso_horas_antes` (entre 0 y 48), `cargo_servicio_porcentaje`(entre 0 y 100).
- cada columna tiene su tipo y su rango de validación. Cambiarlos no requierem modificar codigo y cada cambio ya queda auditado. Limitaciones: valores son globales, no por país y agregar un parámetro nuevo exige modificar la tabla.

#2: cortesías sin pago
se daría de la siguiente manera: Una orden con total 0 y estado de `pagada` sin ningun registro en `pago`
esto porque se sigue dando RN-11 que todo boleto nace de una orden con un pago aprobado. Y `boleto.id_orden` siue siendo obligatorio y la garantia de coherencia con llaves foranea compuestas propuestas. Además esta operacion queda auditada en `admin_operacion_audit`

|#punto	|Consecuencia	|Decisión propuesta|
|---    |---            |   -     -        |            

|1|	El catálogo metodo_pago necesita un valor nuevo|Agregar cortesia (además de efectivo)|
|2	pago.monto hoy probablemente exige un valor positivo	|Debe admitir 0, y el 0 solo vale si el método es cortesia|
||3	|No hay pasarela de por medio|	token_pasarela y ultimos4 ya son opcionales por el efectivo. RN-09 y RN-10 no aplican a este pago, igual que con el efectivo|
|4	|El reporte de “métodos de pago preferidos”	|Se calcula sin las cortesías, porque no es un método que elige el cliente. Anótalo, porque cambia el resultado de esa consulta|
|5	|Redundancia entre boleto.origen = cortesia y el método de pago|	Regla: si el origen es cortesia, el pago de su orden usa el método cortesia, y al revés|
|6	|orden.id_usuario es obligatorio	|Ver abajo|
|7	|canal solo admite web, app y taquilla|	Ver abajo|
|8	|RN-20	|Cada cortesía registra una fila en admin_operacion_audit con la operación cortesia y el id de la orden|
|9	|RN-04 (máximo 6 por orden)|	La cortesía también cuenta para el límite|
|10	|Quién puede otorgarla	|Solo Administrador/Gerente, según la matriz de roles|


#3: credencial en la puerta
- RN-06 dice que la validación “puede” hacerse físicamente en la puerta, y no exige dejar constancia de que se hizo. Por eso no se registra cada verificación exitosa. Sí se registra el rechazo, para tener trazabilidad de incidencias. El boleto solo se marca como usado cuando el ingreso se concede.
- en acceso_puerta_log.resultado se agrega rechazado_credencial, para dejar constancia de cuándo el guardia rechazó a alguien por no tener credencial.
- el boleto pasa a usado solo cuando el ingreso se concede. Si se rechaza por credencial, el boleto queda en emitido y el cliente puede volver con su documento.

#4: estado reservado
Se mantienen 3 estados y además "reservado" es equivalente a `bloqueado`. Estado azul se deduce en consulta del mapa.Los asientos fuera de servicio no se van a modelar
- lo que quiere decir eso es que quien bloquea un asiento se pone en color azul el asiento