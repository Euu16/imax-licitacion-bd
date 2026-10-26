SELECT
    (SELECT count(*) FROM pelicula) AS peliculas,
    (SELECT count(*) FROM funcion) AS funciones,
    (SELECT count(*) FROM asiento) AS asientos,
    (SELECT count(*) FROM tarifa) AS tarifas;


DO $$
DECLARE
    v_pais       integer;
    v_ciudad     integer;
    v_cine       integer;
    v_zona       integer;
    v_sala       integer;
    v_genero     integer;
    v_pelicula   integer;
    v_tipo       integer;
    v_franja     integer;
    v_funcion    integer;
    v_metodo     integer;
    v_dispositivo integer;
    v_inicio     timestamptz;
    v_dia        integer;
    v_numero     integer;
BEGIN
    SELECT id_pais INTO v_pais
    FROM pais
    WHERE nombre = 'Costa Rica';

    IF v_pais IS NULL THEN
        INSERT INTO pais(nombre, moneda)
        VALUES ('Costa Rica', 'CRC')
        RETURNING id_pais INTO v_pais;
    END IF;

    SELECT id_ciudad INTO v_ciudad
    FROM ciudad
    WHERE id_pais = v_pais AND nombre_ciudad = 'San José';



SELECT n.nspname AS esquema,
       p.proname AS funcion,
       pg_get_function_identity_arguments(p.oid) AS argumentos,
       pg_get_function_result(p.oid) AS retorno
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.proname = 'liberar_asientos'
ORDER BY n.nspname;
    IF v_ciudad IS NULL THEN
        INSERT INTO ciudad(id_pais, nombre_ciudad)
        VALUES (v_pais, 'San José')
        RETURNING id_ciudad INTO v_ciudad;
    END IF;

    SELECT id_cine INTO v_cine
    FROM cine
    WHERE id_ciudad = v_ciudad AND nombre_cine = 'IMAX de Prueba';

    IF v_cine IS NULL THEN
        INSERT INTO cine(id_ciudad, nombre_cine, direccion, zona_horaria)
        VALUES (v_ciudad, 'IMAX de Prueba', 'Dirección de prueba', 'America/Costa_Rica')
        RETURNING id_cine INTO v_cine;
    END IF;

    SELECT id_zona INTO v_zona
    FROM zona
    WHERE nombre_zona = 'Zona General de Prueba';

    IF v_zona IS NULL THEN
        INSERT INTO zona(nombre_zona)
        VALUES ('Zona General de Prueba')
        RETURNING id_zona INTO v_zona;
    END IF;

    SELECT id_sala INTO v_sala
    FROM sala
    WHERE id_cine = v_cine AND nombre_sala = 'Sala de Prueba';

    IF v_sala IS NULL THEN
        INSERT INTO sala(id_cine, nombre_sala, capacidad_total)
        VALUES (v_cine, 'Sala de Prueba', 4)
        RETURNING id_sala INTO v_sala;
    END IF;

    SELECT id_genero INTO v_genero
    FROM genero
    WHERE nombre_genero = 'Aventura';

    IF v_genero IS NULL THEN
        INSERT INTO genero(nombre_genero)
        VALUES ('Aventura')
        RETURNING id_genero INTO v_genero;
    END IF;

    SELECT id_pelicula INTO v_pelicula
    FROM pelicula
    WHERE titulo = 'Película de Prueba IMAX'
    ORDER BY id_pelicula
    LIMIT 1;

    IF v_pelicula IS NULL THEN
        INSERT INTO pelicula(
            titulo, sinopsis, clasificacion_edad,
            duracion_minutos, poster_url, pelicula_esta_activa
        )
        VALUES (
            'Película de Prueba IMAX',
            'Registro ficticio para probar el backend.',
            'Todo público',
            120,
            'https://example.com/poster-prueba.jpg',
            true
        )
        RETURNING id_pelicula INTO v_pelicula;
    END IF;

    INSERT INTO pelicula_genero(id_pelicula, id_genero)
    VALUES (v_pelicula, v_genero)
    ON CONFLICT DO NOTHING;

    SELECT id_tipo_entrada INTO v_tipo
    FROM tipo_entrada
    WHERE nombre_tipo_de_entrada = 'adulto';

    IF v_tipo IS NULL THEN
        INSERT INTO tipo_entrada(nombre_tipo_de_entrada, requiere_credencial)
        VALUES ('adulto', false)
        RETURNING id_tipo_entrada INTO v_tipo;
    END IF;

    SELECT id_franja INTO v_franja
    FROM franja_horaria
    WHERE nombre_franja = 'Franja Completa de Prueba';

    IF v_franja IS NULL THEN
        INSERT INTO franja_horaria(nombre_franja, hora_inicio, hora_fin)
        VALUES ('Franja Completa de Prueba', '00:00', '23:59:59')
        RETURNING id_franja INTO v_franja;
    END IF;

    FOR v_numero IN 1..4 LOOP
        INSERT INTO asiento(id_sala, id_zona, fila, numero)
        VALUES (v_sala, v_zona, 'A', v_numero)
        ON CONFLICT (id_sala, fila, numero) DO NOTHING;
    END LOOP;

    SELECT id_metodo_pago INTO v_metodo
    FROM metodo_pago
    WHERE nombre_metodo_pago = 'tarjeta';

    IF v_metodo IS NULL THEN
        INSERT INTO metodo_pago(nombre_metodo_pago)
        VALUES ('tarjeta')
        RETURNING id_metodo_pago INTO v_metodo;
    END IF;

    SELECT id_dispositivo INTO v_dispositivo
    FROM dispositivo_puerta
    WHERE id_sala = v_sala AND nombre_dispositivo = 'Dispositivo de Prueba';

    IF v_dispositivo IS NULL THEN
        INSERT INTO dispositivo_puerta(id_sala, nombre_dispositivo)
        VALUES (v_sala, 'Dispositivo de Prueba')
        RETURNING id_dispositivo INTO v_dispositivo;
    END IF;

    v_inicio :=
        (date_trunc('day', clock_timestamp() AT TIME ZONE 'America/Costa_Rica')
         + interval '2 days 20 hours')
        AT TIME ZONE 'America/Costa_Rica';

    SELECT id_funcion INTO v_funcion
    FROM funcion
    WHERE id_pelicula = v_pelicula
      AND id_sala = v_sala
      AND fecha_hora_inicio = v_inicio
      AND estado_funcion = 'programada';

    IF v_funcion IS NULL THEN
        INSERT INTO funcion(
            id_pelicula, id_sala, fecha_hora_inicio, fecha_hora_fin
        )
        VALUES (v_pelicula, v_sala, v_inicio, v_inicio + interval '2 hours')
        RETURNING id_funcion INTO v_funcion;
    END IF;

    FOR v_dia IN 0..6 LOOP
        INSERT INTO tarifa(
            id_pais, id_zona, id_franja,
            id_tipo_entrada, dia_semana_para_tarifa, precio_base
        )
        VALUES (v_pais, v_zona, v_franja, v_tipo, v_dia, 3500.00)
        ON CONFLICT ON CONSTRAINT unicidad_tarifa_combinacion
        DO UPDATE SET precio_base = EXCLUDED.precio_base;
    END LOOP;

    RAISE NOTICE 'Datos de prueba listos. Función ID: %', v_funcion;
