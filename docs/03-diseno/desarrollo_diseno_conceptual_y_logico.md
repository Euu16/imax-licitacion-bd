# Diseño Conceptual de la Base de Datos

**Proyecto:** Licitación para el Ecosistema Digital de Cines IMAX en todo el mundo
**Fase:** 3, Diseño de la Base de Datos (nivel conceptual)

El diseño conceptual describe **qué información maneja el negocio y cómo se relaciona**, sin comprometerse con tipos de dato, llaves ni tablas físicas. Por eso aquí las relaciones de muchos a muchos aparecen tal como son en el negocio. El diseño lógico (`der.md`) las convierte en tablas con llaves, y el físico (`01_schema.sql`) las implementa en PostgreSQL.


---

## 1. Detalles antes de diagrama conceptual
Antes de generar esta parte, se deben tomar en cuenta algunos detalles como

|Detalle|Explicación|
|  ---  |   ---     |
|Cardinalidad entre usuario y orden|1:N. Un usuario puede tener varias órdenes, pero cada orden pertenece a un solo usuario cliente|
|Ventas de taquilla y cortesías|Cuando el cliente no tiene cuenta (taquilla o cortesía) se usa un usuario genérico con el rol `cliente_mostrador`, de modo que `id_usuario` nunca es nulo. La relación de vendedor (`vendedor_asociado`) registra quién hizo la venta de taquilla o quién otorgó la cortesía|
|`franja_horaria` como entidad propia|La tarifa no es solo una N:M entre zona y tipo de entrada: depende del país, la zona, el tipo de entrada, el día de la semana y la franja horaria. La franja es un catálogo, así el horario de cada franja se define una sola vez|
|Unificación de nombres|Se usa `estado_asiento_funcion` (no `asiento_funcion`) y `vendedor_asociado` (no `id_usuario_vendedor`) en todos los documentos|
|Llaves foráneas compuestas en `boleto`|Son dos: (a) `(id_orden, id_funcion)` hacia `orden`, que asegura que el boleto sea de la función de su compra; (b) `(id_funcion, id_asiento)` hacia `estado_asiento_funcion`, que asegura que el asiento fue bloqueado antes en esa función|
|`ciudad` como entidad|Se relaciona con `pais` y con `cine`. Evita repetir texto de ubicación y separa ciudades con el mismo nombre en países distintos|
|`franja_horaria` y `configuracion`|`franja_horaria` es un catálogo del que depende `tarifa`. `configuracion` es la única entidad sin relaciones: guarda los parámetros globales del sistema|
|Reembolso con boleto opcional|Un pago aprobado puede llegar después de que expiró el bloqueo y el asiento ya se vendió a otro. Hay que devolver el dinero, pero no existe boleto|
|Regla entre asiento y sala|Un asiento seleccionado en una función debe pertenecer a la sala donde se proyecta esa función. Lo valida un trigger o procedimiento almacenado|

## 2.Resumen de entidades del proyecto

|Contexto| Entidades seleccionadas|
|  ---   |          ---           |
|Ubicación y estructura| `pais`,`ciudad`,`cine`,`sala`,`zona`,`asiento`,`dispositivo_puerta`,`configuracion` |
|cartelera y programacion| `pelicula`,`genero`,`pelicula_genero`,`funcion`,`franja_horaria`|
|precios y promociones| `tipo_entrada`,`tarifa`,`promocion`|
|privacidad, seguridad y labores(accesos)|`rol`,`modulo`,`rol_permiso`,`usuario`|
|transacciones y ventas| `orden`,`pago`,`metodo_pago`,`boleto`,`reembolso`|
|Bitácoras para auditoria|`transaccion_log`,`asiento_auditoria_log`,`acceso_puerta_log`,`admin_operacion_audit`|

