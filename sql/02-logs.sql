CREATE FUNCTION rechazar_cambio_en_bitacora() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Las bitácoras son de solo inserción';
END;
$$;

CREATE TRIGGER trg_transaccion_log_append_only
BEFORE UPDATE OR DELETE ON transaccion_log
FOR EACH ROW EXECUTE FUNCTION rechazar_cambio_en_bitacora();

CREATE TRIGGER trg_asiento_auditoria_append_only
BEFORE UPDATE OR DELETE ON asiento_auditoria_log
FOR EACH ROW EXECUTE FUNCTION rechazar_cambio_en_bitacora();

CREATE TRIGGER trg_acceso_puerta_append_only
BEFORE UPDATE OR DELETE ON acceso_puerta_log
FOR EACH ROW EXECUTE FUNCTION rechazar_cambio_en_bitacora();

CREATE TRIGGER trg_admin_audit_append_only
BEFORE UPDATE OR DELETE ON admin_operacion_audit
FOR EACH ROW EXECUTE FUNCTION rechazar_cambio_en_bitacora();


-- 2. Cada cambio de estado de asiento deja huella de bloqueo, expiración, liberación o venta en su auditoría.
CREATE FUNCTION auditar_estado_asiento() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_evento varchar(30);
    v_usuario bigint;
    v_expira timestamptz;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.estado = 'bloqueado' THEN
            v_evento := 'bloqueo';
        ELSE
            RETURN NEW;
        END IF;
        v_usuario := NEW.id_usuario;
        v_expira := NEW.expiracion_bloqueo;
    ELSIF OLD.estado IS DISTINCT FROM NEW.estado
       OR OLD.id_usuario IS DISTINCT FROM NEW.id_usuario
       OR OLD.expiracion_bloqueo IS DISTINCT FROM NEW.expiracion_bloqueo THEN
        IF OLD.estado = 'bloqueado' AND OLD.expiracion_bloqueo <= clock_timestamp()
           AND NEW.estado = 'bloqueado' THEN
            INSERT INTO asiento_auditoria_log
                (id_funcion, id_asiento, id_usuario, evento, expira_en)
            VALUES (OLD.id_funcion, OLD.id_asiento, OLD.id_usuario, 'expiracion', OLD.expiracion_bloqueo);
        END IF;
        IF NEW.estado = 'bloqueado' THEN
            v_evento := 'bloqueo';
            v_usuario := NEW.id_usuario;
            v_expira := NEW.expiracion_bloqueo;
        ELSIF OLD.estado = 'bloqueado' AND NEW.estado = 'ocupado' THEN
            v_evento := 'venta';
            v_usuario := OLD.id_usuario;
            v_expira := OLD.expiracion_bloqueo;
        ELSIF OLD.estado = 'bloqueado' AND NEW.estado = 'disponible' THEN
            v_evento := CASE WHEN OLD.expiracion_bloqueo <= clock_timestamp()
                             THEN 'expiracion' ELSE 'liberacion' END;
            v_usuario := OLD.id_usuario;
            v_expira := OLD.expiracion_bloqueo;
        ELSE
            RETURN NEW;
        END IF;
    ELSE
        RETURN NEW;
    END IF;

    INSERT INTO asiento_auditoria_log
        (id_funcion, id_asiento, id_usuario, evento, expira_en)
    VALUES (NEW.id_funcion, NEW.id_asiento, v_usuario, v_evento, v_expira);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auditar_estado_asiento
AFTER INSERT OR UPDATE ON estado_asiento_funcion
FOR EACH ROW EXECUTE FUNCTION auditar_estado_asiento();


