# Cálculo de Almacenamiento (mensual y acumulado a 5 años)

**Proyecto:** Licitación para el Ecosistema Digital de Cines IMAX
**Fase:** 1, Análisis de Factibilidad

Este documento estima el almacenamiento que necesita la base de datos para operar y para cumplir la retención obligatoria de 5 años de registros de auditoría (RN-20). Es la base del costo de almacenamiento en la comparativa de proveedores cloud.

---

## 1. Datos de partida

Los datos del enunciado y los supuestos de dimensionamiento están documentados en `requisitos.md`. Resumen:

| Dato | Valor | Origen |
|---|---|---|
| Boletos al mes | 15,000,000 | Enunciado |
| Salas | 1,500 | Enunciado |
| Títulos activos | 500 | Enunciado |
| Retención de logs | 5 años (60 meses) | Enunciado (RN-20) |
| Usuarios registrados | 20,000,000 | Supuesto S-03 |
| Funciones al mes | 225,000 | Calculado (1,500 salas × 5 funciones × 30 días) |
| Boletos por orden | 2.5 | Supuesto S-07 |
| Intentos de pago por orden | 1.2 | Supuesto S-08 |
| Sobrecosto por índices y estructura de páginas | +30% | Supuesto S-09 |
| Filas mensuales de `asiento_funcion` | 20,000,000 | Supuesto S-11 |

---

## 2. Tamaño estimado por fila

Los bytes por fila se estiman a partir de los tipos de dato del diseño (`der.md`) e incluyen unos 24 bytes de cabecera por fila en PostgreSQL. Son estimaciones (S-10) que pueden contrastarse con `pg_total_relation_size()` sobre datos de prueba.

| Tabla | Composición aproximada | Bytes/fila |
|---|---|---|
| `transaccion_log` | IDs (3 × 8), evento, monto, impuesto, moneda, referencia de pasarela, `jsonb` de detalle, timestamp, cabecera | 250 |
| `asiento_auditoria_log` | IDs (4 × 8), evento, 2 timestamps, cabecera | 100 |
| `acceso_puerta_log` | IDs, resultado, motivo, timestamp, cabecera | 120 |
| `admin_operacion_audit` | IDs, IP, operación, `jsonb` anterior y nuevo, timestamp, cabecera | 500 |
| `boleto` | IDs, UUID del QR (16), precio, estado, origen, 2 timestamps, cabecera | 180 |
| `orden` | IDs, canal, estado, 4 montos, timestamp, cabecera | 200 |
| `pago` | IDs, estado, monto, token de pasarela, últimos 4, timestamp, cabecera | 200 |
| `asiento_funcion` | 2 IDs, estado, ID de usuario, expiración del bloqueo, cabecera | 60 |
| `funcion` | IDs, 2 timestamps, estado, cabecera | 100 |
| `usuario` | Nombre, correo, teléfono, hash de contraseña, fechas, cabecera | 300 |

---

## 3. Volumen mensual y acumulado a 5 años (datos netos)

Unidades en GB decimales (1 TB = 1,000 GB). Sin índices.

### 3.1 Tablas de auditoría (logs)

| Tabla | Filas/mes | Bytes/fila | GB/mes | GB a 5 años |
|---|---|---|---|---|
| `transaccion_log` | 45,000,000 | 250 | 11.250 | 675.0 |
| `asiento_auditoria_log` | 60,000,000 | 100 | 6.000 | 360.0 |
| `acceso_puerta_log` | 19,500,000 | 120 | 2.340 | 140.4 |
| `admin_operacion_audit` | 50,000 | 500 | 0.025 | 1.5 |
| **Subtotal logs** | | | **19.615** | **1,176.9** |

### 3.2 Tablas operativas con histórico

| Tabla | Filas/mes | Bytes/fila | GB/mes | GB a 5 años |
|---|---|---|---|---|
| `boleto` | 15,000,000 | 180 | 2.700 | 162.0 |
| `orden` | 6,000,000 | 200 | 1.200 | 72.0 |
| `pago` | 7,200,000 | 200 | 1.440 | 86.4 |
| `asiento_funcion` | 20,000,000 | 60 | 1.200 | 72.0 |
| `funcion` | 225,000 | 100 | 0.023 | 1.4 |
| **Subtotal operativas** | | | **6.563** | **393.8** |

`asiento_funcion` se crea bajo demanda (solo para asientos bloqueados o vendidos). Se contabiliza aquí acumulada durante los 60 meses, de forma conservadora; si se purga al finalizar cada función, su aporte al total sería menor, porque su historia se conserva en `asiento_auditoria_log`.

### 3.3 Tablas estáticas o de crecimiento lento

| Tabla | Filas | Bytes/fila | GB |
|---|---|---|---|
| `usuario` | 20,000,000 | 300 | 6.0 |
| `asiento` | 450,000 | 80 | 0.04 |
| Catálogos (películas, salas, tarifas, roles, etc.) | < 100,000 | n/a | < 0.1 |
| **Subtotal estáticas** | | | **= 6.1** |

