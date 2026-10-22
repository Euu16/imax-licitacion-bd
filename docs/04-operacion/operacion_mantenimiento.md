# Fase 5: Operación y Mantenimiento

**Proyecto:** Licitación para el Ecosistema Digital de Cines IMAX
**Fase:** 5, Estrategia de Operación y Mantenimiento

En este documento explicamos cómo vamos a cuidar la base de datos una vez que esté funcionando: cada cuánto se hacen respaldos, qué hacemos si algo se cae, qué disponibilidad prometemos y qué mantenimiento necesita. También justificamos por qué con esta propuesta se cumple cada meta.

---

## 1. Metas de operación

| Métrica | Meta | Por qué importa en este negocio |
|---|---|---|
| **RPO** (datos que se pueden perder) | Máximo 5 segundos, idealmente 0 | Perder datos significa perder pagos confirmados, asientos ya vendidos o boletos emitidos. Eso causa dobles ventas, problemas legales y que los clientes dejen de confiar |
| **RTO** (tiempo para volver a funcionar) | Menos de 5 minutos | En un estreno mundial, cada minuto caído son unas 3,000,000 de operaciones que no se pueden atender (50,000 por segundo × 60) |
| **SLA de disponibilidad** | 99.99% | Son unos 52.6 minutos de caída al año como máximo, o unos 4.3 minutos al mes |
| **Retención de auditoría** | Mínimo 5 años | Lo exigen las normas fiscales y de seguridad de la empresa (RN-20) |

Un plan de recuperación actual no puede depender de reiniciar un computador y esperar. Para cumplir estas metas hace falta copiar los datos todo el tiempo, que el cambio a un servidor de respaldo sea automático y que los respaldos se prueben de verdad.

---

## 2. Cómo se mantiene el servicio funcionando

La disponibilidad la construimos por capas, para que si falla una cosa no se detenga todo el servicio:

| Capa | Qué hace | Qué falla cubre | Efecto en las metas |
|---|---|---|---|
| 1. Alta disponibilidad dentro de la región | Hay un servidor principal y una copia en espera en **otra zona de disponibilidad**, siempre iguales (replicación síncrona). Si el principal falla, se cambia solo a la copia | Se daña el servidor o se cae una zona | RPO = 0. Azure documenta que el cambio tarda de 60 a 120 segundos y sin perder datos [1] |
| 2. Copia en otra región | Una copia de la base de datos en una segunda región, que se actualiza todo el tiempo pero con un pequeño retraso (replicación asíncrona) | Se cae toda una región | RPO de unos segundos. Aurora Global Database indica que la replicación suele tardar menos de 1 segundo [3] |
| 3. Respaldo continuo | Se guarda sin parar el registro de todas las transacciones (WAL), así se puede volver a cualquier momento del pasado | Errores humanos, fallas del software, datos dañados o ransomware | RPO de máximo 5 s al volver a un punto antes del daño |
| 4. Copias de largo plazo | Copias completas que no se pueden modificar, guardadas en otra región | Pérdida masiva de datos y cumplir la retención | Asegura los 5 años de auditoría |

> Las capas 1 y 2 protegen contra **fallas de la infraestructura** (algo se rompe). Las capas 3 y 4 protegen contra **errores y ataques**, que una copia no cubre: si alguien borra algo por accidente, la copia también lo borra.

---

## 3. Políticas de respaldo

### 3.1 Cada cuánto hay que hacer respaldos

Un respaldo diario no alcanza para un RPO de 5 segundos, porque en el peor caso se perderían casi 24 horas de datos. Ese RPO se cumple copiando los datos todo el tiempo (replicación y registro continuo de transacciones). Los respaldos completos sirven para lo que la replicación no cubre. Por eso combinamos varias frecuencias:

| Tipo de respaldo | Frecuencia | Cuánto se guarda | Dónde | Qué protege |
|---|---|---|---|---|
| Registro continuo de transacciones (WAL) | Continuo | 35 días (el máximo habitual en los servicios administrados) | Almacenamiento con copias dentro de la región | Volver a un momento exacto del pasado (RPO ≤ 5 s) |
| Copia completa automática | Diaria | 35 días | Almacenamiento con copias dentro de la región | Restaurar rápido a un día concreto |
| Copia completa en otra región | Diaria | 35 días | Otra región | Que se pierda toda la región |
| Copia de largo plazo | Mensual | 5 años | Almacenamiento barato con bloqueo para que no se pueda modificar | Retención fiscal y de auditoría |
| Exportar las particiones de logs de más de 12 meses | Mensual | 5 años | Almacenamiento barato y comprimido | Guardar las bitácoras de RN-20 |

