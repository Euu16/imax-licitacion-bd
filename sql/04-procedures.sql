CREATE FUNCTION validar_sala_de_estado_asiento() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_sala_funcion integer;
    v_sala_asiento integer;
BEGIN
    SELECT id_sala INTO v_sala_funcion
    FROM funcion WHERE id_funcion = NEW.id_funcion;
    SELECT id_sala INTO v_sala_asiento
    FROM asiento WHERE id_asiento = NEW.id_asiento;

    IF v_sala_funcion IS NULL OR v_sala_asiento IS NULL
       OR v_sala_funcion <> v_sala_asiento THEN
        RAISE EXCEPTION 'El asiento no pertenece a la sala de la función';
    END IF;
    IF NEW.estado = 'bloqueado' AND NEW.expiracion_bloqueo <= clock_timestamp() THEN
        RAISE EXCEPTION 'La expiración del bloqueo debe estar en el futuro';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.estado = 'ocupado' AND NEW.estado <> 'ocupado'
       AND EXISTS (
           SELECT 1 FROM boleto b
           WHERE b.id_funcion = OLD.id_funcion
             AND b.id_asiento = OLD.id_asiento
             AND b.estado_boleto <> 'anulado'
       ) THEN
        RAISE EXCEPTION 'No se puede liberar un asiento con un boleto vigente';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_sala_de_estado_asiento
BEFORE INSERT OR UPDATE ON estado_asiento_funcion
FOR EACH ROW EXECUTE FUNCTION validar_sala_de_estado_asiento();


-- 2. Un estado ocupado debe tener un boleto vigente al terminar la transacción.
CREATE FUNCTION comprobar_asiento_ocupado_con_boleto() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_estado varchar(15);
BEGIN
    SELECT estado INTO v_estado
    FROM estado_asiento_funcion
    WHERE id_funcion = NEW.id_funcion AND id_asiento = NEW.id_asiento;
    IF v_estado = 'ocupado' AND NOT EXISTS (
        SELECT 1 FROM boleto b
        WHERE b.id_funcion = NEW.id_funcion
          AND b.id_asiento = NEW.id_asiento
          AND b.estado_boleto <> 'anulado'
    ) THEN
        RAISE EXCEPTION 'Un asiento ocupado debe tener un boleto vigente';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER ct_asiento_ocupado_tiene_boleto
AFTER INSERT OR UPDATE ON estado_asiento_funcion
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION comprobar_asiento_ocupado_con_boleto();


-- 3. Reserva INDIVIDUAL de cada asiento
CREATE FUNCTION reservar_asientos(
    p_id_funcion bigint,
    p_ids_asiento integer[],
    p_id_usuario bigint
) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_max smallint;
    v_minutos smallint;
    v_ids integer[];
    v_id_asiento integer;
    v_sala integer;
    v_estado varchar(20);
    v_inicio timestamptz;
    v_existentes integer;
    v_nuevos integer;
