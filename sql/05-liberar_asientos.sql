-- Correccion incremental para bases que ya tienen el esquema instalado.
-- Libera solamente bloqueos del usuario que hace la solicitud.
CREATE OR REPLACE FUNCTION liberar_asientos(
    p_id_funcion bigint,
    p_ids_asiento integer[],
    p_id_usuario bigint
) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_liberados bigint;
BEGIN
    IF p_ids_asiento IS NULL OR cardinality(p_ids_asiento) = 0 THEN
        RAISE EXCEPTION 'Debe indicar al menos un asiento para liberar';
    END IF;

    UPDATE estado_asiento_funcion
    SET estado = 'disponible', id_usuario = NULL, expiracion_bloqueo = NULL
    WHERE id_funcion = p_id_funcion
      AND id_asiento = ANY(p_ids_asiento)
      AND estado = 'bloqueado'
      AND id_usuario = p_id_usuario;

    GET DIAGNOSTICS v_liberados = ROW_COUNT;
    RETURN v_liberados;
END;
$$;
