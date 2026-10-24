INSERT INTO configuracion (id_configuracion) VALUES (1);
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