BEGIN
    IF p_ids_asiento IS NULL OR cardinality(p_ids_asiento) = 0 THEN
        RAISE EXCEPTION 'Debe seleccionar al menos un asiento';
    END IF;
    SELECT array_agg(u.id_asiento ORDER BY u.id_asiento) INTO v_ids
    FROM unnest(p_ids_asiento) AS u(id_asiento);
    IF cardinality(v_ids) <> (SELECT count(DISTINCT u.id_asiento) FROM unnest(v_ids) AS u(id_asiento)) THEN
        RAISE EXCEPTION 'La selección contiene asientos duplicados';
    END IF;
    SELECT max_asientos_en_orden, bloqueo_minutos INTO v_max, v_minutos
    FROM configuracion WHERE id_configuracion = 1;
    IF cardinality(v_ids) > v_max THEN
        RAISE EXCEPTION 'La cantidad de asientos supera el máximo permitido (%)', v_max;
    END IF;

    PERFORM 1 FROM usuario WHERE id_usuario = p_id_usuario AND usuario_esta_activo FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El usuario no existe o está inactivo';
    END IF;
    SELECT id_sala, estado_funcion, fecha_hora_inicio
      INTO v_sala, v_estado, v_inicio
    FROM funcion WHERE id_funcion = p_id_funcion;
    IF NOT FOUND OR v_estado <> 'programada' OR v_inicio <= clock_timestamp() THEN
        RAISE EXCEPTION 'La función no está disponible para reservar';
    END IF;

    SELECT count(*) INTO v_existentes
    FROM estado_asiento_funcion e
    WHERE e.id_funcion = p_id_funcion
      AND e.id_usuario = p_id_usuario
      AND e.estado = 'bloqueado'
      AND e.expiracion_bloqueo > clock_timestamp();
    SELECT count(*) INTO v_nuevos
    FROM unnest(v_ids) AS x(id_asiento)
    WHERE NOT EXISTS (
        SELECT 1 FROM estado_asiento_funcion e
        WHERE e.id_funcion = p_id_funcion
          AND e.id_asiento = x.id_asiento
          AND e.id_usuario = p_id_usuario
          AND e.estado = 'bloqueado'
          AND e.expiracion_bloqueo > clock_timestamp()
    );
    IF v_existentes + v_nuevos > v_max THEN
        RAISE EXCEPTION 'El usuario ya tiene bloqueos activos que exceden el máximo permitido (%)', v_max;
    END IF;

    FOREACH v_id_asiento IN ARRAY v_ids LOOP
        IF NOT EXISTS (SELECT 1 FROM asiento WHERE id_asiento = v_id_asiento AND id_sala = v_sala) THEN
            RAISE EXCEPTION 'El asiento % no pertenece a la sala de la función', v_id_asiento;
        END IF;
        INSERT INTO estado_asiento_funcion
            (id_funcion, id_asiento, estado, id_usuario, expiracion_bloqueo)
        VALUES
            (p_id_funcion, v_id_asiento, 'bloqueado', p_id_usuario,
             clock_timestamp() + make_interval(mins => v_minutos))
        ON CONFLICT (id_funcion, id_asiento) DO UPDATE
        SET estado = 'bloqueado', id_usuario = EXCLUDED.id_usuario,
            expiracion_bloqueo = EXCLUDED.expiracion_bloqueo
        WHERE estado_asiento_funcion.estado = 'disponible'
           OR (estado_asiento_funcion.estado = 'bloqueado'
               AND estado_asiento_funcion.expiracion_bloqueo <= clock_timestamp())
           OR (estado_asiento_funcion.estado = 'bloqueado'
               AND estado_asiento_funcion.id_usuario = p_id_usuario);
        IF NOT FOUND THEN
            RAISE EXCEPTION 'El asiento % ya no está disponible', v_id_asiento;
        END IF;
    END LOOP;
END;
$$;


-- 4. Liberación de bloqueso ya vencidos
CREATE FUNCTION liberar_bloqueos_vencidos() RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_liberados bigint;
BEGIN
    UPDATE estado_asiento_funcion
    SET estado = 'disponible', id_usuario = NULL, expiracion_bloqueo = NULL
    WHERE estado = 'bloqueado' AND expiracion_bloqueo <= clock_timestamp();
    GET DIAGNOSTICS v_liberados = ROW_COUNT;
    RETURN v_liberados;
END;
$$;


-- 5. Validación de roles de cada usuario
CREATE FUNCTION validar_roles_de_orden() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_rol_cliente text;
    v_rol_vendedor text;
BEGIN
    SELECT r.nombre_rol INTO v_rol_cliente
    FROM usuario u JOIN rol r USING (id_rol)
    WHERE u.id_usuario = NEW.id_usuario AND u.usuario_esta_activo;
    IF v_rol_cliente IS NULL THEN
        RAISE EXCEPTION 'El cliente debe ser un usuario válido';
    END IF;
    IF NEW.canal IN ('web', 'app') THEN
        IF v_rol_cliente <> 'cliente' THEN
            RAISE EXCEPTION 'Las ventas web/app requieren un usuario con rol cliente';
        END IF;
    ELSIF v_rol_cliente NOT IN ('cliente', 'cliente_mostrador') THEN
        RAISE EXCEPTION 'La orden presencial debe pertenecer a un cliente';
    END IF;

    IF NEW.canal IN ('taquilla', 'administrativo') THEN
        SELECT r.nombre_rol INTO v_rol_vendedor
        FROM usuario u JOIN rol r USING (id_rol)
        WHERE u.id_usuario = NEW.vendedor_asociado AND u.usuario_esta_activo;
        IF NEW.canal = 'taquilla' AND v_rol_vendedor IS DISTINCT FROM 'taquillero' THEN
            RAISE EXCEPTION 'Las ventas de taquilla requieren un vendedor con rol taquillero';
        ELSIF NEW.canal = 'administrativo' AND v_rol_vendedor IS DISTINCT FROM 'administrador/gerente' THEN
            RAISE EXCEPTION 'Las órdenes administrativas requieren administrador/gerente';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_roles_de_orden