END $$;




SELECT
    f.id_funcion,
    f.fecha_hora_inicio,
    a.id_asiento,
    a.fila,
    a.numero,
    te.id_tipo_entrada,
    mp.id_metodo_pago
FROM funcion f
JOIN pelicula p USING (id_pelicula)
JOIN sala s USING (id_sala)
JOIN cine c USING (id_cine)
JOIN asiento a USING (id_sala)
JOIN tipo_entrada te ON te.nombre_tipo_de_entrada = 'adulto'
JOIN metodo_pago mp ON mp.nombre_metodo_pago = 'tarjeta'
WHERE p.titulo = 'Película de Prueba IMAX'
  AND c.nombre_cine = 'IMAX de Prueba'
  AND s.nombre_sala = 'Sala de Prueba'
  AND f.estado_funcion = 'programada'
  AND f.fecha_hora_inicio > now()
ORDER BY f.fecha_hora_inicio, a.numero;


ALTER ROLE postgres WITH PASSWORD 'base_bd26';


SELECT s.id_sala, s.nombre_sala, COUNT(a.id_asiento) AS total_asientos
FROM sala s
LEFT JOIN asiento a ON a.id_sala = s.id_sala
GROUP BY s.id_sala, s.nombre_sala
ORDER BY s.id_sala;


