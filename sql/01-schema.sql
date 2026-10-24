



DROP SCHEMA IF EXISTS desarrollo CASCADE;
CREATE SCHEMA desarrollo;



CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE pais(
    id_pais SERIAL PRIMARY KEY,
    nombre VARCHAR(110) NOT NULL,
    moneda VARCHAR(15) NOT NULL
);

CREATE TABLE rol(
    id_rol SERIAL PRIMARY KEY,
    nombre_rol VARCHAR(50) NOT NULL,
    descripcion VARCHAR(150) NOT NULL
);
CREATE TABLE modulo(
    id_modulo SERIAL PRIMARY KEY,
    nombre_modulo VARCHAR(150) NOT NULL
);
CREATE TABLE metodo_pago(
    id_metodo_pago SERIAL PRIMARY KEY,
    nombre_metodo_pago VARCHAR(45)
    --ya sea paypal, efectivo,etc
);
CREATE TABLE configuracion(
    id_configuracion INT PRIMARY KEY DEFAULT 1,
    -- se cambia tipo de dato a int, y empezando en 1 porque sino hay problemas en inserts fallidos
    bloqueo_minutos INT NOT NULL CHECK(bloqueo_minutos BETWEEN 1 AND 15),
    max_asientos_en_orden INT NOT NULL CHECK(max_asientos_en_orden BETWEEN 1 AND 10),
    tolerancia_antes_min INT NOT NULL CHECK(tolerancia_antes_min BETWEEN 0 AND 120),
    tolerancia_despues_min INT NOT NULL CHECK(tolerancia_despues_min BETWEEN 0 AND 60),
    reembolso_horas_antes INT NOT NULL CHECK(reembolso_horas_antes BETWEEN 0 AND 48),
    cargo_servicio_porcentaje NUMERIC(5,2) NOT NULL CHECK(cargo_servicio_porcentaje BETWEEN 0 AND 100),
    CONSTRAINT check_fila_unica CHECK(id_configuracion=1)
    --solo una fila en configuracion
);
CREATE TABLE genero(
    id_genero SERIAL PRIMARY KEY,
    nombre_genero VARCHAR(50) NOT NULL UNIQUE

);
CREATE TABLE franja_horaria(
    id_franja SERIAL PRIMARY KEY,
    nombre_franja VARCHAR(50),
    hora_inicio TIMESTAMPTZ NOT NULL,
    hora_fin TIMESTAMPTZ NOT NULL,
    --se debe agregar una restriccion para comprobar que la hora de finalizacion de esa franja sea mayor a la hora de inicio
    CONSTRAINT comprobacion_horas_en_franja CHECK(hora_fin>hora_inicio)
    --las columnas que llevan TIMESTAMPTZ se adaptan a la hora local, es decir UTC
);

CREATE TABLE tipo_entrada(
    id_tipo_entrada SERIAL PRIMARY KEY,
    nombre_tipo_de_entrada VARCHAR(40) NOT NULL, 
    --especifica si es para adulto, niño,etc
    requiere_credencial BOOLEAN NOT NULL

);

CREATE TABLE zona(
    id_zona SERIAL PRIMARY KEY,
    nombre_zona VARCHAR(100) NOT NULL

);

CREATE TABLE promocion(
    id_promocion SERIAL PRIMARY KEY,
    nombre_promocion VARCHAR(110) NOT NULL,
    tipo_regla VARCHAR(100) NOT NULL,
    descuento_porcentaje NUMERIC(5,2),
    condicion_minima VARCHAR(70) NOT NULL,
    dia_semana INT 
    CHECK(dia_semana BETWEEN 0 AND 6),
    --este check es para comprobar que no se salga del rango de 7 dias de la semana, donde 0=domingo,1=lunes, etc.
    promocion_esta_activa BOOLEAN DEFAULT TRUE
    --basicamente decimos que por defecto una promocion si esta activa
    CONSTRAINT verificacion_reglas_de_promocion CHECK((tipo_regla='2x1' AND dia_semana IS NULL)OR (tipo_regla='descuento_dia' AND dia_semana IS NOT NULL))
    --este constraint verifica que si hay 2x1, entonces no referencia a un dia, pues se puede dar en varios
    --ademas en descuento_dia obligatoriamente se le debe asociar un dia, por lo que no puede ser nulo

);