BEFORE INSERT OR UPDATE ON orden
FOR EACH ROW EXECUTE FUNCTION validar_roles_de_orden();


-- 6. Validación de montos y reglas de pago.
CREATE FUNCTION validar_monto_y_orden_pago() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_total numeric(10,2);
    v_estado_orden varchar(30);
    v_metodo text;
    v_canal varchar(30);
BEGIN
    SELECT total, estado_orden, canal INTO v_total, v_estado_orden, v_canal
    FROM orden WHERE id_orden = NEW.id_orden FOR UPDATE;
    SELECT nombre_metodo_pago INTO v_metodo
    FROM metodo_pago WHERE id_metodo_pago = NEW.id_metodo_pago;
    IF NEW.monto <> v_total THEN
        RAISE EXCEPTION 'El monto del pago debe coincidir con el total de la orden';
    END IF;
    IF (NEW.monto = 0 AND v_metodo <> 'cortesia')
       OR (NEW.monto > 0 AND v_metodo = 'cortesia') THEN
        RAISE EXCEPTION 'El método cortesia y el monto cero deben usarse juntos';
    END IF;
    IF v_metodo = 'cortesia' AND (v_canal <> 'administrativo' OR NEW.estado_pago <> 'aprobado') THEN
        RAISE EXCEPTION 'La cortesía requiere orden administrativa y pago aprobado';
    END IF;
    IF v_canal = 'administrativo' AND v_metodo <> 'cortesia' THEN
        RAISE EXCEPTION 'Las órdenes administrativas deben registrarse como cortesía';
    END IF;
    IF v_canal IN ('web', 'app') AND v_metodo IN ('efectivo', 'cortesia') THEN
        RAISE EXCEPTION 'El método efectivo/cortesia no está disponible en web/app';
    END IF;
    IF NEW.estado_pago = 'aprobado' AND v_estado_orden = 'anulada' THEN
        RAISE EXCEPTION 'No se puede aprobar un pago para una orden anulada';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_monto_y_orden_pago
BEFORE INSERT OR UPDATE ON pago
FOR EACH ROW EXECUTE FUNCTION validar_monto_y_orden_pago();


-- 7. Validación de orden pagada con pago aprobado.
CREATE FUNCTION validar_orden_pagada() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.estado_orden = 'pagada' AND NOT EXISTS (
        SELECT 1 FROM pago p
        WHERE p.id_orden = NEW.id_orden AND p.estado_pago = 'aprobado'
    ) THEN
        RAISE EXCEPTION 'Una orden solo puede quedar pagada con un pago aprobado';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER ct_orden_pagada_con_pago_aprobado
AFTER INSERT OR UPDATE ON orden
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION validar_orden_pagada();


-- 8. Validación de emisión de boletos.
CREATE FUNCTION validar_emision_boleto() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_cliente bigint;
    v_vendedor bigint;
    v_canal varchar(30);
    v_estado_orden varchar(30);
    v_bloqueo_usuario bigint;
    v_bloqueo_expira timestamptz;
    v_bloqueo_estado varchar(40);
    v_max smallint;
    v_cantidad integer;
    v_metodo_cortesia boolean;
