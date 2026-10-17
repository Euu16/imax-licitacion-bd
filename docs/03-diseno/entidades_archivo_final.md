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
| Detalle de cada película: título, sinopsis, clasificación de edad, duración, póster y si está activa | `pelicula` | `id_pelicula` [PK], `titulo`, `sinopsis`, `clasificacion_edad`, `duracion_minutos`, `poster_url`, `esta_activa` |
| Género(s) de cada película. Una película puede tener varios, por eso no es un atributo simple | `genero`, `pelicula_genero` | `genero`: `id_genero` [PK], `nombre`. `pelicula_genero`: `id_pelicula` [PK, FK], `id_genero` [PK, FK] |
| Ubicación de los cines en el mundo (para filtrar por ubicación) | `cine` | `id_cine` [PK], `nombre`, `pais`, `ciudad`, `direccion` |
| Salas de cada cine | `sala` | `id_sala` [PK], `id_cine` [FK], `nombre_sala`, `capacidad_total`, `activa` |
| Programación: qué película se proyecta, en qué sala y cuándo | `funcion` | `id_funcion` [PK], `id_pelicula` [FK], `id_sala` [FK], `fecha_hora_inicio`, `fecha_hora_fin`, `estado_funcion` |

**Notas:**
- La ubicación exacta de la sala (RN-02) se obtiene por `sala → cine`, por lo que no se repite en `sala`.
- `fecha_hora_fin` permite evitar traslapes en una misma sala y calcular la ventana de tolerancia de RN-16.
- `estado_funcion` solo admite un valor a la vez: `programada`, `cancelada` o `finalizada` (restricción `CHECK`).

### 2.2 Asientos y mapa de la sala (RN-03, RN-04, RN-05)

| Qué se necesita guardar | Entidades | Atributos |
|---|---|---|
| Zonas de la sala (platea, palco, VIP, general) | `zona` | `id_zona` [PK], `nombre` |
| Distribución física de cada sala | `asiento` | `id_asiento` [PK], `id_sala` [FK], `id_zona` [FK], `fila`, `numero`. Restricción `UNIQUE (id_sala, fila, numero)` |
| Estado de cada asiento en cada función, incluido el bloqueo temporal de 2 minutos | `asiento_funcion` | `id_funcion` [PK, FK], `id_asiento` [PK, FK], `estado`, `id_usuario` [FK, nulo], `expiracion_bloqueo` (`timestamptz`, nulo) |

**Notas:**
- `asiento_funcion.estado` admite `disponible`, `bloqueado` u `ocupado`. El estado "reservado" del enunciado corresponde a `bloqueado`: una reserva temporal mientras el usuario completa el pago.
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
| Compra completa: quién, para qué función, montos y estado | `orden` | `id_orden` [PK], `id_usuario` [FK], `id_funcion` [FK], `id_promocion` [FK, nulo], `canal` (web, app, taquilla), `estado_orden` (pendiente, pagada, fallida, anulada), `subtotal`, `descuento`, `cargo_servicio`, `total`, `fecha_creacion` |
| Intentos de pago y respuesta de la pasarela | `pago` | `id_pago` [PK], `id_orden` [FK], `id_metodo_pago` [FK], `estado_pago` (aprobado, rechazado, pendiente), `monto`, `token_pasarela`, `ultimos4`, `fecha_operacion` |
| Métodos de pago (para el reporte de métodos preferidos) | `metodo_pago` | `id_metodo_pago` [PK], `nombre` (tarjeta, PayPal, billetera, transferencia) |

**Notas:**
- `orden` y `pago` están separadas porque una compra puede tener varios intentos de pago (uno rechazado y otro aprobado).
- `subtotal`, `descuento` y `total` se guardan como una fotografía financiera: no deben cambiar si luego cambia una tarifa.
- Si el pago es rechazado, la orden pasa a `fallida` y los asientos se liberan de inmediato (RN-10).

### 2.6 Emisión del boleto (RN-11, RN-12, RN-13)

| Qué se necesita guardar | Entidades | Atributos |
|---|---|---|
| Boleto digital único con su código QR, creado solo después de un pago aprobado | `boleto` | `id_boleto` [PK], `id_orden` [FK], `id_funcion` [FK], `id_asiento` [FK], `id_tipo_entrada` [FK], `precio_final`, `codigo_qr` (`UUID`, `UNIQUE`, `NOT NULL`), `estado_boleto` (emitido, usado, anulado), `origen` (online, taquilla, cortesia), `fecha_emision`, `fecha_uso` |

**Notas:**
- Un boleto **no existe** hasta que el pago es aprobado. Por eso no hay estado "pendiente" ni boletos sin QR: la condición de RN-11 se cumple por construcción.
- `(id_funcion, id_asiento)` es una **FK compuesta** hacia `asiento_funcion`: un boleto solo puede existir sobre un asiento que fue bloqueado antes por el flujo de compra.
- `id_tipo_entrada` permite validar la credencial en la puerta (RN-06), y `precio_final` conserva lo realmente cobrado.
- Como red de seguridad contra la doble venta, se agrega un índice único parcial: `UNIQUE (id_funcion, id_asiento) WHERE estado_boleto <> 'anulado'`.
- Un boleto anulado libera el asiento para una nueva venta.

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