CREATE TABLE ciudad(
    id_ciudad SERIAL PRIMARY KEY,
    id_pais INT, 
    --es un FK
    nombre_ciudad VARCHAR(150),
    CONSTRAINT fk_ciudad FOREIGN KEY(id_pais) REFERENCES pais(id_pais),
    CONSTRAINT unicidad_ciudad_de_pais UNIQUE(id_pais,nombre_ciudad)
    --esta restriccion permite que esa combinacion no se repita y que cada ciudad en un pais sea unica con su nombre y id simultaneamente

);

CREATE TABLE usuario(
    id_usuario SERIAL PRIMARY KEY,
    id_rol INT,
    nombre_usuario VARCHAR(85) NOT NULL,
    correo VARCHAR(120) NOT NULL UNIQUE,
    telefono VARCHAR(20) UNIQUE,
    contraseña_hash VARCHAR(200),
    usuario_esta_activo BOOLEAN DEFAULT TRUE,
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_usuario FOREIGN KEY(id_rol) REFERENCES rol(id_rol)

);

CREATE TABLE pelicula(
    id_pelicula SERIAL PRIMARY KEY,
    titulo VARCHAR(300) NOT NULL,
    sinopsis TEXT NOT NULL,
    clasificacion_edad VARCHAR(5) NOT NULL,
    duracion_minutos INT NOT NULL CHECK(duracion_minutos>0),
    --comprobacion de dominio de duracion_minutos
    poster_url TEXT NOT NULL,
    pelicula_esta_activa BOOLEAN DEFAULT TRUE

);




CREATE TABLE cine(
    id_cine SERIAL PRIMARY KEY,
    id_ciudad INT, 
    --es una FK
    nombre_cine VARCHAR(120) NOT NULL,
    direccion VARCHAR(250) NOT NULL,
    zona_horaria VARCHAR(60) NOT NULL,
    CONSTRAINT fk_id_ciudad_para_cine FOREIGN KEY(id_ciudad) REFERENCES ciudad(id_ciudad),
    CONSTRAINT unicidad_en_cinde_de_ciudad  UNIQUE(id_ciudad,nombre_cine)
    --la combinacion del identificador de la ciudad y el nombre del cine no se puede repetir
    
);

CREATE TABLE rol_permiso(
    --ESTA TABLA ES LA TABLA INTERMEDIA generada por la relacion N:M de rol y modulo
    id_rol INT NOT NULL,
    id_modulo INT NOT NULL,
    PRIMARY KEY(id_rol,id_modulo),
    nivel VARCHAR(30) NOT NULL,
    --esto aclara si el rol de permiso es de lectura,escritura, ejecución o ninguno
    CONSTRAINT fk_rol_permiso1 FOREIGN KEY(id_rol) REFERENCES rol(id_rol),
    CONSTRAINT fk_rol_permiso2 FOREIGN KEY(id_modulo) REFERENCES modulo(id_modulo),
    
    CONSTRAINT verificacion_permisos_para_rol CHECK(nivel in('ninguno','lectura','escritura','ejecución','total'))
    --en esta se aclara los tipos de permiso que existen
);


CREATE TABLE pelicula_genero(
    --esta es la tabla intermedia entre pelicula y genero
    id_pelicula INT NOT NULL,
    id_genero INT NOT NULL,
    PRIMARY KEY(id_pelicula,id_genero),
    CONSTRAINT fk_peligenero_peli FOREIGN KEY(id_pelicula) REFERENCES pelicula(id_pelicula),
    CONSTRAINT fk_peligen_genero FOREIGN KEY(id_genero) REFERENCES genero(id_genero)

);

CREATE TABLE sala(
    id_sala SERIAL PRIMARY KEY,
    id_cine INT NOT NULL, 
    --es fk
    nombre_sala VARCHAR(120) NOT NULL,
    capacidad_total INT NOT NULL CHECK(capacidad_total>0),
    --revision de dominio
    sala_esta_activa BOOLEAN DEFAULT TRUE,
    CONSTRAINT fk_id_cine FOREIGN KEY(id_cine) REFERENCES cine(id_cine),
    CONSTRAINT unicidad_sala_cine UNIQUE(id_cine,nombre_sala)

);


