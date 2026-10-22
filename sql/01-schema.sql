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
    nombre_metodo_pago VARCHAR(45)--ya sea paypal, efectivo,etc
);
CREATE TABLE configuracion(
    id_configuracion SERIAL PRIMARY KEY,
    bloqueo_minutos INT,
    max_asientos_en_orden INT,
    tolerancia_antes_min INT,
    tolerancia_despues_min INT,
    reembolso_horas_antes INT,
    cargo_servicio_porcentaje FLOAT
);
CREATE TABLE genero(
    id_genero SERIAL PRIMARY KEY,
    nombre_genero VARCHAR(50)

);
CREATE TABLE franja_horaria(
    id_franja SERIAL PRIMARY KEY,
    nombre_franja VARCHAR(50),
    hora_inicio TIMESTAMP,
    hora_fin TIMESTAMP
);

CREATE TABLE ciudad(
    id_ciudad SERIAL PRIMARY KEY,
    id_pais INT, --es un FK
    nombre_ciudad VARCHAR(150)
    CONSTRAINT FOREIGN KEY(id_pais) REFERENCES pais(id_pais)
);

CREATE TABLE cine(
    id_cine SERIAL PRIMARY KEY,
    id_ciudad INT, --es una FK
    nombre_cine VARCHAR(120) NOT NULL,
    direccion VARCHAR(250) NOT NULL,
    zona_horaria TIMESTAMP NOT NULL,
    CONSTRAINT FOREIGN KEY(id_ciudad) REFERENCES ciudad(id_ciudad)
);

CREATE TABLE sala(
    id_sala SERIAL PRIMARY KEY,
    id_cine INT, --es fk
    nombre_sala VARCHAR(120) NOT NULL,
    capacidad_total INT,
    sala_esta_activa BOOLEAN,
    CONSTRAINT FOREIGN KEY(id_cine) REFERENCES cine(id_cine)
);

CREATE TABLE zona(
    id_zona SERIAL PRIMARY KEY,
    nombre_zona VARCHAR(100) NOT NULL,

);

CREATE table asiento()




CREATE TABLE dispositivo_puerta()

CREATE TABLE configuracion()



CREATE TABLE pelicula