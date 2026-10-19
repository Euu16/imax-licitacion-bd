# Diseño Conceptual de la Base de Datos

**Proyecto:** Licitación para el Ecosistema Digital de Cines IMAX
**Fase:** 3, Diseño de la Base de Datos (nivel conceptual)

El diseño conceptual describe **qué información maneja el negocio y cómo se relaciona**, sin comprometerse con tipos de dato, llaves ni tablas físicas. Por eso aquí las relaciones de muchos a muchos aparecen tal como son en el negocio. El diseño lógico (`der.md`) las convierte en tablas con llaves, y el físico (`01_schema.sql`) las implementa en PostgreSQL.


---

## 1. Diagrama Entidad-Relación conceptual
Antes de generar esta parte, se deben tomar en cuenta algunos detalles como

|Detalle|Explicación|
|  ---  |   ---     |
|Cardinalidad entre usuario y orden| 1:N, pues un usuario puede tener varias ordenes, pero cada orden pertenece a un usuario|
|Ventas presenciales en taquilla (cuando cliente no tiene cuenta) y relación de vendedor|Recordar que ventas presenciales en taquilla o cortesías cuando un cliente no tiene cuenta, se utilizará un usuario genérico con un rol de mostrador, mantienendo que id_usuario no será nulo. Además, la relación del vendedor se ajusta exclusivamente a quien reigstra venta de mostrador o cortesía|
|`franja horaria` como entidad propia| en cuanto a tarifa, no es solo una N:M directa, sino que esta misma depende de la zona,tipo de entrada, dia de la semana, franja horaria y el país. Lo brindado permite evitar solapamientos y que hayan parámetros globales por moneda y región|
|Unificación de nombres| se unifican nombres en documentación conceptual y lógica utilizando `estado_asiento_funcion` y columna `vendedor_asociado` para evitar confusiones de nombres viejos|
|LLaves foráneas compuestas en entidad `boleto`| en este archivo se deja en claro que boleto tiene 2 validaciones o dependencias claves: a- (id_orden,id_funcion) que asegura coherencia con la compra, b-(id_funcion,id_asiento)  para referenciarse directamente del inventario en `estado_asiento_funcion` (de manera lógica, el boleto nace y se verifica sonre un asiento que fue bloqueado para una función específica)|