CREATE table asiento(
    id_asiento SERIAL PRIMARY KEY,
    id_sala INT NOT NULL,
    id_zona INT NOT NULL,
    fila CHAR(1) NOT NULL,
    numero INT NOT NULL CHECK(numero>0),
    UNIQUE(id_sala,fila,numero),
    CONSTRAINT fk_id_sala_en_asiento FOREIGN KEY (id_sala) REFERENCES sala(id_sala),
    CONSTRAINT fk_id_zona FOREIGN KEY(id_zona) REFERENCES zona(id_zona),
    CONSTRAINT unicidad_asiento_sala UNIQUE(id_sala,fila,numero)
);
 
CREATE TABLE dispositivo_puerta(
    id_dispositivo SERIAL PRIMARY KEY,
    id_sala INT NOT NULL,
    nombre_dispositivo VARCHAR(60) NOT NULL,
    CONSTRAINT fk_id_sala_en_dispositivo FOREIGN KEY(id_sala) REFERENCES sala(id_sala)

);

CREATE TABLE tarifa(
    id_tarifa SERIAL PRIMARY KEY,
    id_pais INT NOT NULL,
    id_zona INT NOT NULL,
    id_franja INT NOT NULL,
    id_tipo_entrada INT NOT NULL,
    dia_semana_para_tarifa INT NOT NULL CHECK(dia_semana_para_tarifa BETWEEN 0 AND 6),
    precio_base NUMERIC(10,2) NOT NULL CHECK(precio_base>=0),
    CONSTRAINT fk_tarifa_en_pais FOREIGN KEY (id_pais) REFERENCES pais(id_pais),
    CONSTRAINT fk_tarifa_en_zona FOREIGN KEY (id_zona) REFERENCES zona(id_zona),
    CONSTRAINT fk_tarifa_en_franja FOREIGN KEY (id_franja) REFERENCES franja_horaria(id_franja),
    CONSTRAINT fk_tarifa_para_tipo_entrada FOREIGN KEY (id_tipo_entrada) REFERENCES tipo_entrada(id_tipo_entrada),
    CONSTRAINT unicidad_tarifa_combinacion UNIQUE(id_pais,id_zona,id_tipo_entrada,dia_semana_para_tarifa,id_franja)

);

CREATE TABLE funcion(
    id_funcion SERIAL PRIMARY KEY,
    id_pelicula INT NOT NULL,
    id_sala INT NOT NULL,
    fecha_hora_inicio TIMESTAMPTZ NOT NULL,
    fecha_hora_fin TIMESTAMPTZ NOT NULL,
    estado_funcion VARCHAR(35) DEFAULT 'programada',
    CONSTRAINT verificacion_estado_de_funcion CHECK(estado_funcion IN ('programada','cancelada','finalizada')),
    CONSTRAINT verificacion_fechas_de_funcion CHECK(fecha_hora_fin>fecha_hora_inicio),
    CONSTRAINT fk_relacionar_pelicula_en_funcion FOREIGN KEY (id_pelicula) REFERENCES pelicula(id_pelicula),
    CONSTRAINT fk_sala_en_funcion FOREIGN key (id_sala) REFERENCES sala(id_sala),
    CONSTRAINT evitar_traslape_en_sala EXCLUDE USING gist(
        id_sala WITH =,
        tstzrange(fecha_hora_inicio,fecha_hora_fin) WITH &&
    )
    --basicamente con esa linea se pone una restriccion para que no haya solapamiento
    --gist es un indice (Generalized Search Tree)

);

CREATE TABLE estado_asiento_funcion (
    id_funcion INT NOT NULL,
    id_asiento INT NOT NULL,
    PRIMARY KEY(id_funcion,id_asiento),
    estado VARCHAR(40) NOT NULL DEFAULT 'disponible',
    id_usuario INT,

    expiracion_bloqueo TIMESTAMPTZ,
    --esas ultimas 2 lineas pueden ser nulas (la fk de id_usuario y la de expiracion_bloqueo)
    CONSTRAINT fk_para_estado_asiento_de_usuario FOREIGN KEY(id_usuario) REFERENCES usuario(id_usuario), 
    CONSTRAINT fk_estado_asiento_para_funcion FOREIGN KEY(id_funcion) REFERENCES funcion(id_funcion),
    CONSTRAINT fk_identificar_estado_asiento FOREIGN KEY(id_asiento) REFERENCES asiento(id_asiento),

    CONSTRAINT revision_estado_funcion CHECK (estado IN ('disponible','bloqueado','ocupado')),
    CONSTRAINT verificacion_logica_en_bloqueo CHECK((estado='disponible' AND id_usuario IS NULL AND expiracion_bloqueo IS NULL) OR (estado='bloqueado' AND id_usuario IS NOT NULL AND expiracion_bloqueo IS NOT NULL)
    OR(estado='ocupado' AND expiracion_bloqueo IS NULL))
    

);

