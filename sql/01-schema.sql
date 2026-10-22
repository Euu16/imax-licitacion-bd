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
    id_configuracion SERIAL PRIMARY KEY,
    bloqueo_minutos INT,
    max_asientos_en_orden INT,
    tolerancia_antes_min INT,
    tolerancia_despues_min INT,
    reembolso_horas_antes INT,
    cargo_servicio_porcentaje NUMERIC(5,2) NOT NULL
);
CREATE TABLE genero(
    id_genero SERIAL PRIMARY KEY,
    nombre_genero VARCHAR(50)

);
CREATE TABLE franja_horaria(
    id_franja SERIAL PRIMARY KEY,
    nombre_franja VARCHAR(50),
    hora_inicio TIMESTAMPTZ NOT NULL,
    hora_fin TIMESTAMPTZ NOT NULL
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

);


CREATE TABLE ciudad(
    id_ciudad SERIAL PRIMARY KEY,
    id_pais INT, 
    --es un FK
    nombre_ciudad VARCHAR(150),
    CONSTRAINT FOREIGN KEY(id_pais) REFERENCES pais(id_pais)
);

CREATE TABLE usuario(
    id_usuario SERIAL PRIMARY KEY,
    id_rol INT,
    nombre_usuario VARCHAR(85) NOT NULL,
    correo VARCHAR(120) NOT NULL UNIQUE,
    telefono VARCHAR(20) UNIQUE,
    contraseña_hash VARCHAR(200),
    usuario_esta_activo BOOLEAN DEFAULT TRUE,
    fecha_registro TIMESTAMP,
    CONSTRAINT FOREIGN KEY(id_rol) REFERENCES rol(id_rol)

);

CREATE TABLE pelicula(
    id_pelicula SERIAL PRIMARY KEY,
    titulo VARCHAR(300) NOT NULL,
    sinopsis VARCHAR(1010) NOT NULL,
    clasificacion_edad VARCHAR(5) NOT NULL,
    duracion_minutos INT NOT NULL,
    poster_url VARCHAR(60) NOT NULL

);




CREATE TABLE cine(
    id_cine SERIAL PRIMARY KEY,
    id_ciudad INT, 
    --es una FK
    nombre_cine VARCHAR(120) NOT NULL,
    direccion VARCHAR(250) NOT NULL,
    zona_horaria VARCHAR(60) NOT NULL,
    CONSTRAINT FOREIGN KEY(id_ciudad) REFERENCES ciudad(id_ciudad)
);

CREATE TABLE rol_permiso(
    --ESTA TABLA ES LA TABLA INTERMEDIA generada por la relacion N:M de rol y modulo
    id_rol INT,
    id_modulo INT,
    PRIMARY KEY(id_rol,id_modulo),
    nivel VARCHAR(30) NOT NULL
    --esto aclara si el rol de permiso es de lectura,escritura, ejecución o ninguno
    CONSTRAINT FOREIGN KEY(id_rol) REFERENCES rol(id_rol),
    CONSTRAINT FOREIGN KEY(id_modulo) REFERENCES modulo(id_modulo),
    
    CHECK(nivel in('ninguno','lectura','escritura','ejecución','total'))
    --en esta se aclara los tipos de permiso que existen
);


CREATE TABLE pelicula_genero(
    --esta es la tabla intermedia entre pelicula y genero
    id_pelicula INT,
    id_genero INT,
    PRIMARY KEY(id_pelicula,id_genero),
    CONSTRAINT FOREIGN KEY(id_pelicula) REFERENCES pelicula(id_pelicula),
    CONSTRAINT FOREIGN KEY(id_genero) REFERENCES genero(id_genero)

);

CREATE TABLE sala(
    id_sala SERIAL PRIMARY KEY,
    id_cine INT, 
    --es fk
    nombre_sala VARCHAR(120) NOT NULL,
    capacidad_total INT,
    sala_esta_activa BOOLEAN,
    CONSTRAINT FOREIGN KEY(id_cine) REFERENCES cine(id_cine)
);


CREATE table asiento(
    id_asiento SERIAL PRIMARY KEY,
    id_sala INT,
    id_zona INT,
    fila CHAR(1) NOT NULL,
    numero INT NOT NULL,
    UNIQUE(id_sala,fila,numero),
    CONSTRAINT FOREIGN KEY (id_sala) REFERENCES sala(id_sala),
    CONSTRAINT FOREIGN KEY(id_zona) REFERENCES zona(id_zona)
);
 
CREATE TABLE dispositivo_puerta(
    id_dispositivo SERIAL PRIMARY KEY,
    id_sala INT,
    nombre_dispositivo VARCHAR(60) NOT NULL,
    CONSTRAINT FOREIGN KEY(id_sala) REFERENCES sala(id_sala)

);

CREATE TABLE tarifa(
    id_tarifa SERIAL PRIMARY KEY,
    id_pais INT,
    id_zona INT,
    id_franja INT,
    id_tipo_entrada INT,
    dia_semana_para_tarifa INT NOT NULL,
    precio_base NUMERIC(10,3) NOT NULL,
    CHECK(dia_semana_para_tarifa BETWEEN 0 AND 6),
    CONSTRAINT FOREIGN KEY (id_pais) REFERENCES pais(id_pais),
    CONSTRAINT FOREIGN KEY (id_zona) REFERENCES zona(id_zona),
    CONSTRAINT FOREIGN KEY (id_franja) REFERENCES franja_horaria(id_franja),
    CONSTRAINT FOREIGN KEY (id_tipo_entrada) REFERENCES tipo_entrada(id_tipo_entrada)

);