BEGIN
    SELECT id_usuario, vendedor_asociado, canal, estado_orden
      INTO v_cliente, v_vendedor, v_canal, v_estado_orden
    FROM orden WHERE id_orden = NEW.id_orden FOR UPDATE;
    IF v_estado_orden <> 'pagada' OR NOT EXISTS (
        SELECT 1 FROM pago WHERE id_orden = NEW.id_orden AND estado_pago = 'aprobado'
    ) THEN
        RAISE EXCEPTION 'El boleto requiere una orden pagada con pago aprobado';
    END IF;
    SELECT EXISTS (
        SELECT 1 FROM pago p JOIN metodo_pago m USING (id_metodo_pago)
        WHERE p.id_orden = NEW.id_orden AND p.estado_pago = 'aprobado' AND m.nombre_metodo_pago = 'cortesia'
    ) INTO v_metodo_cortesia;
    IF (NEW.origen = 'cortesia' AND NOT v_metodo_cortesia)
       OR (NEW.origen <> 'cortesia' AND v_metodo_cortesia) THEN
        RAISE EXCEPTION 'El origen cortesia debe coincidir con el método de pago cortesia';
    END IF;
    IF (v_canal IN ('web', 'app') AND NEW.origen <> 'online')
       OR (v_canal = 'taquilla' AND NEW.origen <> 'taquilla')
       OR (v_canal = 'administrativo' AND NEW.origen <> 'cortesia') THEN
        RAISE EXCEPTION 'El origen del boleto no coincide con el canal de la orden';
    END IF;

    SELECT estado, id_usuario, expiracion_bloqueo
      INTO v_bloqueo_estado, v_bloqueo_usuario, v_bloqueo_expira
    FROM estado_asiento_funcion
    WHERE id_funcion = NEW.id_funcion AND id_asiento = NEW.id_asiento
    FOR UPDATE;
    IF NOT FOUND OR v_bloqueo_estado <> 'bloqueado' OR v_bloqueo_expira <= clock_timestamp() THEN
        RAISE EXCEPTION 'El asiento no tiene un bloqueo vigente';
    END IF;
    IF v_bloqueo_usuario IS DISTINCT FROM (CASE WHEN v_canal IN ('web', 'app') THEN v_cliente ELSE v_vendedor END) THEN
        RAISE EXCEPTION 'El bloqueo del asiento pertenece a otro usuario';
    END IF;

    SELECT max_asientos_en_orden INTO v_max FROM configuracion WHERE id_configuracion = 1;
    SELECT count(*) INTO v_cantidad FROM boleto
    WHERE id_orden = NEW.id_orden AND estado_boleto <> 'anulado';
    IF v_cantidad >= v_max THEN
        RAISE EXCEPTION 'La orden excede el máximo de boletos permitido (%)', v_max;
    END IF;
    IF NEW.estado_boleto <> 'emitido' OR NEW.fecha_uso IS NOT NULL THEN
        RAISE EXCEPTION 'El boleto debe crearse en estado emitido y sin fecha de uso';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_emision_boleto
BEFORE INSERT ON boleto
FOR EACH ROW EXECUTE FUNCTION validar_emision_boleto();


-- 9. Protección LOS ESTADOS DE BOLETO 
CREATE FUNCTION proteger_transicion_boleto() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.estado_boleto = 'usado' AND OLD.estado_boleto <> 'usado'
       AND current_setting('imax.checkin', true) IS DISTINCT FROM 'on' THEN
        RAISE EXCEPTION 'El boleto solo puede marcarse usado mediante validar_acceso_qr';
    END IF;
    IF NEW.estado_boleto = 'anulado' AND OLD.estado_boleto <> 'anulado'
       AND NOT EXISTS (SELECT 1 FROM reembolso r WHERE r.id_boleto = OLD.id_boleto) THEN
        RAISE EXCEPTION 'El boleto solo puede anularse como parte de un reembolso';
    END IF;
    IF OLD.estado_boleto = 'usado' AND NEW.estado_boleto <> 'usado' THEN
        RAISE EXCEPTION 'Un boleto usado no puede reactivarse ni anularse';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_proteger_transicion_boleto
BEFORE UPDATE OF estado_boleto ON boleto
FOR EACH ROW EXECUTE FUNCTION proteger_transicion_boleto();


CREATE FUNCTION validar_reembolso() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_estado_pago varchar(30);
    v_monto_pago numeric(10,2);
    v_id_orden bigint;
    v_inicio timestamptz;
    v_horas smallint;
    v_ya_reembolsado numeric(10,2);
    v_rol text;
    v_id_rol smallint;
    v_boleto_orden bigint;
    v_estado_boleto varchar(30);
