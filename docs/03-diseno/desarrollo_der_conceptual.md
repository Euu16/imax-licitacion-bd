# Diseño Conceptual de la Base de Datos

**Proyecto:** Licitación para el Ecosistema Digital de Cines IMAX
**Fase:** 3, Diseño de la Base de Datos (nivel conceptual)

El diseño conceptual describe **qué información maneja el negocio y cómo se relaciona**, sin comprometerse con tipos de dato, llaves ni tablas físicas. Por eso aquí las relaciones de muchos a muchos aparecen tal como son en el negocio. El diseño lógico (`der.md`) las convierte en tablas con llaves, y el físico (`01_schema.sql`) las implementa en PostgreSQL.


---

## 1. Detalles antes de diagrama conceptual
Antes de generar esta parte, se deben tomar en cuenta algunos detalles como

|Detalle|Explicación|
|  ---  |   ---     |
|Cardinalidad entre usuario y orden| 1:N, pues un usuario puede tener varias ordenes, pero cada orden pertenece a un usuario|
|Ventas presenciales en taquilla (cuando cliente no tiene cuenta) y relación de vendedor|Recordar que ventas presenciales en taquilla o cortesías cuando un cliente no tiene cuenta, se utilizará un usuario genérico con un rol de mostrador, mantienendo que id_usuario no será nulo. Además, la relación del vendedor se ajusta exclusivamente a quien reigstra venta de mostrador o cortesía|
|`franja horaria` como entidad propia| en cuanto a tarifa, no es solo una N:M directa, sino que esta misma depende de la zona,tipo de entrada, dia de la semana, franja horaria y el país. Lo brindado permite evitar solapamientos y que hayan parámetros globales por moneda y región|
|Unificación de nombres| se unifican nombres en documentación conceptual y lógica utilizando `estado_asiento_funcion` y columna `vendedor_asociado` para evitar confusiones de nombres viejos|
|LLaves foráneas compuestas en entidad `boleto`| en este archivo se deja en claro que boleto tiene 2 validaciones o dependencias claves: a- (id_orden,id_funcion) que asegura coherencia con la compra, b-(id_funcion,id_asiento)  para referenciarse directamente del inventario en `estado_asiento_funcion` (de manera lógica, el boleto nace y se verifica sonre un asiento que fue bloqueado para una función específica)|
|caso de entidad `ciudad`| Esta entidad existe y se relaciona con la entidad `pais` para evitar repetir texto de ubicación y normalizar correctamente jerarquía geográfica junto a `cine`|
|Inclusión de entidades Huérfanas/Parámetros| con entidades huerfanas en este caso se refier y e a que basicamente estas dependen de info de ellas relacionada con otras tablas. En este caso se agregan entidades `franja_horaria` y `configuracion`.La primera ya fue explicada, mientras que la segunda sirve para configurar distintos parámetros como minutos de bloqueo,limites de asiento, tolerancias, limites para reembolsos, etc|
|Reembolso con Boleto Opcional| aqui se deja claro que un reembolso no debe tener una relación obligatoria con el boleto,pues pueden haber casos especiales de pagos aprobados y demás|
|Regla para Asiento y la Sala| se usa como regla de validación un trigger o procedimiento almacenado lo siguiente: 
un asiento seleccionado en una función específica debe pertenecer obligatoriamente a la sala en la cuál se va a programar la función.|

## 2.Resumen de entidades del proyecto

|Contexto| Entidades seleccionadas|
|  ---   |          ---           |
|Ubicación y estructura| `pais`,`ciudad`,`cine`,`sala`,`zona`,`asiento`,`dispositivo_puerta`,`configuracion` |
|cartelera y programacion| `pelicula`,`genero`,`pelicula_genero`,`funcion`,`franja_horaria`|
|precios y promociones| `tipo_entrada`,`tarifa`,`promocion`|
|privacidad, seguridad y labores(accesos)|`rol`,`modulo`,`rol_permiso`,`usuario`|
|transacciones y ventas| `orden`,`pago`,`metodo_pago`,`boleto`,`reembolso`|
|Bitácoras para auditoria|`transaccion_log`,`asiento_auditoria_log`,`acceso_puerta_log`,`admin_operacion_audit`|