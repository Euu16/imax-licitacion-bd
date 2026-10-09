# Fase 2: Recopilación y Análisis de Requisitos

**Proyecto:** Licitación para el Ecosistema Digital de Cines IMAX
**Curso:** Bases de Datos
**Ubicación en el repo:** `docs/02-requisitos/requisitos.md`

---

## 1. Requisitos funcionales (RF)

| ID | Requisito | Reglas de negocio |
|---|---|---|
| RF-01 | Mostrar la cartelera de funciones activas y futuras, con título, sinopsis, clasificación de edad, horarios y ubicación exacta de la sala. | RN-01, RN-02 |
| RF-02 | Filtrar la cartelera por ubicación, fecha y género. | RN-01 |
| RF-03 | Mostrar el mapa de la sala con el estado actualizado de cada asiento (disponible, ocupado, reservado, bloqueado). | RN-03 |
| RF-04 | Bloquear un asiento durante 2 minutos al seleccionarlo y liberarlo automáticamente si el pago no se completa. | RN-05 |
| RF-05 | Limitar la cantidad de asientos por transacción (valor propuesto: 6, ver supuesto S-05). | RN-04 |
| RF-06 | Permitir elegir el tipo de entrada (adulto, niño, tercera edad, estudiante) y aplicar promociones (2x1) de forma automática. | RN-06, RN-07 |
| RF-07 | Calcular el total exacto: tarifas, descuentos y cargos por servicio. | RN-08 |
| RF-08 | Simular el pago; si falla, cancelar la transacción y liberar de inmediato los asientos. | RN-09, RN-10 |
| RF-09 | Emitir un código QR único solo después de un pago aprobado y dejarlo disponible en el perfil del usuario. | RN-11, RN-12, RN-13 |
| RF-10 | Validar el QR en puerta: una sola vez, función y horario correctos, dentro de la tolerancia (30 min antes a 15 min después del inicio). Un segundo intento muestra "Entrada ya utilizada". | RN-06, RN-14, RN-15, RN-16 |
| RF-11 | Gestionar incidencias de acceso (QR ilegible, clientes rezagados, errores de validación). | RN-15, RN-16, RN-20 |
| RF-12 | CRUD de películas, salas, asientos, funciones y matriz de tarifas, evitando traslapes de horario y bloqueando cambios en salas con ventas activas. | RN-18 |
| RF-13 | Anular entradas y reembolsar solo dentro de la política (hasta 2 horas antes de la función), liberando el asiento. | RN-19 |
| RF-14 | Dashboard con ocupación, ingresos por función, métodos de pago y tendencias de compra. | Consultas analíticas |
| RF-15 | Control de acceso por roles (RBAC) con 5 perfiles según la matriz de privilegio mínimo: cliente, taquillero, operador de sala, contador y administrador/gerente. | RN-17 |
| RF-16 | Registrar bitácoras de auditoría: transacciones, bloqueos de asientos, accesos en puerta y operaciones administrativas manuales. | RN-20 |

---

## 2. Requisitos no funcionales (RNF)

| ID | Categoría | Requisito |
|---|---|---|
| RNF-01 | Disponibilidad | SLA de 99.99% (aprox. 52 minutos de caída al año). |
| RNF-02 | Recuperación | RPO menor o igual a 5 segundos (ideal 0) y RTO < 5 minutos. |
| RNF-03 | Integridad | Transacciones ACID y restricción de unicidad `(funcion_id, asiento_id)` que impida físicamente la doble venta. |
| RNF-04 | Rendimiento | Consulta del mapa de asientos con p95 < 200 ms y reserva de asiento con p95 < 500 ms (supuesto S-06). |
| RNF-05 | Escalabilidad | Soportar 50,000 TPS durante los primeros 10 minutos de un estreno mundial. |
| RNF-06 | Seguridad | Cumplimiento PCI-DSS: no almacenar número completo de tarjeta ni CVV; solo un token de la pasarela. |
| RNF-07 | Seguridad | Cifrado en tránsito (TLS) y en reposo; contraseñas almacenadas con hash. |
| RNF-08 | Auditoría | Logs inalterables, con retención mínima de 5 años y particionamiento por fecha. |
| RNF-09 | Privacidad | Cumplimiento de normativas de protección de datos personales (GDPR/CCPA, a nivel de mención). |
| RNF-10 | Operación | Backups automáticos y plan de recuperación ante desastres documentado. |
| RNF-11 | Usabilidad | Interfaz web y móvil de carácter funcional (la GUI es de soporte para demostrar los flujos). |

---

## 3. Dimensionamiento de datos

### 3.1 Datos dados por el enunciado

| Dato | Valor |
|---|---|
| Usuarios concurrentes en el estreno | 8,000,000 |
| TPS pico (compras + lecturas), primeros 10 min | 50,000 |
| Títulos activos | 500 |
| Salas a nivel mundial | 1,500 |
| Boletos vendidos al mes | 15,000,000 |
| Retención de logs y auditoría | 5 años mínimo |

### 3.2 Carga pico (estreno mundial)

| Dato | Cálculo | Resultado |
|---|---|---|
| Operaciones en la ventana pico | 50,000 × 600 s | 30,000,000 en 10 min |
| Lecturas (80%, S-02) | 50,000 × 0.8 | 40,000 / s |
| Escrituras (20%, S-02) | 50,000 × 0.2 | 10,000 / s |