-- 3. Registro automático de transacciones de pago en el log financiero.
CREATE FUNCTION registrar_pago_y_actualizar_orden() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_moneda varchar(3);
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.estado_pago = NEW.estado_pago THEN
        RETURN NEW;
    END IF;
    IF NEW.estado_pago = 'aprobado' THEN
        UPDATE orden SET estado_orden = 'pagada'
        WHERE id_orden = NEW.id_orden AND estado_orden <> 'anulada';
    END IF;
    SELECT moneda INTO v_moneda FROM orden WHERE id_orden = NEW.id_orden;
    INSERT INTO transaccion_log
        (id_orden, id_pago, evento, monto, moneda, referencia_pasarela, detalle)
    VALUES
        (NEW.id_orden, NEW.id_pago, 'pago_' || NEW.estado_pago, NEW.monto,
         v_moneda, NEW.token_pasarela, jsonb_build_object('metodo_pago', NEW.id_metodo_pago));
    
    IF NEW.estado_pago = 'aprobado' AND EXISTS (
        SELECT 1 FROM metodo_pago m
        WHERE m.id_metodo_pago = NEW.id_metodo_pago AND m.nombre_metodo_pago = 'cortesia'
    ) THEN
        INSERT INTO admin_operacion_audit
            (id_usuario, id_rol, ip_origen, operacion, entidad, id_entidad,
             valor_anterior, valor_nuevo)
        SELECT o.vendedor_asociado, u.id_rol, '127.0.0.1', 'cortesia',
               'orden', o.id_orden::text, NULL,
               jsonb_build_object('id_orden', o.id_orden, 'total', o.total, 'moneda', o.moneda)
        FROM orden o JOIN usuario u ON u.id_usuario = o.vendedor_asociado
        WHERE o.id_orden = NEW.id_orden;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_registrar_pago_y_actualizar_orden
AFTER INSERT OR UPDATE ON pago
FOR EACH ROW EXECUTE FUNCTION registrar_pago_y_actualizar_orden();


-- 4. Registro de emisión de boletos en la bitácora transaccional.
CREATE FUNCTION actualizar_asiento_por_boleto() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_moneda varchar(3);
    v_pago bigint;
BEGIN
    UPDATE estado_asiento_funcion
    SET estado = 'ocupado', id_usuario = NULL, expiracion_bloqueo = NULL
    WHERE id_funcion = NEW.id_funcion AND id_asiento = NEW.id_asiento;
    
    SELECT moneda INTO v_moneda FROM orden WHERE id_orden = NEW.id_orden;
    SELECT id_pago INTO v_pago FROM pago
    WHERE id_orden = NEW.id_orden AND estado_pago = 'aprobado';
    
    INSERT INTO transaccion_log
        (id_orden, id_pago, evento, monto, moneda, detalle)
    VALUES
        (NEW.id_orden, v_pago, 'boleto_emitido', NEW.precio_final, v_moneda,
         jsonb_build_object('id_boleto', NEW.id_boleto, 'id_funcion', NEW.id_funcion,
                            'id_asiento', NEW.id_asiento));
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_actualizar_asiento_por_boleto
AFTER INSERT ON boleto
FOR EACH ROW EXECUTE FUNCTION actualizar_asiento_por_boleto();


-- 5. Auditoría y registro de reembolsos y excepciones forzadas.
CREATE FUNCTION aplicar_reembolso() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_moneda varchar(3);
    v_rol smallint;
BEGIN
    IF NEW.id_boleto IS NOT NULL THEN
        UPDATE boleto SET estado_boleto = 'anulado'
        WHERE id_boleto = NEW.id_boleto;
    END IF;
    
    SELECT o.moneda INTO v_moneda
    FROM pago p JOIN orden o USING (id_orden)
    WHERE p.id_pago = NEW.id_pago;
    
    INSERT INTO transaccion_log
        (id_orden, id_pago, evento, monto, moneda, detalle)
    SELECT p.id_orden, NEW.id_pago, 'reembolso', NEW.monto_reembolso, v_moneda,
           jsonb_build_object('id_reembolso', NEW.id_reembolso, 'motivo', NEW.motivo)
    FROM pago p WHERE p.id_pago = NEW.id_pago;
    
    IF NEW.forzado THEN
        SELECT id_rol INTO v_rol FROM usuario WHERE id_usuario = NEW.id_usuario_autoriza;
        INSERT INTO admin_operacion_audit
            (id_usuario, id_rol, ip_origen, operacion, entidad, id_entidad,
             valor_anterior, valor_nuevo)
        VALUES
            (NEW.id_usuario_autoriza, v_rol, '127.0.0.1', 'reembolso_forzado',
             'reembolso', NEW.id_reembolso::text, NULL,
             jsonb_build_object('id_boleto', NEW.id_boleto, 'id_pago', NEW.id_pago,
                                'monto', NEW.monto_reembolso, 'motivo', NEW.motivo));
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_aplicar_reembolso
AFTER INSERT ON reembolso
FOR EACH ROW EXECUTE FUNCTION aplicar_reembolso();