SELECT table_name, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('sala', 'asiento', 'funcion', 'asiento_funcion')
ORDER BY table_name, ordinal_position;


SELECT id_asiento, id_sala, id_zona, fila, numero
FROM asiento
WHERE id_sala = 1
ORDER BY fila, numero;




BEGIN;

INSERT INTO asiento (id_sala, id_zona, fila, numero)
SELECT 1, base.id_zona, nuevos.fila, nuevos.numero
FROM (
    SELECT id_zona
    FROM asiento
    WHERE id_sala = 1
    ORDER BY id_asiento
    LIMIT 1
) AS base
CROSS JOIN (
    SELECT 'A' AS fila, generate_series(5, 10) AS numero
    UNION ALL
    SELECT 'B', generate_series(1, 10)
    UNION ALL
    SELECT 'C', generate_series(1, 10)
) AS nuevos
WHERE NOT EXISTS (
    SELECT 1
    FROM asiento existente
    WHERE existente.id_sala = 1
      AND existente.fila = nuevos.fila
      AND existente.numero = nuevos.numero
);

UPDATE sala
SET capacidad_total = (
    SELECT COUNT(*)
    FROM asiento
    WHERE id_sala = 1
)
WHERE id_sala = 1;

SELECT s.id_sala, s.capacidad_total, COUNT(a.id_asiento) AS asientos_registrados
FROM sala s
LEFT JOIN asiento a ON a.id_sala = s.id_sala
WHERE s.id_sala = 1
GROUP BY s.id_sala, s.capacidad_total;

COMMIT;


ROLLBACK;



SELECT id_sala, nombre_sala, capacidad_total
FROM sala
WHERE id_sala = 1;

SELECT id_asiento, id_zona, fila, numero
FROM asiento
WHERE id_sala = 1
ORDER BY fila, numero;



WITH nueva_sala AS (
    INSERT INTO sala (id_cine, nombre_sala, capacidad_total, sala_esta_activa)
    SELECT id_cine, 'Sala de Prueba 2', 30, TRUE
    FROM sala
    WHERE id_sala = 1
    RETURNING id_sala
),
asientos AS (
    SELECT 'A' AS fila, generate_series(1, 10) AS numero
    UNION ALL
    SELECT 'B', generate_series(1, 10)
    UNION ALL
    SELECT 'C', generate_series(1, 10)
)
INSERT INTO asiento (id_sala, id_zona, fila, numero)
SELECT nueva_sala.id_sala, 1, asientos.fila, asientos.numero
FROM nueva_sala
CROSS JOIN asientos;



SELECT s.id_sala, s.nombre_sala, s.capacidad_total,
       COUNT(a.id_asiento) AS asientos_registrados
FROM sala s
LEFT JOIN asiento a ON a.id_sala = s.id_sala
WHERE s.nombre_sala = 'Sala de Prueba 2'
GROUP BY s.id_sala, s.nombre_sala, s.capacidad_total;



SELECT table_name, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('ciudad', 'cine', 'sala', 'zona', 'pelicula', 'funcion')
ORDER BY table_name, ordinal_position;



