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