BEGIN
    SELECT p.estado_pago, p.monto, p.id_orden, f.fecha_hora_inicio
      INTO v_estado_pago, v_monto_pago, v_id_orden, v_inicio
    FROM pago p
    JOIN orden o ON o.id_orden = p.id_orden
    JOIN funcion f ON f.id_funcion = o.id_funcion
    WHERE p.id_pago = NEW.id_pago
    FOR UPDATE OF p;
    IF v_estado_pago <> 'aprobado' THEN
        RAISE EXCEPTION 'Solo se puede reembolsar un pago aprobado';
    END IF;
    IF NEW.id_boleto IS NOT NULL THEN
        SELECT id_orden, estado_boleto INTO v_boleto_orden, v_estado_boleto
        FROM boleto WHERE id_boleto = NEW.id_boleto FOR UPDATE;
        IF v_boleto_orden IS DISTINCT FROM v_id_orden OR v_estado_boleto <> 'emitido' THEN
            RAISE EXCEPTION 'El boleto no pertenece al pago o ya no está emitido';
        END IF;
    END IF;

    SELECT COALESCE(sum(monto_reembolso), 0) INTO v_ya_reembolsado
    FROM reembolso WHERE id_pago = NEW.id_pago;
    IF NEW.monto_reembolso + v_ya_reembolsado > v_monto_pago THEN
        RAISE EXCEPTION 'El total reembolsado excedería el pago aprobado';
    END IF;

    IF NEW.forzado THEN
        IF NEW.id_usuario IS NULL THEN
            RAISE EXCEPTION 'Un reembolso forzado requiere un administrador responsable';
        END IF;
        SELECT r.id_rol, r.nombre_rol INTO v_id_rol, v_rol
        FROM usuario u JOIN rol r USING (id_rol)
        WHERE u.id_usuario = NEW.id_usuario AND u.usuario_esta_activo;
        IF v_rol IS DISTINCT FROM 'administrador/gerente' THEN
            RAISE EXCEPTION 'Solo administrador/gerente puede forzar un reembolso';
        END IF;
    ELSE
        SELECT reembolso_horas_antes INTO v_horas FROM configuracion WHERE id_configuracion = 1;
        IF NEW.id_boleto IS NOT NULL AND v_inicio <= clock_timestamp() + make_interval(hours => v_horas) THEN
            RAISE EXCEPTION 'El reembolso ordinario debe solicitarse con la anticipación configurada';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_reembolso
BEFORE INSERT ON reembolso
FOR EACH ROW EXECUTE FUNCTION validar_reembolso();


-- 11. VALIDACION del codigo QR EN PUERTA PARA FUNCION
CREATE FUNCTION validar_acceso_qr(
    p_codigo_qr uuid,
    p_id_dispositivo integer,
    p_credencial_validada boolean DEFAULT true
) RETURNS varchar
LANGUAGE plpgsql AS $$
DECLARE
    v_boleto boleto%ROWTYPE;
    v_inicio timestamptz;
    v_estado_funcion varchar(35);
    v_sala_funcion integer;
    v_sala_dispositivo integer;
    v_requiere_credencial boolean;
    v_antes smallint;
    v_despues smallint;
    v_resultado varchar(40);
    v_motivo text;
    v_actualizados integer;