### 3.2 Comprobar que los respaldos sirven

Un respaldo que nunca se restauró no sirve de garantía. Por eso programamos estas pruebas:

| Prueba | Frecuencia | Cómo sabemos que salió bien |
|---|---|---|
| Restaurar todo en un entorno aparte | Una vez al mes | La base se restaura y pasa las consultas de validación (conteos y sumas de control por tabla) |
| Volver a un momento del pasado | Una vez al mes | Se recupera el estado exacto anterior a un cambio que simulamos |
| Simulacro de falla de una zona y de una región | Cada tres meses | Se cumple el RTO < 5 min y el RPO ≤ 5 s, medidos de verdad |

---

## 4. Recuperación ante desastres

| Qué pasa | Cómo nos recuperamos | RTO | RPO |
|---|---|---|---|
| Falla el servidor principal o una zona | Cambio automático a la copia en espera | Menos de 2 min | 0 |
| Se cae toda la región | Se convierte en principal la copia de la otra región y se redirige el tráfico | Menos de 5 min | Máximo 5 s |
| Se borran o se dañan datos | Restaurar a un momento anterior al daño en un servidor nuevo y volver a conectar | Menos de 1 h | Máximo 5 s |
| Ransomware o cuenta comprometida | Restaurar desde las copias que no se pueden modificar, en otra región, y cambiar todas las contraseñas y claves | Menos de 4 h | Máximo 1 día |
| Se cae la pasarela de pago | Se cambia a la pasarela de respaldo y los pagos sin respuesta se revisan después | Menos de 5 min | 0 |

### Pasos si se cae una región completa

1. El monitoreo detecta la falla y avisa al equipo de guardia.
2. Se confirma qué tan grande es el problema: toda la región, no solo un componente.
3. Se promueve la copia de la región secundaria para que sea la nueva principal.
4. Se redirige el tráfico (DNS y balanceador global) hacia la región secundaria.
5. Se revisa el estado: el último registro de transacciones aplicado y los conteos de boletos y bloqueos.
6. Se ejecuta la liberación de bloqueos vencidos para que el inventario quede coherente.
7. Se avisa que el servicio volvió y se documenta la causa y cuánto tardamos en recuperarnos.

Como cada bloqueo de asiento dura solo 2 minutos, un asiento reservado justo antes de la caída vuelve a quedar libre por sí solo. Si hay una compra con el pago aprobado pero sin boleto, se detecta al revisar los pagos y se resuelve emitiendo el boleto o devolviendo el dinero.

---

## 5. Por qué se cumplen las métricas

| Meta | Cómo se cumple | En qué nos basamos |
|---|---|---|
| **RPO ≤ 5 s (ideal 0)** | Dentro de la región la copia es síncrona, así que no se pierde nada. Entre regiones es asíncrona, con un retraso típico de menos de 1 segundo, y se puede limitar con un parámetro de control | Azure: no se pierden datos con alta disponibilidad [1] [2]. Aurora: replicación típica de menos de 1 segundo y un parámetro para limitar el RPO [3] [4] |
| **RTO < 5 min** | El cambio automático dentro de la región tarda de 60 a 120 segundos. Entre regiones, convertir la copia en principal toma unos minutos | Azure: cambio de 60 a 120 s [1]. Aurora: la documentación habla de minutos y el material comercial de menos de 1 minuto [3] [4] |
| **SLA 99.99%** | Una base de datos con alta disponibilidad entre zonas, más redundancia en las demás capas (aplicación en varias zonas, balanceador y WAF) | Azure: 99.99% de disponibilidad con la configuración entre zonas [1] |

### Algo importante sobre el SLA

El 99.99% que ofrece un proveedor para **un servicio** no es el de **toda la plataforma**. Si la disponibilidad total dependiera de tres componentes en fila, cada uno con 99.99%, el resultado sería 0.9999³ ≈ 99.97%, o sea unos 158 minutos de caída al año. Por eso no dependemos de un solo componente por capa: la aplicación se despliega en varias zonas, el borde (la red de distribución y el WAF) es global y tiene respaldo, y la base de datos tiene una copia en espera. La meta de 99.99% para toda la plataforma se logra con redundancia en cada capa, y se comprueba midiendo la disponibilidad real.