CREATE TABLE orden (
    id_orden SERIAL PRIMARY KEY,
    id_usuario INT NOT NULL, 

    id_funcion INT NOT NULL,
    id_promocion INT, -- Opcional
    canal VARCHAR(30) NOT NULL,
    estado_orden VARCHAR(30) NOT NULL,
    subtotal NUMERIC(10,2) NOT NULL CHECK(subtotal>=0),
    descuento NUMERIC(10,2) DEFAULT 0.00 CHECK(descuento>=0),
    cargo_servicio NUMERIC(10,2) DEFAULT 0.00 CHECK(cargo_servicio>=0),
    total NUMERIC(10,2) NOT NULL CHECK(total>=0),
    fecha_creacion TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    vendedor_asociado INT, -- FK nula para web/app, obligatoria si es taquilla/administrativo
    moneda VARCHAR(10) NOT NULL,

    --constraints de esta tabla
    CONSTRAINT fk_usuario_en_orden FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario),
    CONSTRAINT fk_funcion_en_orden FOREIGN KEY (id_funcion) REFERENCES funcion(id_funcion),
    CONSTRAINT fk_promocion_en_orden FOREIGN KEY (id_promocion) REFERENCES promocion(id_promocion),
    CONSTRAINT fk_de_vendedor_relacionado_a_usuario FOREIGN KEY (vendedor_asociado) REFERENCES usuario(id_usuario),
    CONSTRAINT chk_canal CHECK (canal IN ('web', 'app', 'taquilla', 'administrativo')),
    CONSTRAINT chk_estado_orden CHECK (estado_orden IN ('pendiente', 'pagada', 'fallida', 'anulada')),

    CONSTRAINT verificacion_vendedor_por_canal CHECK((canal IN('web','app') AND vendedor_asociado IS NULL) OR
    --tiene sentido, porque si es en uno de esos canales, entonces no se ocupa un vendedor
    (canal IN('taquilla','administrativo') AND vendedor_asociado IS NOT NULL)
    ),
    --aqui tambien tiene sentido, pues para esos canales, se necesita el vendedor

    UNIQUE(id_orden,id_funcion)
);


CREATE TABLE pago(
    id_pago SERIAL PRIMARY KEY,
    id_orden INT NOT NULL,
    id_metodo_pago INT NOT NULL,
    estado_pago VARCHAR(30) NOT NULL,
    monto NUMERIC(10,2) NOT NULL CHECK(monto>=0),
    token_pasarela VARCHAR(255), -- Nulo si es efectivo o cortesía
    ultimos4 VARCHAR(4),          -- Nulo si es efectivo o cortesía
    fecha_operacion TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pago_en_orden FOREIGN KEY (id_orden) REFERENCES orden(id_orden),
    CONSTRAINT fk_metodo_de_pago_en_orden FOREIGN KEY (id_metodo_pago) REFERENCES metodo_pago(id_metodo_pago),
    CONSTRAINT chk_estado_pago CHECK (estado_pago IN ('aprobado', 'rechazado', 'pendiente'))
);

CREATE TABLE boleto(
    id_boleto SERIAL PRIMARY KEY,
    id_orden INT NOT NULL,
    id_funcion INT NOT NULL,
    id_asiento INT NOT NULL,
    id_tipo_entrada INT NOT NULL,
    precio_final NUMERIC(10,2) NOT NULL,
    codigo_qr UUID NOT NULL UNIQUE,
    estado_boleto VARCHAR(30) NOT NULL DEFAULT 'emitido',
    origen VARCHAR(30) NOT NULL,
    fecha_emision TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    fecha_uso TIMESTAMPTZ,
    -- Las dos FK compuestas críticas de nuestro diseño:
    CONSTRAINT fk_boleto_orden_funcion FOREIGN KEY (id_orden, id_funcion) REFERENCES orden(id_orden, id_funcion),
    CONSTRAINT fk_boleto_asiento_funcion FOREIGN KEY (id_funcion, id_asiento) REFERENCES estado_asiento_funcion(id_funcion, id_asiento),
    CONSTRAINT fk_tipo_entrada_en_boleto FOREIGN KEY (id_tipo_entrada) REFERENCES tipo_entrada(id_tipo_entrada),
    CONSTRAINT chk_estado_boleto CHECK (estado_boleto IN ('emitido', 'usado', 'anulado')),
    CONSTRAINT chk_origen_boleto CHECK (origen IN ('online', 'taquilla', 'cortesia'))
);