WITH pelicula AS (
    SELECT id_pelicula
    FROM pelicula
    WHERE pelicula_esta_activa = TRUE
    ORDER BY id_pelicula
    LIMIT 1
),
sala_nueva AS (
    SELECT id_sala
    FROM sala
    WHERE nombre_sala = 'Sala de Prueba 2'
    LIMIT 1
),
horarios (inicio, fin) AS (
    VALUES
    (TIMESTAMPTZ '2026-10-27 16:00:00-06', TIMESTAMPTZ '2026-10-27 18:00:00-06'),
    (TIMESTAMPTZ '2026-10-27 19:00:00-06', TIMESTAMPTZ '2026-10-27 21:15:00-06'),
    (TIMESTAMPTZ '2026-10-28 16:00:00-06', TIMESTAMPTZ '2026-10-28 17:45:00-06'),
    (TIMESTAMPTZ '2026-10-28 18:45:00-06', TIMESTAMPTZ '2026-10-28 20:55:00-06'),
    (TIMESTAMPTZ '2026-10-29 16:00:00-06', TIMESTAMPTZ '2026-10-29 17:55:00-06'),
    (TIMESTAMPTZ '2026-10-29 19:00:00-06', TIMESTAMPTZ '2026-10-29 20:35:00-06')
)
INSERT INTO funcion (id_pelicula, id_sala, fecha_hora_inicio, fecha_hora_fin)
SELECT pelicula.id_pelicula, sala_nueva.id_sala, horarios.inicio, horarios.fin
FROM pelicula
CROSS JOIN sala_nueva
CROSS JOIN horarios
RETURNING id_funcion, id_pelicula, id_sala, fecha_hora_inicio, fecha_hora_fin;





INSERT INTO ciudad (id_pais, nombre_ciudad)
SELECT pais_local.id_pais, nuevas.nombre_ciudad
FROM (
    SELECT ciudad.id_pais
    FROM cine
    JOIN ciudad USING (id_ciudad)
    WHERE cine.id_cine = 1
) AS pais_local
CROSS JOIN (
    VALUES ('Heredia'), ('Cartago')
) AS nuevas(nombre_ciudad)
WHERE NOT EXISTS (
    SELECT 1
    FROM ciudad existente
    WHERE existente.id_pais = pais_local.id_pais
      AND lower(existente.nombre_ciudad) = lower(nuevas.nombre_ciudad)
);



INSERT INTO cine (id_ciudad, nombre_cine, direccion, zona_horaria)
SELECT ciudad.id_ciudad, nuevos.nombre_cine, nuevos.direccion,
       (SELECT zona_horaria FROM cine WHERE id_cine = 1)
FROM (
    VALUES
      ('San José', 'IMAX Centro San José', 'Dirección de prueba, San José'),
      ('Heredia',  'IMAX Paseo Heredia',  'Dirección de prueba, Heredia'),
      ('Cartago',  'IMAX Cartago Este',   'Dirección de prueba, Cartago')
) AS nuevos(nombre_ciudad, nombre_cine, direccion)
JOIN ciudad
  ON lower(ciudad.nombre_ciudad) = lower(nuevos.nombre_ciudad)
 AND ciudad.id_pais = (
     SELECT ciudad_base.id_pais
     FROM cine cine_base
     JOIN ciudad ciudad_base USING (id_ciudad)
     WHERE cine_base.id_cine = 1
 )
WHERE NOT EXISTS (
    SELECT 1
    FROM cine existente
    WHERE existente.nombre_cine = nuevos.nombre_cine
)
RETURNING id_cine, id_ciudad, nombre_cine;




INSERT INTO sala (id_cine, nombre_sala, capacidad_total)
SELECT cine.id_cine, 'Sala General', 30
FROM cine
WHERE cine.nombre_cine IN (
    'IMAX Centro San José',
    'IMAX Paseo Heredia',
    'IMAX Cartago Este'
)
AND NOT EXISTS (
    SELECT 1
    FROM sala existente
    WHERE existente.id_cine = cine.id_cine
      AND existente.nombre_sala = 'Sala General'
);



INSERT INTO asiento (id_sala, id_zona, fila, numero)
SELECT sala.id_sala, 1, filas.fila, numeros.numero
FROM sala
JOIN cine ON cine.id_cine = sala.id_cine
CROSS JOIN (VALUES ('A'), ('B'), ('C')) AS filas(fila)
CROSS JOIN generate_series(1, 10) AS numeros(numero)
WHERE cine.nombre_cine IN (
    'IMAX Centro San José',
    'IMAX Paseo Heredia',
    'IMAX Cartago Este'
)
AND sala.nombre_sala = 'Sala General'
AND NOT EXISTS (
    SELECT 1
    FROM asiento existente
    WHERE existente.id_sala = sala.id_sala
      AND existente.fila = filas.fila
      AND existente.numero = numeros.numero
);



