
\set ON_ERROR_STOP on

BEGIN;

DROP INDEX IF EXISTS ix_estado_asiento_bloqueado;
DROP INDEX IF EXISTS ix_boleto_emitido_fecha;
ANALYZE estado_asiento_funcion;
ANALYZE boleto;

\echo 'ANTES: disponibilidad y bloqueos activos'
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT e.id_asiento, e.expiracion_bloqueo
  FROM estado_asiento_funcion e
 WHERE e.id_funcion = :function_id
   AND e.id_usuario = :user_id
   AND e.estado = 'bloqueado'
   AND e.expiracion_bloqueo > clock_timestamp();

\echo 'ANTES: boletos emitidos en los últimos siete días'
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT p.id_pelicula, p.titulo, count(*) AS boletos_vendidos
  FROM boleto b
  JOIN funcion f USING (id_funcion)
  JOIN pelicula p USING (id_pelicula)
 WHERE b.estado_boleto = 'emitido'
   AND b.fecha_emision >= now() - interval '7 days'
 GROUP BY p.id_pelicula, p.titulo
 ORDER BY boletos_vendidos DESC
 LIMIT 5;

CREATE INDEX ix_estado_asiento_bloqueado
    ON estado_asiento_funcion (id_funcion, id_usuario, expiracion_bloqueo)
    WHERE estado = 'bloqueado';
CREATE INDEX ix_boleto_emitido_fecha
    ON boleto (fecha_emision, id_funcion)
    WHERE estado_boleto = 'emitido';
ANALYZE estado_asiento_funcion;
ANALYZE boleto;

\echo 'DESPUES: disponibilidad y bloqueos activos'
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT e.id_asiento, e.expiracion_bloqueo
  FROM estado_asiento_funcion e
 WHERE e.id_funcion = :function_id
   AND e.id_usuario = :user_id
   AND e.estado = 'bloqueado'
   AND e.expiracion_bloqueo > clock_timestamp();

\echo 'DESPUES: boletos emitidos en los últimos siete días'
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT p.id_pelicula, p.titulo, count(*) AS boletos_vendidos
  FROM boleto b
  JOIN funcion f USING (id_funcion)
  JOIN pelicula p USING (id_pelicula)
 WHERE b.estado_boleto = 'emitido'
   AND b.fecha_emision >= now() - interval '7 days'
 GROUP BY p.id_pelicula, p.titulo
 ORDER BY boletos_vendidos DESC
 LIMIT 5;

ROLLBACK;