CREATE UNIQUE INDEX indice_unico_boleto_activo
--esa linea garantiza que las columnas q se vayan a especificar sean unicas 
ON boleto (id_funcion,id_asiento)
--evita que haya doble venta de un mismo asiento, y si se anula, pues que quede libre de nuevo, asi otro cliente puede seleccionar ese asiento
WHERE estado_boleto <> 'anulado';



CREATE TABLE reembolso(
    id_reembolso SERIAL PRIMARY KEY,
    id_boleto INT ,
    --este se deja con posibilidad de ser nulo,pues si el pago es aprobado puede ser nulo despues de que tiempo de bloqueo terminó y ya se vendió el asiento a otra persona
    --aqui ya no existe boleto pero si se debe devolver dinero
    id_pago INT NOT NULL,
    id_usuario INT NOT NULL,
    monto_reembolso NUMERIC(9,3) NOT NULL,
    motivo VARCHAR(400) NOT NULL,
    forzado BOOLEAN NOT NULL DEFAULT FALSE,
    --este atributo si se hizo automaticamente con reglas, o tuvo aue forzarse el reembolso
    --si es TRUE, es por una excepcion gerencial
    fecha_reembolso TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_para_reembolso_de_boleto FOREIGN KEY(id_boleto) REFERENCES boleto(id_boleto),
    CONSTRAINT fk_reembolso_de_pago FOREIGN KEY(id_pago) REFERENCES pago(id_pago),
    CONSTRAINT fk_reembolso_a_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario)
);

/*TABLAS DE AUDITORIA*/
--en estas no ponemos FK´S pues al tener millones de registros por minuto, basicamente ocuparia ir a buscar a la tabla padre para ver si existe fisicamente tal id
-- eso afectaría rendimiento
CREATE TABLE transaccion_log(
    id_log SERIAL,
    fecha_hora TIMESTAMPTZ NOT NULL,
    id_orden INT,
    id_pago INT,
    evento VARCHAR(60) NOT NULL,
    monto NUMERIC(9,3),
    impuesto NUMERIC(9,3),
    moneda VARCHAR(25),
    referencia_pasarela VARCHAR(240),
    detalle JSONB,
    PRIMARY KEY(id_log,fecha_hora)

);

CREATE TABLE asiento_auditoria_log (
    id_log SERIAL,
    fecha_hora TIMESTAMPTZ NOT NULL,
    id_funcion INT,
    id_asiento INT,
    id_usuario INT,
    evento VARCHAR(50) NOT NULL,
    expira_en TIMESTAMPTZ,
    PRIMARY KEY (id_log, fecha_hora)
);

CREATE TABLE acceso_puerta_log(
    id_log SERIAL,
    fecha_hora TIMESTAMPTZ NOT NULL,
    id_boleto INT,
    id_dispositivo INT,
    resultado VARCHAR(40) NOT NULL,
    motivo VARCHAR(250),
    PRIMARY KEY (id_log,fecha_hora),
    CONSTRAINT chk_revision_resultado_acceso CHECK (resultado IN ('exitoso','duplicado','rechazado_horario','rechazado_credencial','funcion_incorrecta','invalido'))
);


CREATE TABLE admin_operacion_audit (
    id_log SERIAL,
    fecha_hora TIMESTAMPTZ NOT NULL,
    id_usuario INT,
    id_rol INT,
    ip_origen VARCHAR(45) NOT NULL,
    operacion VARCHAR(50) NOT NULL,
    entidad VARCHAR(50) NOT NULL,
    id_entidad INT,
    valor_anterior JSONB,
    valor_nuevo JSONB,
    PRIMARY KEY (id_log, fecha_hora)
);





