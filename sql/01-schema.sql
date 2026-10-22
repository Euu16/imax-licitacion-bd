CREATE TABLE pais(
    id_pais SERIAL PRIMARY KEY,
    nombre VARCHAR(110) NOT NULL,
    moneda VARCHAR(15) NOT NULL
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
    id_cine INT,
    nombre_sala VARCHAR(120) NOT NULL,
    capacidad_total INT,
    sala_esta_activa BOOLEAN
);