> Los 8 millones de usuarios concurrentes no equivalen a 8 millones de conexiones a la base de datos. La arquitectura propuesta usa sala de espera virtual, caché para el mapa de asientos y pool de conexiones, de modo que a la BD llegan las escrituras (aproximadamente 10,000/s) y solo una fracción de las lecturas.

### 3.3 Carga promedio (operación normal)

| Dato | Cálculo | Resultado |
|---|---|---|
| Boletos por día | 15,000,000 / 30 | 500,000 |
| Boletos por segundo (promedio) | 15,000,000 / 2,592,000 s | Aprox 5.8 / s |
| Relación pico / promedio | 50,000 / 5.8 | Aprox 8,600× |

Esta relación justifica el **autoescalado en la nube**: pagar todo el año por capacidad de estreno no es razonable.

### 3.4 Inventario físico

| Dato | Cálculo | Resultado |
|---|---|---|
| Capacidad promedio por sala (S-01) | Supuesto | 300 asientos |
| Asientos físicos totales | 1,500 × 300 | 450,000 |
| Funciones por sala al día (S-01) | Supuesto | 5 |
| Funciones al día | 1,500 × 5 | 7,500 |
| Funciones al mes | 7,500 × 30 | 225,000 |
| Boletos promedio por función | 15,000,000 / 225,000 | Aprox 67 |
| Ocupación promedio implícita | 67 / 300 | Aprox 22% |


### 3.5 Usuarios registrados

| Dato | Valor |
|---|---|
| Cuentas de usuario registradas (S-03) | 20,000,000 |
| Relación con concurrentes en el pico | 8M / 20M = 40% de las cuentas conectadas a la vez |

### 3.6 Registros de log por mes (insumo para el cálculo de almacenamiento)

| Tabla | Filas por boleto (S-04) | Filas al mes |
|---|---|---|
| `transaccion_log` | 3 (intento, confirmación, emisión) | 45,000,000 |
| `asiento_auditoria_log` | 4 (bloqueo, liberación/expiración, venta, abandonos) | 60,000,000 |
| `acceso_puerta_log` | 1.3 (escaneo más reintentos) | 19,500,000 |
| `admin_operacion_audit` | Volumen bajo | Aprox 50,000 |
| **Total** | | **Aprox 124.55 M filas/mes** |

El cálculo en bytes, GB y TB (mensual y acumulado a 5 años) se desarrolla en `docs/01-factibilidad/almacenamiento.md`.

---

## 4. Supuestos y justificación

Los siguientes valores **no vienen del enunciado**; son supuestos del equipo para poder dimensionar. Deben ser revisados y, de ser posible, respaldados con una fuente.

| ID | Supuesto | Valor | Justificación |
|---|---|---|---|
| S-01 | Capacidad promedio por sala y funciones diarias | 300 asientos; 5 funciones por sala por día | Tomamos de referencia los cines IMAX y de ahi sacamos los promedios en un rango aceptable. |
| S-02 | Proporción de lecturas y escrituras en el pico | 80% lecturas / 20% escrituras | En una venta de entradas, cada compra implica varias consultas previas (cartelera, mapa de asientos). Se usa una proporción prudente, como la que normalmente se aplica en sistemas que leen muchos datos. |  
| S-03 | Usuarios registrados | 20,000,000 | Con 15 M de boletos al mes y varios boletos por compra, una base de 20 M de cuentas es consistente con el volumen. Define el tamaño de la tabla `usuario`. |
| S-04 | Filas de log por boleto | 3 / 4 / 1.3 | Cada boleto genera varios eventos: intento, confirmación y emisión de pago; bloqueo, liberación o expiración y venta de asiento; escaneo en puerta más los reintentos. |
| S-05 | Máximo de asientos por transacción | 6 | El texto propone dos opciones: permitir 6 o 10. Se eligió 6 porque es la más estricta y ayuda mejor a evitar la reventa. |
| S-06 | Metas de latencia | p95 < 200 ms (mapa); p95 < 500 ms (reserva) | Estos son los umbrales habituales de experiencia de usuario fluida en comercio electrónico. |

---

## 5. Trazabilidad: reglas de negocio a requisitos

| Regla de negocio | Descripción breve | Requisito(s) |
|---|---|---|
| RN-01 | Solo funciones activas y futuras | RF-01, RF-02 |
| RN-02 | Información obligatoria de la función | RF-01 |
| RN-03 | Mapa en tiempo real | RF-03 |
| RN-04 | Límite de asientos por transacción | RF-05 |
| RN-05 | Bloqueo temporal de 2 minutos | RF-04 |
| RN-06 | Validación de tarifas por perfil en puerta | RF-06, RF-10 |
| RN-07 | Promociones automáticas | RF-06 |
| RN-08 | Cálculo exacto del total | RF-07 |
| RN-09 | Seguridad de pagos / PCI-DSS | RF-08, RNF-06 |
| RN-10 | Manejo de transacciones fallidas | RF-08 |
| RN-11 | Emisión solo tras pago aprobado | RF-09 |
| RN-12 | Unicidad del comprobante | RF-09, RNF-03 |
| RN-13 | Entrega en el perfil de la app | RF-09 |
| RN-14 | Validación única de entrada | RF-10 |
| RN-15 | Verificación de función y horario | RF-10, RF-11 |
| RN-16 | Tolerancia de ingreso | RF-10, RF-11 |
| RN-17 | RBAC | RF-15 |
| RN-18 | Restricción de modificación de salas con ventas | RF-12 |
| RN-19 | Cancelaciones y reembolsos | RF-13 |
| RN-20 | Auditoría de operaciones a 5 años | RF-11, RF-16, RNF-08 |