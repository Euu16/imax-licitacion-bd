DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE pais(
    id_pais SERIAL PRIMARY KEY,
    nombre VARCHAR(110) NOT NULL UNIQUE,
    moneda VARCHAR(3) NOT NULL CHECK (moneda ~ '^[A-Z]{3}$')
);

CREATE TABLE rol(
    id_rol SERIAL PRIMARY KEY,
    nombre_rol VARCHAR(50) NOT NULL UNIQUE,
    descripcion VARCHAR(150) NOT NULL
);

CREATE TABLE modulo(
    id_modulo SERIAL PRIMARY KEY,
    nombre_modulo VARCHAR(150) NOT NULL UNIQUE
);

CREATE TABLE metodo_pago(
    id_metodo_pago SERIAL PRIMARY KEY,
    nombre_metodo_pago VARCHAR(45) NOT NULL UNIQUE
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
    cargo_servicio_porcentaje NUMERIC(10,2) NOT NULL CHECK(cargo_servicio_porcentaje BETWEEN 0 AND 100),
    CONSTRAINT check_fila_unica CHECK(id_configuracion=1)
    --solo una fila en configuracion
);

CREATE TABLE genero(
    id_genero SERIAL PRIMARY KEY,
    nombre_genero VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE franja_horaria(
    id_franja SERIAL PRIMARY KEY,
    nombre_franja VARCHAR(50) NOT NULL UNIQUE,
    hora_inicio TIME NOT NULL,
    hora_fin TIME NOT NULL,
    --se debe agregar una restriccion para comprobar que la hora de finalizacion de esa franja sea mayor a la hora de inicio
    CONSTRAINT comprobacion_horas_en_franja CHECK(hora_fin>hora_inicio)
    --las columnas que llevan TIMESTAMPTZ se adaptan a la hora local, es decir UTC
);

CREATE TABLE tipo_entrada(
    id_tipo_entrada SERIAL PRIMARY KEY,
    nombre_tipo_de_entrada VARCHAR(40) NOT NULL UNIQUE, 
    --especifica si es para adulto, niño,etc
    requiere_credencial BOOLEAN NOT NULL
);

CREATE TABLE zona(
    id_zona SERIAL PRIMARY KEY,
    nombre_zona VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE promocion(
    id_promocion SERIAL PRIMARY KEY,
    nombre_promocion VARCHAR(110) NOT NULL,
    tipo_regla VARCHAR(100) NOT NULL CHECK(tipo_regla IN ('2x1', 'descuento_dia')),
    descuento_porcentaje NUMERIC(10,2) CHECK(descuento_porcentaje BETWEEN 0 AND 100),
    -- restriccion de dominio del descuento_porcentaje
    condicion_minima INT NOT NULL CHECK(condicion_minima > 0),
    dia_semana INT CHECK(dia_semana BETWEEN 0 AND 6),
    --este check es para comprobar que no se salga del rango de 7 dias de la semana, donde 0=domingo,1=lunes, etc.
    promocion_esta_activa BOOLEAN DEFAULT TRUE,
    --basicamente decimos que por defecto una promocion si esta activa
    CONSTRAINT verificacion_reglas_de_promocion CHECK(
        (tipo_regla='2x1' AND dia_semana IS NULL AND descuento_porcentaje IS NULL) OR 
        (tipo_regla='descuento_dia' AND dia_semana IS NOT NULL AND descuento_porcentaje IS NOT NULL)
    )
    --este constraint verifica que si hay 2x1, entonces no referencia a un dia, pues se puede dar en varios
    --ademas en descuento_dia obligatoriamente se le debe asociar un dia y un descuento
);

CREATE TABLE ciudad(
    id_ciudad SERIAL PRIMARY KEY,
    id_pais INT NOT NULL, 
    --es un FK
    nombre_ciudad VARCHAR(150) NOT NULL,
    CONSTRAINT fk_ciudad FOREIGN KEY(id_pais) REFERENCES pais(id_pais),
    CONSTRAINT unicidad_ciudad_de_pais UNIQUE(id_pais,nombre_ciudad)
    --esta restriccion permite que esa combinacion no se repita y que cada ciudad en un pais sea unica con su nombre y id simultaneamente
);

CREATE TABLE usuario(
    id_usuario SERIAL PRIMARY KEY,
    id_rol INT NOT NULL,
    nombre_usuario VARCHAR(85) NOT NULL,
    correo VARCHAR(120) NOT NULL UNIQUE,
    telefono VARCHAR(20) UNIQUE,
    contrasena_hash VARCHAR(200) NOT NULL,
    --quitando ñ y poniendo n 
    usuario_esta_activo BOOLEAN DEFAULT TRUE,
    fecha_registro TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_usuario FOREIGN KEY(id_rol) REFERENCES rol(id_rol)
);

CREATE TABLE pelicula(
    id_pelicula SERIAL PRIMARY KEY,
    titulo VARCHAR(300) NOT NULL,
    sinopsis TEXT NOT NULL,
    clasificacion_edad VARCHAR(30) NOT NULL,
    duracion_minutos INT NOT NULL CHECK(duracion_minutos>0),
    --comprobacion de dominio de duracion_minutos
    poster_url TEXT NOT NULL,
    pelicula_esta_activa BOOLEAN DEFAULT TRUE
);

CREATE TABLE cine(
    id_cine SERIAL PRIMARY KEY,
    id_ciudad INT NOT NULL, 
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
    CONSTRAINT verificacion_permisos_para_rol CHECK(nivel in('ninguno','lectura','escritura','ejecucion','total'))
    --se quitan tildes
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

CREATE TABLE asiento(
    id_asiento SERIAL PRIMARY KEY,
    id_sala INT NOT NULL,
    id_zona INT NOT NULL,
    fila VARCHAR(8) NOT NULL,
    numero INT NOT NULL CHECK(numero>0),
    CONSTRAINT fk_id_sala_en_asiento FOREIGN KEY (id_sala) REFERENCES sala(id_sala),
    CONSTRAINT fk_id_zona FOREIGN KEY(id_zona) REFERENCES zona(id_zona),
    CONSTRAINT unicidad_asiento_sala UNIQUE(id_sala,fila,numero)
);
 
CREATE TABLE dispositivo_puerta(
    id_dispositivo SERIAL PRIMARY KEY,
    id_sala INT NOT NULL,
    nombre_dispositivo VARCHAR(60) NOT NULL,
    CONSTRAINT fk_id_sala_en_dispositivo FOREIGN KEY(id_sala) REFERENCES sala(id_sala),
    CONSTRAINT unicidad_dispositivo_sala UNIQUE(id_sala, nombre_dispositivo)
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
    CONSTRAINT fk_sala_en_funcion FOREIGN KEY (id_sala) REFERENCES sala(id_sala),
    CONSTRAINT evitar_traslape_en_sala EXCLUDE USING gist(
        id_sala WITH =,
        tstzrange(fecha_hora_inicio, fecha_hora_fin, '[)') WITH &&
    ) WHERE (estado_funcion = 'programada')
    --basicamente con esa linea se pone una restriccion para que no haya solapamiento
    --gist es un indice (Generalized Search Tree)
);
CREATE INDEX ix_funcion_sala_horario ON funcion (id_sala, fecha_hora_inicio, fecha_hora_fin)
    WHERE estado_funcion = 'programada';

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
    CONSTRAINT verificacion_logica_en_bloqueo CHECK(
        (estado = 'bloqueado' AND id_usuario IS NOT NULL AND expiracion_bloqueo IS NOT NULL) OR
        (estado IN ('disponible', 'ocupado') AND id_usuario IS NULL AND expiracion_bloqueo IS NULL)
    )
);

CREATE TABLE orden (
    id_orden SERIAL PRIMARY KEY,
    id_usuario INT NOT NULL, 
    id_funcion INT NOT NULL,
    id_promocion INT, -- Opcional
    canal VARCHAR(30) NOT NULL,
    estado_orden VARCHAR(30) NOT NULL,
    subtotal NUMERIC(10,2) NOT NULL CHECK(subtotal>=0),
    descuento NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK(descuento>=0),
    cargo_servicio NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK(cargo_servicio>=0),
    total NUMERIC(10,2) NOT NULL CHECK(total>=0),
    fecha_creacion TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    vendedor_asociado INT, -- FK nula para web/app, obligatoria si es taquilla/administrativo
    moneda VARCHAR(3) NOT NULL CHECK (moneda ~ '^[A-Z]{3}$'),

    --constraints de esta tabla
    CONSTRAINT fk_usuario_en_orden FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario),
    CONSTRAINT fk_funcion_en_orden FOREIGN KEY (id_funcion) REFERENCES funcion(id_funcion),
    CONSTRAINT fk_promocion_en_orden FOREIGN KEY (id_promocion) REFERENCES promocion(id_promocion),
    CONSTRAINT fk_de_vendedor_relacionado_a_usuario FOREIGN KEY (vendedor_asociado) REFERENCES usuario(id_usuario),
    CONSTRAINT chk_canal CHECK (canal IN ('web', 'app', 'taquilla', 'administrativo')),
    CONSTRAINT chk_estado_orden CHECK (estado_orden IN ('pendiente', 'pagada', 'fallida', 'anulada')),

    CONSTRAINT verificacion_vendedor_por_canal CHECK(
        (canal IN('web','app') AND vendedor_asociado IS NULL) OR
        --tiene sentido, porque si es en uno de esos canales, entonces no se ocupa un vendedor
        (canal IN('taquilla','administrativo') AND vendedor_asociado IS NOT NULL)
    ),
    --aqui tambien tiene sentido, pues para esos canales, se necesita el vendedor
    CONSTRAINT check_de_total_orden CHECK(total = subtotal - descuento + cargo_servicio),
    CONSTRAINT check_descuento_valido CHECK(descuento <= subtotal),
    --para comprobar que se base en esos cálculos
    UNIQUE(id_orden,id_funcion)
);

CREATE TABLE pago(
    id_pago SERIAL PRIMARY KEY,
    id_orden INT NOT NULL,
    id_metodo_pago INT NOT NULL,
    estado_pago VARCHAR(30) NOT NULL,
    monto NUMERIC(10,2) NOT NULL CHECK(monto>=0),
    token_pasarela VARCHAR(255), -- Nulo si es efectivo o cortesía
    ultimos4 VARCHAR(4) CHECK (ultimos4 IS NULL OR ultimos4 ~ '^[0-9]{4}$'),          -- Nulo si es efectivo o cortesía
    fecha_operacion TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pago_en_orden FOREIGN KEY (id_orden) REFERENCES orden(id_orden),
    CONSTRAINT fk_metodo_de_pago_en_orden FOREIGN KEY (id_metodo_pago) REFERENCES metodo_pago(id_metodo_pago),
    CONSTRAINT chk_estado_pago CHECK (estado_pago IN ('aprobado', 'rechazado', 'pendiente'))
);
CREATE UNIQUE INDEX uq_pago_aprobado_por_orden ON pago (id_orden) WHERE estado_pago = 'aprobado';

CREATE TABLE boleto(
    id_boleto SERIAL PRIMARY KEY,
    id_orden INT NOT NULL,
    id_funcion INT NOT NULL,
    id_asiento INT NOT NULL,
    id_tipo_entrada INT NOT NULL,
    precio_final NUMERIC(10,2) NOT NULL CHECK(precio_final >= 0),
    codigo_qr UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    --esto es para generar un qr random
    estado_boleto VARCHAR(30) NOT NULL DEFAULT 'emitido',
    origen VARCHAR(30) NOT NULL,
    fecha_emision TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    fecha_uso TIMESTAMPTZ,
    -- Las dos FK compuestas críticas de nuestro diseño:
    CONSTRAINT fk_boleto_orden_funcion FOREIGN KEY (id_orden, id_funcion) REFERENCES orden(id_orden, id_funcion),
    CONSTRAINT fk_boleto_asiento_funcion FOREIGN KEY (id_funcion, id_asiento) REFERENCES estado_asiento_funcion(id_funcion, id_asiento),
    CONSTRAINT fk_tipo_entrada_en_boleto FOREIGN KEY (id_tipo_entrada) REFERENCES tipo_entrada(id_tipo_entrada),
    CONSTRAINT chk_estado_boleto CHECK (estado_boleto IN ('emitido', 'usado', 'anulado')),
    CONSTRAINT chk_origen_boleto CHECK (origen IN ('online', 'taquilla', 'cortesia')),
    CONSTRAINT chk_fecha_uso CHECK (
        (estado_boleto = 'usado' AND fecha_uso IS NOT NULL) OR
        (estado_boleto <> 'usado' AND fecha_uso IS NULL)
    )
);

CREATE UNIQUE INDEX indice_unico_boleto_activo
--esa linea garantiza que las columnas q se vayan a especificar sean unicas 
ON boleto (id_funcion,id_asiento)
--evita que haya doble venta de un mismo asiento, y si se anula, pues que quede libre de nuevo, asi otro cliente puede seleccionar ese asiento
WHERE estado_boleto <> 'anulado';

CREATE TABLE reembolso(
    id_reembolso SERIAL PRIMARY KEY,
    id_boleto INT,
    --este se deja con posibilidad de ser nulo,pues si el pago es aprobado puede ser nulo despues de que tiempo de bloqueo terminó y ya se vendió el asiento a otra persona
    --aqui ya no existe boleto pero si se debe devolver dinero
    id_pago INT NOT NULL,
    id_usuario INT NOT NULL,
    monto_reembolso NUMERIC(10,2) NOT NULL CHECK(monto_reembolso > 0),
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
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT now(),
    id_orden INT,
    id_pago INT,
    evento VARCHAR(60) NOT NULL,
    monto NUMERIC(10,2),
    impuesto NUMERIC(10,2),
    moneda VARCHAR(3),
    referencia_pasarela VARCHAR(240),
    detalle JSONB NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY(id_log,fecha_hora)
);

CREATE TABLE asiento_auditoria_log (
    id_log SERIAL,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT now(),
    id_funcion INT,
    id_asiento INT,
    id_usuario INT,
    evento VARCHAR(50) NOT NULL,
    expira_en TIMESTAMPTZ,
    PRIMARY KEY (id_log, fecha_hora)
);

CREATE TABLE acceso_puerta_log(
    id_log SERIAL,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT now(),
    id_boleto INT,
    id_dispositivo INT,
    resultado VARCHAR(40) NOT NULL,
    motivo VARCHAR(250),
    PRIMARY KEY (id_log,fecha_hora),
    CONSTRAINT chk_revision_resultado_acceso CHECK (resultado IN ('exitoso','duplicado','rechazado_horario','rechazado_credencial','funcion_incorrecta','invalido'))
);

CREATE TABLE admin_operacion_audit (
    id_log SERIAL,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT now(),
    id_usuario INT NOT NULL,
    id_rol INT NOT NULL,
    ip_origen VARCHAR(45) NOT NULL,
    operacion VARCHAR(50) NOT NULL,
    entidad VARCHAR(50) NOT NULL,
    id_entidad INT,
    valor_anterior JSONB,
    valor_nuevo JSONB,
    PRIMARY KEY (id_log, fecha_hora)
);


--LOGS

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




--roles del sistema

INSERT INTO configuracion (id_configuracion,bloqueo_minutos,max_asientos_en_orden,tolerancia_antes_min,tolerancia_despues_min,reembolso_horas_antes,cargo_servicio_porcentaje) VALUES (1,10,6,15,15,24,0);
COMMENT ON COLUMN configuracion.cargo_servicio_porcentaje IS 'Valor inicial neutro 0; definir el porcentaje comercial antes de habilitar ventas.';

-- Creación de roles para el sistema y vamos a basarnos en RBAC
--esto se hace por medio de inserts
INSERT INTO rol (nombre_rol, descripcion)
 VALUES
    ('cliente', 'Cliente con cuenta'),
    ('taquillero', 'Personal de taquilla'),
    ('operador de sala', 'Personal de operación de sala'),
    ('contador', 'Personal de contabilidad'),
    ('administrador/gerente', 'Administración y gerencia'),
    ('cliente_mostrador', 'Identidad genérica para ventas presenciales sin cuenta');

INSERT INTO metodo_pago (nombre_metodo_pago) 
VALUES
    ('tarjeta'), 
    ('paypal'), 
    ('billetera'), 
    ('transferencia'), 
    ('efectivo'), 
    ('cortesia');


INSERT INTO tipo_entrada (nombre_tipo_de_entrada, requiere_credencial) 
VALUES
    ('adulto', false), 
    ('nino', false), 
    ('tercera_edad', true), 
    ('estudiante', true);

--creacion del usuario generio

-- correo usa cierto dominio que no tiene ruta y .invalid y la constraseña hash no va a dejar hacer el inicio de sesion
INSERT INTO usuario (id_rol, nombre_usuario, correo, contrasena_hash)
SELECT id_rol, 'Cliente mostrador', 'cliente_mostrador@imax.invalid', '!NO_PASSWORD!'
FROM rol WHERE nombre_rol = 'cliente_mostrador';






--procedimientos del sistema

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


-- Liberacion manual de los bloqueos activos que pertenecen al usuario.
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