CREATE TABLE funcion(
    id_funcion SERIAL PRIMARY KEY,
    id_pelicula INT,
    id_sala INT,
    fecha_hora_inicio TIMESTAMPTZ NOT NULL,
    fecha_hora_fin TIMESTAMPTZ NOT NULL,
    estado_funcion VARCHAR(35),
    CHECK(estado_funcion IN ('programada','cancelada','finalizada')),
    CONSTRAINT FOREIGN KEY (id_pelicula) REFERENCES pelicula(id_pelicula),
    CONSTRAINT FOREIGN key (id_sala) REFERENCES sala(id_sala)

);

CREATE TABLE estado_asiento_funcion (
    id_funcion INT,
    id_asiento INT,
    PRIMARY KEY(id_funcion,id_asiento),
    estado VARCHAR(40) NOT NULL DEFAULT 'disponible',
    id_usuario INT REFERENCES usuario(id_usuario),

    expiracion_bloqueo TIMESTAMPTZ
    --esas ultimas 2 lineas pueden ser nulas (la fk de id_usuario y la de expiracion_bloqueo)
    CONSTRAINT FOREIGN KEY(id_funcion) REFERENCES funcion(id_funcion),
    CONSTRAINT FOREIGN KEY(id_asiento) REFERENCES asiento(id_asiento),

    CONSTRAINT revision_estado_funcion CHECK (estado IN ('disponible','bloqueado','ocupado'))
    

);

CREATE TABLE orden (
    id_orden SERIAL PRIMARY KEY,
    id_usuario INT NOT NULL, 

    id_funcion INT NOT NULL,
    id_promocion INT, -- Opcional
    canal VARCHAR(30) NOT NULL,
    estado_orden VARCHAR(30) NOT NULL,
    subtotal NUMERIC(10,2) NOT NULL,
    descuento NUMERIC(10,2) DEFAULT 0.00,
    cargo_servicio NUMERIC(10,2) DEFAULT 0.00,
    total NUMERIC(10,2) NOT NULL,
    fecha_creacion TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    vendedor_asociado INT, -- FK nula para web/app, obligatoria si es taquilla/administrativo
    moneda VARCHAR(10) NOT NULL,

    --constraints de esta tabla
    CONSTRAINT FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario),
    CONSTRAINT FOREIGN KEY (id_funcion) REFERENCES funcion(id_funcion),
    CONSTRAINT FOREIGN KEY (id_promocion) REFERENCES promocion(id_promocion),
    CONSTRAINT FOREIGN KEY (vendedor_asociado) REFERENCES usuario(id_usuario),
    CONSTRAINT chk_canal CHECK (canal IN ('web', 'app', 'taquilla', 'administrativo')),
    CONSTRAINT chk_estado_orden CHECK (estado_orden IN ('pendiente', 'pagada', 'fallida', 'anulada')),

    UNIQUE(id_orden,id_funcion)
);


CREATE TABLE pago(
    id_pago SERIAL PRIMARY KEY,
    id_orden INT NOT NULL,
    id_metodo_pago INT NOT NULL,
    estado_pago VARCHAR(30) NOT NULL,
    monto NUMERIC(10,2) NOT NULL,
    token_pasarela VARCHAR(255), -- Nulo si es efectivo o cortesía
    ultimos4 VARCHAR(4),          -- Nulo si es efectivo o cortesía
    fecha_operacion TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT FOREIGN KEY (id_orden) REFERENCES orden(id_orden),
    CONSTRAINT FOREIGN KEY (id_metodo_pago) REFERENCES metodo_pago(id_metodo_pago),
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
    CONSTRAINT FOREIGN KEY (id_tipo_entrada) REFERENCES tipo_entrada(id_tipo_entrada),
    CONSTRAINT chk_estado_boleto CHECK (estado_boleto IN ('emitido', 'usado', 'anulado')),
    CONSTRAINT chk_origen_boleto CHECK (origen IN ('online', 'taquilla', 'cortesia'))
);



CREATE TABLE reembolso(
    id_reembolso SERIAL PRIMARY KEY,
    id_boleto INT REFERENCES boleto(id_boleto),
    --este se deja con posibilidad de ser nulo,pues si el pago es aprobado puede ser nulo despues de que tiempo de bloqueo terminó y ya se vendió el asiento a otra persona
    --aqui ya no existe boleto pero si se debe devolver dinero
    id_pago INT,
    id_usuario INT,
    monto_reembolso NUMERIC(9,3) NOT NULL,
    motivo VARCHAR(400) NOT NULL,
    forzado BOOLEAN NOT NULL DEFAULT FALSE,
    --este atributo si se hizo automaticamente con reglas, o tuvo aue forzarse el reembolso
    --si es TRUE, es por una excepcion gerencial
    fecha_reembolso TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
    

);





