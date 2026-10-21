# Diseño Conceptual de la Base de Datos

**Proyecto:** Licitación para el Ecosistema Digital de Cines IMAX
**Fase:** 3, Diseño de la Base de Datos (nivel conceptual)

El diseño conceptual describe **qué información maneja el negocio y cómo se relaciona**, sin comprometerse con tipos de dato, llaves ni tablas físicas. Por eso aquí las relaciones de muchos a muchos aparecen tal como son en el negocio. El diseño lógico (`der.md`) las convierte en tablas con llaves, y el físico (`01_schema.sql`) las implementa en PostgreSQL.


---

## 1. Detalles antes de diagrama conceptual
Antes de generar esta parte, se deben tomar en cuenta algunos detalles como

|Detalle|Explicación|
|  ---  |   ---     |
|Cardinalidad entre usuario y orden| 1:N, pues un usuario puede tener varias ordenes, pero cada orden pertenece a un usuario|
|Ventas presenciales en taquilla (cuando cliente no tiene cuenta) y relación de vendedor|Recordar que ventas presenciales en taquilla o cortesías cuando un cliente no tiene cuenta, se utilizará un usuario genérico con un rol de mostrador, mantienendo que id_usuario no será nulo. Además, la relación del vendedor se ajusta exclusivamente a quien reigstra venta de mostrador o cortesía|
|`franja horaria` como entidad propia| en cuanto a tarifa, no es solo una N:M directa, sino que esta misma depende de la zona,tipo de entrada, dia de la semana, franja horaria y el país. Lo brindado permite evitar solapamientos y que hayan parámetros globales por moneda y región|
|Unificación de nombres| se unifican nombres en documentación conceptual y lógica utilizando `estado_asiento_funcion` y columna `vendedor_asociado` para evitar confusiones de nombres viejos|
|LLaves foráneas compuestas en entidad `boleto`| en este archivo se deja en claro que boleto tiene 2 validaciones o dependencias claves: a- (id_orden,id_funcion) que asegura coherencia con la compra, b-(id_funcion,id_asiento)  para referenciarse directamente del inventario en `estado_asiento_funcion` (de manera lógica, el boleto nace y se verifica sonre un asiento que fue bloqueado para una función específica)|
|caso de entidad `ciudad`| Esta entidad existe y se relaciona con la entidad `pais` para evitar repetir texto de ubicación y normalizar correctamente jerarquía geográfica junto a `cine`|
|Inclusión de entidades Huérfanas/Parámetros| con entidades huerfanas en este caso se refier y e a que basicamente estas dependen de info de ellas relacionada con otras tablas. En este caso se agregan entidades `franja_horaria` y `configuracion`.La primera ya fue explicada, mientras que la segunda sirve para configurar distintos parámetros como minutos de bloqueo,limites de asiento, tolerancias, limites para reembolsos, etc|
|Reembolso con Boleto Opcional| aqui se deja claro que un reembolso no debe tener una relación obligatoria con el boleto,pues pueden haber casos especiales de pagos aprobados y demás|
|Regla para Asiento y la Sala| se usa como regla de validación un trigger o procedimiento almacenado lo siguiente: 
un asiento seleccionado en una función específica debe pertenecer obligatoriamente a la sala en la cuál se va a programar la función.|

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
|`zona`||
|`asiento`||
|`dispositivo_puerta`||
|`pelicula`||
|`genero`||
|`funcion`||
|``||
|``||
|``||
|``||
|``||
|``||
|``||
|``||
|``||
|``||
|``||
|``||
|``||
|``||
|``||
|``||
|``||