---

## 6. Mantenimiento

| Tarea | Cada cuánto | Detalle |
|---|---|---|
| Crear particiones de las bitácoras | Cada mes (automático) | Se crean con tiempo las particiones de los meses siguientes |
| Archivar particiones viejas | Cada mes | Las de más de 12 meses se desprenden (`DETACH PARTITION`), se exportan a almacenamiento barato y se sacan de la base transaccional |
| Liberar bloqueos vencidos | Todo el tiempo (proceso periódico) | Deja libres los asientos con bloqueo vencido y registra la expiración en la bitácora |
| Estadísticas e índices | Cada semana | Se ejecuta `ANALYZE` en las tablas más grandes y se revisan los índices que no se usan o están desordenados |
| Revisar planes de ejecución | Cada mes y antes de cada estreno | `EXPLAIN ANALYZE` de las consultas importantes (disponibilidad de asientos y reportes) |
| Parches del motor y del sistema | Según el calendario del proveedor | En el servicio administrado se aplican primero a la copia en espera, para interrumpir lo menos posible [2] |
| Cambiar contraseñas y claves | Cada tres meses | Incluye las de la pasarela y las de las cuentas de servicio |
| Revisar roles y permisos | Cada tres meses | Para confirmar que cada rol sigue teniendo solo los permisos que necesita |
| Pruebas de carga | Antes de cada estreno grande | Se simula el pico con k6 o JMeter y se revisan los límites del autoescalado |

---

## 7. Monitoreo y alertas

| Qué se mide | Cuándo se alerta | Qué hacemos |
|---|---|---|
| Retraso de la replicación | Más de 1 segundo sostenido | Revisar la carga y la red entre zonas o regiones |
| Tiempo de reserva de un asiento (p95) | Más de 500 ms | Hacer crecer la parte de aplicación y revisar bloqueos |
| Tiempo del mapa de asientos (p95) | Más de 200 ms | Revisar la caché y las copias de lectura |
| Errores o demoras de la pasarela | Más del 2% de las solicitudes | Cambiar a la pasarela de respaldo |
| Uso de disco y crecimiento de las bitácoras | Más del 75% | Adelantar el archivado de particiones |
| Conexiones activas | Más del 80% del límite | Revisar el pool de conexiones y hacer crecer el servicio |
| Bloqueos vencidos sin liberar | Más de 1,000 | Revisar el proceso periódico |
| Fallas en los respaldos o en su verificación | Cualquier falla | Corregir de inmediato y repetir la copia |

---

## 8. Privacidad y cumplimiento de normas

| Tema | Qué hacemos |
|---|---|
| **Datos de tarjeta (PCI-DSS, RN-09)** | No se guarda el número completo ni el CVV. Solo se guarda el token de la pasarela y los últimos 4 dígitos |
| **Datos personales** | Solo pedimos los necesarios (nombre, correo y teléfono). Las contraseñas se guardan con hash. Todo va cifrado en tránsito y en reposo |
| **Acceso** | Control por roles con el privilegio mínimo. Toda operación manual de un administrador queda en una bitácora con fecha, hora, IP, rol y usuario |
| **Derecho a borrar los datos frente a los 5 años de retención** | Los registros financieros y de auditoría se guardan porque la ley lo exige. Si una persona pide eliminar su cuenta, sus datos personales se anonimizan y se mantienen los registros de las transacciones sin identificarla |
| **Normas** | Aplicamos los principios de las normas de protección de datos personales (GDPR y CCPA, como criterio de diseño). Cumplirlas de manera formal depende de cada país donde opere IMAX |

---

## 9. Referencias

Consultadas en octubre de 2026.

1. Microsoft. *High availability in Azure Database for PostgreSQL - Flexible Server*. https://learn.microsoft.com/azure/postgresql/flexible-server/concepts-high-availability
2. Microsoft. *Business continuity in Azure Database for PostgreSQL - Flexible Server*. https://learn.microsoft.com/azure/postgresql/flexible-server/concepts-business-continuity
3. Amazon Web Services. *Using switchover or failover in Amazon Aurora Global Database*. https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-disaster-recovery
4. Amazon Web Services. *Amazon Aurora Global Database*. https://aws.amazon.com/rds/aurora/global-database