## 3.Diagrama Entidad-Relación
**3.1: Diagrama de 26 tablas de negocio**
erDiagram
    rol ||--o{ usuario : "tiene"
    rol ||--o{ rol_permiso : "recibe"
    modulo ||--o{ rol_permiso : "se asigna en"

    pais ||--o{ ciudad : "tiene"
    ciudad ||--o{ cine : "aloja"
    cine ||--o{ sala : "contiene"
    sala ||--o{ asiento : "tiene"
    zona ||--o{ asiento : "clasifica"
    sala ||--o{ dispositivo_puerta : "tiene"

    pelicula ||--o{ pelicula_genero : "pertenece"
    genero ||--o{ pelicula_genero : "agrupa"
    pelicula ||--o{ funcion : "se proyecta en"
    sala ||--o{ funcion : "aloja"

    pais ||--o{ tarifa : "define moneda y precio"
    zona ||--o{ tarifa : "define precio"
    tipo_entrada ||--o{ tarifa : "define precio"
    franja_horaria ||--o{ tarifa : "define precio"

    usuario ||--o{ orden : "compra"
    usuario |o--o{ orden : "vende en taquilla"
    funcion ||--o{ orden : "es comprada en"
    promocion |o--o{ orden : "se aplica a"
    orden ||--o{ pago : "se paga con"
    metodo_pago ||--o{ pago : "usa"

    funcion ||--o{ estado_asiento_funcion : "tiene estado de"
    asiento ||--o{ estado_asiento_funcion : "tiene estado en"
    usuario |o--o{ estado_asiento_funcion : "bloquea"

    orden ||--o{ boleto : "genera"
    estado_asiento_funcion ||--o{ boleto : "se vende como"
    tipo_entrada ||--o{ boleto : "clasifica"

    pago ||--o{ reembolso : "devuelve"
    boleto |o--o{ reembolso : "origina"
    usuario |o--o{ reembolso : "autoriza"

    rol {
        smallint id_rol PK
        varchar nombre_rol UK
        varchar descripcion
    }
    modulo {
        smallint id_modulo PK
        varchar nombre UK
    }
    rol_permiso {
        smallint id_rol PK, FK
        smallint id_modulo PK, FK
        varchar nivel "ninguno, lectura, ejecucion, escritura, total"
    }
    usuario {
        bigint id_usuario PK
        smallint id_rol FK
        varchar nombre
        varchar correo UK
        varchar telefono
        varchar contrasena_hash
        boolean activo
        timestamptz fecha_registro
    }
    pais {
        smallint id_pais PK
        varchar nombre UK
        varchar moneda
    }
    ciudad {
        int id_ciudad PK
        smallint id_pais FK
        varchar nombre
    }
    cine {
        int id_cine PK
        int id_ciudad FK
        varchar nombre
        varchar direccion
        varchar zona_horaria
    }
    sala {
        int id_sala PK
        int id_cine FK
        varchar nombre_sala
        int capacidad_total
        boolean sala_esta_activa
    }
    zona {
        smallint id_zona PK
        varchar nombre UK "platea, palco, VIP, general"
    }
    asiento {
        int id_asiento PK
        int id_sala FK
        smallint id_zona FK
        varchar fila
        smallint numero
    }
    dispositivo_puerta {
        int id_dispositivo PK
        int id_sala FK
        varchar nombre
    }
    genero {
        smallint id_genero PK
        varchar nombre UK
    }
    pelicula {
        int id_pelicula PK
        varchar titulo
        text sinopsis
        varchar clasificacion_edad
        smallint duracion_minutos
        varchar poster_url
        boolean pelicula_esta_activa
    }
    pelicula_genero {
        int id_pelicula PK, FK
        smallint id_genero PK, FK
    }
    funcion {
        bigint id_funcion PK
        int id_pelicula FK
        int id_sala FK
        timestamptz fecha_hora_inicio
        timestamptz fecha_hora_fin
        varchar estado_funcion "programada, cancelada, finalizada"
    }
    franja_horaria {
        smallint id_franja PK
        varchar nombre
        time hora_inicio
        time hora_fin
    }
    tipo_entrada {
        smallint id_tipo_entrada PK
        varchar nombre UK "adulto, nino, tercera_edad, estudiante"
        boolean requiere_credencial
    }
    tarifa {
        int id_tarifa PK
        smallint id_pais FK
        smallint id_zona FK
        smallint id_tipo_entrada FK
        smallint id_franja FK
        smallint dia_semana "0 a 6, obligatorio"
        numeric precio_base
    }
    promocion {
        int id_promocion PK
        varchar nombre_promocion
        varchar tipo_regla "2x1, descuento_dia"
        numeric descuento_pct
        int condicion_minima
        smallint dia_semana "obligatorio si descuento_dia; vacio si 2x1"
        boolean activa
    }
    metodo_pago {
        smallint id_metodo_pago PK
        varchar nombre UK "tarjeta, paypal, billetera, transferencia, efectivo, cortesia"
    }
    orden {
        bigint id_orden PK
        bigint id_usuario FK "cliente; obligatorio"
        bigint vendedor_asociado FK "taquilla o administrativo; opcional"
        bigint id_funcion FK
        int id_promocion FK
        varchar canal "web, app, taquilla, administrativo"
        varchar estado_orden "pendiente, pagada, fallida, anulada"
        numeric subtotal
        numeric descuento
        numeric cargo_servicio
        numeric total
        varchar moneda
        timestamptz fecha_creacion
    }
    pago {
        bigint id_pago PK
        bigint id_orden FK
        smallint id_metodo_pago FK
        varchar estado_pago "pendiente, aprobado, rechazado"
        numeric monto
        varchar token_pasarela "nulo con efectivo y cortesia"
        char ultimos4 "nulo con efectivo y cortesia"
        timestamptz fecha_operacion
    }
    estado_asiento_funcion {
        bigint id_funcion PK, FK
        int id_asiento PK, FK
        varchar estado "disponible, bloqueado, ocupado"
        bigint id_usuario FK "quien bloquea; nulo si disponible"
        timestamptz expiracion_bloqueo "nulo si no esta bloqueado"
    }
    boleto {
        bigint id_boleto PK
        bigint id_orden FK "FK compuesta (id_orden, id_funcion)"
        bigint id_funcion FK "FK compuesta a estado_asiento_funcion"
        int id_asiento FK "FK compuesta a estado_asiento_funcion"
        smallint id_tipo_entrada FK
        numeric precio_final
        uuid codigo_qr UK
        varchar estado_boleto "emitido, usado, anulado"
        varchar origen "online, taquilla, cortesia"
        timestamptz fecha_emision
        timestamptz fecha_uso
    }
    reembolso {
        bigint id_reembolso PK
        bigint id_pago FK
        bigint id_boleto FK "nulo si el pago fue tardio"
        bigint id_usuario_autoriza FK
        numeric monto_reembolso
        varchar motivo
        boolean forzado
        timestamptz fecha_reembolso
    }
    configuracion {
        smallint id_configuracion PK
        smallint bloqueo_minutos
        smallint max_asientos_en_orden
        smallint tolerancia_antes_min
        smallint tolerancia_despues_min
        smallint reembolso_horas_antes
        numeric cargo_servicio_porcentaje
    }

**3.2: Diagrama de 4 tablas de auditoría**
- Recordar que estas no tienen FK fisicas.Solo guardan identificadores como referencias lógicas.
erDiagram
    transaccion_log {
        bigint id_log PK
        timestamptz fecha_hora PK "llave de particion"
        bigint id_orden
        bigint id_pago
        varchar evento "intento, confirmacion, emision, rechazo"
        numeric monto
        numeric impuesto
        varchar moneda
        varchar ref_pasarela
        jsonb detalle
    }
    asiento_auditoria_log {
        bigint id_log PK
        timestamptz fecha_hora PK "llave de particion"
        bigint id_funcion
        int id_asiento
        bigint id_usuario
        varchar evento "bloqueo, expiracion, liberacion, venta"
        timestamptz expira_en
    }
    acceso_puerta_log {
        bigint id_log PK
        timestamptz fecha_hora PK "llave de particion"
        bigint id_boleto
        int id_dispositivo
        varchar resultado "exitoso, duplicado, rechazado_horario, rechazado_credencial, funcion_incorrecta, invalido"
        varchar motivo
    }
    admin_operacion_audit {
        bigint id_log PK
        timestamptz fecha_hora PK "llave de particion"
        bigint id_usuario
        smallint id_rol
        inet ip_origen
        varchar operacion "cortesia, cambio_asiento, reembolso_forzado, config"
        varchar entidad
        bigint id_entidad
        jsonb valor_anterior
        jsonb valor_nuevo
    }

## 4.Entidades
|Entidad|Descripción|
| ---   |    ---    |
|`pais`, `ciudad`| Ubicación geográfica de cines. Recordar que cada cine pertenece a una ciduad|
|`cine`|sucursal IMAX ubicada en una ciudad específica|
|`sala`|Sala de proyección de un cine|
|`zona`|puede ser plate,palco,VIP o general (para el asiento)|
|`asiento`|asiento físico de una sala (tiene fila, numero y zona)|
|`dispositivo_puerta`|lector de qr en la entrada de sala|
|`configuracion`|relacionado a parametros como moneda y demas (parámetros globales sistema)|
|`pelicula`|catálogo de películas. tiene titulo,sinopsis,clasificación, duración y póster|
|`genero`|género de la película|
|`pelicula_genero`|relacion N:M entre película y genero|
|`funcion`|incluye pelicula,sala,hora de inicio, hora de fin y estado|
|`franja_horaria`|catálogo de horarios|
|`tipo_entrada`|especifica si es para niño,tercera edad,adulto,etc|
|`tarifa`|precio base basado en función del país,zona y demas detalles|
|`promocion`|promocion aplicable como descuentos,2x1.|
|`rol`|rol en el sistema de un usuario(cliente, taquillero,operador,contador,cliente_mostrador,administrador)|
|`modulo`|modulo funcional del sistema|
|`rol_permiso`|matriz de privilegios de cada rol sobre el módulo|
|`usuario`|usuario del sistema|
|`orden`|compra. Tiene su cliente,funcion,montos,canal y puede tener vendedor asociado|
|`pago`|intento de pago de una orden; con token y últimos 4 dígitos|
|`metodo_pago`|tarjeta,efectivo,cortesía,PayPal,etc|
|`boleto`|boleto digital emitido tras pago aprobado. Tiene un QR único|
|`reembolso`|para devolver dinero|
|`estado_asiento_funcion`|si esta ocupado, disponible o bloqueado|
|`transaccion_log`|auditoría de pagos, confirmaciones y emisión de boletos|
|`asiento_auditoria_log`|auditoría de bloqueos,liberaciones y ventas de asientos|
|`acceso_puerta_log`|registro de cada escaneo de QR en puerta|
|`admin_operacion_audit`|auditoria de operaciones manuales del administrador|


## 5. Relaciones y cardinalidades
|Relación|Cardinalidad|Comentario|
| ---    |   ---      |   ---    |
|pais → ciudad|1 : N| |
|ciudad → cine|1 : N| |
|cine → sala|1 : N| |
|sala → asiento|1 : N|El mapa de asientos de una sala|
|zona → asiento|1 : N|Platea, palco, VIP, general|
|sala → dispositivo_puerta|1 : N| |
|rol → usuario|1 : N|Un usuario tiene un solo rol|
|rol ↔ modulo|N : M (vía rol_permiso)|Matriz de privilegio mínimo|
|pelicula ↔ genero|N : M (vía pelicula_genero)| |
|pelicula → funcion|1 : N| |
|sala → funcion|1 : N|Sin traslapes|
|pais, zona, tipo_entrada, franja_horaria → tarifa|1 : N cada una|Una tarifa combina las cuatro, con día de la semana y precio|
|funcion ↔ asiento|N : M (vía estado_asiento_funcion)|Estado de cada asiento en cada función|
|usuario → estado_asiento_funcion|0..1 : N|Quién tiene el bloqueo|
|usuario → orden (cliente)|1 : N|Obligatorio; en taquilla se usa `cliente_mostrador`|
|usuario → orden (vendedor)|0..1 : N|Solo canal taquilla o administrativo|
|funcion → orden|1 : N| |
|promocion → orden|0..1 : N|Una orden puede no tener promoción|
|orden → pago|1 : N|Varios intentos de pago posibles|
|metodo_pago → pago|1 : N| |
|orden → boleto|1 : N|De uno a seis|
|estado_asiento_funcion → boleto|1 : 0..1 vigente|A lo sumo un boleto no anulado|
|tipo_entrada → boleto|1 : N| |
|pago → reembolso|1 : N| |
|boleto → reembolso|0..1 : N|Sin boleto cuando el pago llegó tarde|
|usuario → reembolso (autoriza)|0..1 : N|Sin usuario si la devolución es automática|