BEGIN
    SELECT * INTO v_boleto FROM boleto WHERE codigo_qr = p_codigo_qr FOR UPDATE;
    IF NOT FOUND THEN
        INSERT INTO acceso_puerta_log (id_dispositivo, resultado, motivo)
        VALUES (p_id_dispositivo, 'invalido', 'Código QR inexistente');
        RETURN 'invalido';
    END IF;
    IF v_boleto.estado_boleto = 'usado' THEN
        INSERT INTO acceso_puerta_log (id_boleto, id_dispositivo, resultado, motivo)
        VALUES (v_boleto.id_boleto, p_id_dispositivo, 'duplicado', 'El boleto ya fue utilizado');
        RETURN 'duplicado';
    ELSIF v_boleto.estado_boleto <> 'emitido' THEN
        INSERT INTO acceso_puerta_log (id_boleto, id_dispositivo, resultado, motivo)
        VALUES (v_boleto.id_boleto, p_id_dispositivo, 'invalido', 'El boleto está anulado');
        RETURN 'invalido';
    END IF;

    SELECT f.fecha_hora_inicio, f.estado_funcion, f.id_sala, te.requiere_credencial
      INTO v_inicio, v_estado_funcion, v_sala_funcion, v_requiere_credencial
    FROM funcion f CROSS JOIN tipo_entrada te
    WHERE f.id_funcion = v_boleto.id_funcion
      AND te.id_tipo_entrada = v_boleto.id_tipo_entrada;
    SELECT id_sala INTO v_sala_dispositivo
    FROM dispositivo_puerta WHERE id_dispositivo = p_id_dispositivo;
    IF v_estado_funcion <> 'programada' THEN
        v_resultado := 'invalido';
        v_motivo := 'La función no está programada';
    ELSIF v_sala_dispositivo IS NULL OR v_sala_dispositivo <> v_sala_funcion THEN
        v_resultado := 'funcion_incorrecta';
        v_motivo := 'El lector no corresponde a la sala de la función';
    ELSE
        SELECT tolerancia_antes_min, tolerancia_despues_min
          INTO v_antes, v_despues FROM configuracion WHERE id_configuracion = 1;
        IF clock_timestamp() < v_inicio - make_interval(mins => v_antes)
           OR clock_timestamp() > v_inicio + make_interval(mins => v_despues) THEN
            v_resultado := 'rechazado_horario';
            v_motivo := 'Fuera de la ventana de acceso permitida';
        ELSIF v_requiere_credencial AND p_credencial_validada IS DISTINCT FROM true THEN
            v_resultado := 'rechazado_credencial';
            v_motivo := 'No se presentó la credencial requerida';
        ELSE
            PERFORM set_config('imax.checkin', 'on', true);
            UPDATE boleto SET estado_boleto = 'usado', fecha_uso = clock_timestamp()
            WHERE id_boleto = v_boleto.id_boleto AND estado_boleto = 'emitido';
            GET DIAGNOSTICS v_actualizados = ROW_COUNT;
            PERFORM set_config('imax.checkin', 'off', true);
            IF v_actualizados = 1 THEN
                v_resultado := 'exitoso';
                v_motivo := NULL;
            ELSE
                v_resultado := 'duplicado';
                v_motivo := 'El boleto ya fue utilizado';
            END IF;
        END IF;
    END IF;
    INSERT INTO acceso_puerta_log (id_boleto, id_dispositivo, resultado, motivo)
    VALUES (v_boleto.id_boleto, p_id_dispositivo, v_resultado, v_motivo);
    RETURN v_resultado;
END;
$$;


-- Basado en RN-18
CREATE FUNCTION proteger_sala_con_ventas() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_id_sala integer;
BEGIN
    v_id_sala := OLD.id_sala;
    IF EXISTS (
        SELECT 1 FROM funcion f
        WHERE f.id_sala = v_id_sala
          AND f.estado_funcion = 'programada'
          AND f.fecha_hora_inicio > clock_timestamp()
          AND (
              EXISTS (SELECT 1 FROM boleto b WHERE b.id_funcion = f.id_funcion
                      AND b.estado_boleto <> 'anulado')
              OR EXISTS (SELECT 1 FROM estado_asiento_funcion e
                         WHERE e.id_funcion = f.id_funcion
                           AND e.estado = 'bloqueado'
                           AND e.expiracion_bloqueo > clock_timestamp())
          )
    ) THEN
        RAISE EXCEPTION 'No se puede cambiar la sala mientras tenga ventas o reservas futuras';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_proteger_sala_con_ventas
BEFORE UPDATE OR DELETE ON sala
FOR EACH ROW EXECUTE FUNCTION proteger_sala_con_ventas();

CREATE FUNCTION proteger_asiento_con_ventas() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_id_asiento integer;
BEGIN
    v_id_asiento := OLD.id_asiento;
    IF EXISTS (
        SELECT 1 FROM estado_asiento_funcion e
        JOIN funcion f ON f.id_funcion = e.id_funcion
        WHERE e.id_asiento = v_id_asiento
          AND f.estado_funcion = 'programada'
          AND f.fecha_hora_inicio > clock_timestamp()
          AND (e.estado = 'bloqueado' AND e.expiracion_bloqueo > clock_timestamp()
               OR EXISTS (SELECT 1 FROM boleto b WHERE b.id_funcion = e.id_funcion
                          AND b.id_asiento = e.id_asiento AND b.estado_boleto <> 'anulado')
               OR (TG_OP = 'UPDATE' AND NEW.id_sala IS DISTINCT FROM OLD.id_sala))
    ) THEN
        RAISE EXCEPTION 'No se puede cambiar el asiento mientras tenga ventas o reservas futuras';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_proteger_asiento_con_ventas
BEFORE UPDATE OR DELETE ON asiento
FOR EACH ROW EXECUTE FUNCTION proteger_asiento_con_ventas();