SELECT cine.nombre_cine, sala.id_sala, sala.capacidad_total,
       COUNT(asiento.id_asiento) AS asientos_registrados
FROM cine
JOIN sala ON sala.id_cine = cine.id_cine
LEFT JOIN asiento ON asiento.id_sala = sala.id_sala
WHERE sala.nombre_sala = 'Sala General'
  AND cine.nombre_cine IN (
      'IMAX Centro San José',
      'IMAX Paseo Heredia',
      'IMAX Cartago Este'
  )
GROUP BY cine.nombre_cine, sala.id_sala, sala.capacidad_total
ORDER BY cine.nombre_cine;




INSERT INTO pelicula
    (titulo, sinopsis, clasificacion_edad, duracion_minutos, poster_url, pelicula_esta_activa)
SELECT nuevas.titulo, nuevas.sinopsis, 'Todo público',
       nuevas.duracion_minutos, '', TRUE
FROM (
    VALUES
      ('Viaje al océano profundo', 'Una expedición descubre un mundo bajo el mar.', 120),
      ('Misión Orión', 'Una tripulación viaja hacia una estación espacial distante.', 135),
      ('El último bosque', 'Una comunidad protege el último bosque de su región.', 105),
      ('Código Aurora', 'Un equipo investiga una señal misteriosa en el norte.', 130),
      ('La ciudad de cristal', 'Una arquitecta descubre secretos bajo una ciudad futurista.', 115),
      ('Guardianes del arrecife', 'Un grupo de jóvenes protege un arrecife amenazado.', 95)
) AS nuevas(titulo, sinopsis, duracion_minutos)
WHERE NOT EXISTS (
    SELECT 1
    FROM pelicula existente
    WHERE existente.titulo = nuevas.titulo
)
RETURNING id_pelicula, titulo;



INSERT INTO funcion (id_pelicula, id_sala, fecha_hora_inicio, fecha_hora_fin)
SELECT pelicula.id_pelicula, sala.id_sala, horarios.inicio, horarios.fin
FROM (
    VALUES
      ('Viaje al océano profundo', 'IMAX Centro San José',
       TIMESTAMPTZ '2026-10-27 16:00:00-06', TIMESTAMPTZ '2026-10-27 18:00:00-06'),
      ('Misión Orión', 'IMAX Centro San José',
       TIMESTAMPTZ '2026-10-27 19:00:00-06', TIMESTAMPTZ '2026-10-27 21:15:00-06'),
      ('El último bosque', 'IMAX Paseo Heredia',
       TIMESTAMPTZ '2026-10-27 17:00:00-06', TIMESTAMPTZ '2026-10-27 18:45:00-06'),
      ('Código Aurora', 'IMAX Paseo Heredia',
       TIMESTAMPTZ '2026-10-27 20:00:00-06', TIMESTAMPTZ '2026-10-27 22:10:00-06'),
      ('La ciudad de cristal', 'IMAX Cartago Este',
       TIMESTAMPTZ '2026-10-28 16:00:00-06', TIMESTAMPTZ '2026-10-28 17:55:00-06'),
      ('Guardianes del arrecife', 'IMAX Cartago Este',
       TIMESTAMPTZ '2026-10-28 19:00:00-06', TIMESTAMPTZ '2026-10-28 20:35:00-06')
) AS horarios(titulo, nombre_cine, inicio, fin)
JOIN pelicula ON pelicula.titulo = horarios.titulo
JOIN cine ON cine.nombre_cine = horarios.nombre_cine
JOIN sala ON sala.id_cine = cine.id_cine
          AND sala.nombre_sala = 'Sala General'
WHERE NOT EXISTS (
    SELECT 1
    FROM funcion existente
    WHERE existente.id_sala = sala.id_sala
      AND existente.fecha_hora_inicio = horarios.inicio
)
RETURNING id_funcion, id_pelicula, id_sala, fecha_hora_inicio, fecha_hora_fin;



SELECT p.oid::regprocedure AS firma
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'liberar_asientos';



SELECT id_funcion, id_asiento, estado, id_usuario, expiracion_bloqueo
FROM estado_asiento_funcion
WHERE estado = 'bloqueado'
ORDER BY expiracion_bloqueo;