Los bloqueos temporales de asientos viven en `asiento_funcion` (sección 3.2), y sus eventos de bloqueo y expiración quedan en `asiento_auditoria_log`, que ya está contabilizado en la sección 3.1.

---

## 4. Tabla resumen

| Concepto | GB/mes | A 12 meses | A 36 meses | A 60 meses (5 años) |
|---|---|---|---|---|
| Logs de auditoría | 19.6 | 235 GB | 706 GB | 1,177 GB |
| Operativas con histórico | 6.6 | 79 GB | 236 GB | 394 GB |
| Estáticas | n/a | 6 GB | 6 GB | 6 GB |
| **Total neto (sin índices)** | **26.2** | **320 GB** | **948 GB** | **1,577 GB** |
| **Total con índices (+30%)** | **34.0** | **416 GB** | **1,233 GB** | **2,050 GB = 2.05 TB** |

**Resultado: aproximadamente 26 GB netos por mes (34 GB con índices) y cerca de 2.05 TB acumulados a 5 años.**

---

## 5. Sensibilidad: crecimiento de volumen del 10% anual

La proyección financiera a 3 años supone un crecimiento del 10% anual en el volumen. Aplicado al almacenamiento de las tablas que crecen (logs y operativas, sin índices):

| Año | GB del año | Acumulado |
|---|---|---|
| 1 | 314 | 314 GB |
| 2 | 346 | 660 GB |
| 3 | 380 | 1,040 GB |
| 4 | 418 | 1,458 GB |
| 5 | 460 | 1,918 GB |

Sumando las tablas estáticas (6.1 GB) y el 30% de índices, el total a 5 años en este escenario sería de **= 2.5 TB**.

---

## 6. De datos netos a capacidad aprovisionada

El tamaño de los datos no es lo mismo que la capacidad que se paga. Para costear la infraestructura se separan cuatro capas:

| Capa | Qué contiene | Estimación |
|---|---|---|
| **Caliente** (PostgreSQL, SSD) | Últimos 12 meses de logs y tablas operativas | = 416 GB con índices |
| **Replicación** | Primaria más 2 réplicas (alta disponibilidad multi-zona o multi-región) | ×3, es decir = 1.25 TB de disco |
| **Fría** (almacenamiento de objetos) | Particiones de más de 12 meses exportadas y comprimidas (Parquet) | = 1.26 TB netos; con compresión de 4:1 a 6:1, entre 0.21 y 0.31 TB |
| **Respaldos** | Copias completas e incrementales con retención quinquenal | Entre 1 y 2 veces el dato neto (= 1.6 a 3.2 TB) |

Esta separación justifica el **particionamiento mensual** de los logs: las particiones antiguas se desprenden (`DETACH PARTITION`), se exportan a almacenamiento frío de bajo costo (S3 Glacier o Azure Archive) y se eliminan de la base de datos transaccional, que es la capa más cara.

---

## 7. Relación con el valor referencial del enunciado

El ejemplo de costos del enunciado menciona 45 TB acumulados para el almacenamiento histórico y de logs, y lo presenta como valor referencial. Esta propuesta mantiene su propio cálculo, construido de abajo hacia arriba: filas por mes, bytes por fila y 60 meses de retención, lo que da cerca de 2 TB netos.

La diferencia se explica por el criterio de cada cifra. El cálculo de este documento separa el **dato neto** (sección 4) de la **capacidad aprovisionada** (sección 6): réplicas, respaldos, comprobantes en PDF o imágenes de QR y cargas útiles completas por evento no están en el dato neto, y se estiman aparte. El valor de 45 TB del enunciado no detalla su composición, por lo que no es posible compararlo línea por línea; en cambio, cada cifra de este documento puede rastrearse hasta un supuesto explícito.

Los costos de almacenamiento de la comparativa de proveedores se calculan con las cifras de este documento.

---

## 8. Supuestos de este documento

| ID | Supuesto | Valor | Justificación |
|---|---|---|---|
| S-07 | Boletos promedio por orden | 2.5 | Compras típicas en pareja o grupo pequeño, con un máximo de 6 por transacción (RN-04) |
| S-08 | Intentos de pago por orden | 1.2 | Algunos pagos son rechazados y se reintentan |
| S-09 | Sobrecosto por índices y estructura de páginas | +30% | Valor habitual para tablas con 2 o 3 índices |
| S-10 | Bytes por fila | Ver sección 2 | Estimación a partir de los tipos de dato del diseño |
| S-11 | Filas de `asiento_funcion` al mes | 20,000,000 (rango de 15 a 25 millones) | Boletos vendidos (15 M) más asientos bloqueados y luego abandonados, dado que la fila se crea bajo demanda |