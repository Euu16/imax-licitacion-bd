# Matriz Única de Riesgo y Mitigación

**Proyecto:** Licitación para el Ecosistema Digital de Cines IMAX
**Fase:** 1, Análisis de Factibilidad (análisis de riesgos)

En esta matriz juntamos los riesgos más importantes de la plataforma durante todo el servicio. De cada uno decimos qué tan probable es, qué tan grave sería, cómo lo reducimos, cuánto tardaríamos en recuperarnos (RTO) y cuántos datos podríamos perder (RPO). Los valores de RTO y RPO son objetivos de diseño: los basamos en lo que publican los servicios administrados (sección 3) y en las metas del proyecto, que son RPO de máximo 5 segundos y RTO menor a 5 minutos.

---

## 1. Escalas utilizadas

| Escala | Valor | Qué significa |
|---|---|---|
| Probabilidad | Baja | Puede pasar una vez cada varios años |
| | Media | Puede pasar una o más veces al año |
| | Alta | Se espera que pase durante la vida del servicio, o en cada estreno grande |
| Impacto | Bajo | Afecta a pocos usuarios o a una sala, sin perder ventas ni datos |
| | Medio | Baja la calidad del servicio o afecta a un cine, con una pérdida limitada de ingresos |
| | Crítico | Detiene las ventas en todo el mundo, pierde datos financieros o nos expone legalmente |

**RTO** (Recovery Time Objective) es el tiempo máximo que podemos tardar en volver a tener el servicio funcionando. **RPO** (Recovery Point Objective) es la cantidad máxima de datos que podríamos perder, medida en tiempo.

---

## 2. Matriz de riesgos

| ID Riesgo | Descripción del Riesgo | Probabilidad (Baja/Media/Alta) | Impacto (Bajo/Medio/Crítico) | Estrategia de Mitigación / Plan de Respaldo (DRP) | RTO / RPO Objetivo |
|---|---|---|---|---|---|
| R-01 | Se cae el servidor principal de la base de datos durante el estreno | Media | Crítico | Tener una copia lista en otra zona de disponibilidad, que se mantiene igual que el servidor principal en todo momento (replicación síncrona). Si el principal falla, el sistema cambia solo a la copia (failover automático). Además hay alertas que vigilan el estado del servidor | RTO < 2 min / RPO = 0 |
| R-02 | Se cae toda una región del proveedor cloud | Baja | Crítico | Una copia de la base de datos en una segunda región que se actualiza todo el tiempo (replicación asíncrona). Dejamos escritos los pasos para convertir esa copia en la principal y mandar el tráfico hacia allá (DNS y balanceador global). Hacemos simulacros cada tres meses | RTO < 5 min / RPO ≤ 5 s |
| R-03 | La pasarela de pago se cae o se pone lenta | Media | Crítico | Una segunda pasarela de respaldo que entra sola cuando la primera falla (con un disyuntor, o circuit breaker). Los reintentos son seguros: si un cobro se repite, no se cobra dos veces. Los pagos que no responden quedan como `pendiente` y se revisan después. Como los asientos solo se guardan 2 minutos, no se acumulan bloqueos | RTO < 5 min / RPO = 0 |
| R-04 | Ataque de denegación de servicio (DDoS) en el estreno | Alta | Crítico | Red de distribución de contenido, firewall de aplicaciones (WAF) y protección contra DDoS en el borde de la red. Límites de solicitudes por IP y por usuario. Una sala de espera virtual que controla cuánta gente entra a la vez | RTO < 5 min / RPO = 0 |
| R-05 | Se pierde la consistencia del inventario: un asiento se vende dos veces | Media | Crítico | Lo prevenimos desde el diseño: la base de datos no permite dos filas para la misma pareja (función, asiento), el bloqueo se hace en una sola sentencia que no se puede interrumpir, y hay llaves foráneas compuestas y un índice único parcial sobre los boletos vigentes. Hacemos pruebas automáticas con 20 a 50 solicitudes al mismo tiempo sobre el mismo asiento. Una bitácora de bloqueos permite revisar las colisiones | RTO < 15 min (corregir y reembolsar) / RPO = 0 |
| R-06 | Saturación por el pico de carga (8 millones de usuarios y 50,000 TPS) | Alta | Crítico | La parte de aplicación crece sola cuando hay más gente (autoescalado). También usamos sala de espera virtual, caché para el mapa de asientos, un grupo compartido de conexiones a la base de datos (pool) y copias de solo lectura. Antes de cada estreno hacemos pruebas de carga (k6 o JMeter) | RTO < 5 min / RPO = 0 |
| R-07 | Se filtran datos de tarjetas o se incumple PCI-DSS | Baja | Crítico | Los datos de la tarjeta nunca llegan a nuestra base de datos: usamos una pasarela certificada y solo guardamos un token y los últimos 4 dígitos. Todo viaja y se guarda cifrado (TLS en tránsito y cifrado en reposo). También separamos las redes, cuidamos las claves y contraseñas y hacemos revisiones de seguridad | RTO < 1 h (contener el problema) / RPO = 0 |
| R-08 | Datos dañados o borrados por un error humano, una falla del software o ransomware | Media | Crítico | Respaldo continuo que permite volver a cualquier momento del pasado (PITR), copias completas todos los días y copias que no se pueden modificar, guardadas 5 años. Roles con privilegio mínimo, sin escritura directa sobre las bitácoras | RTO < 1 h / RPO ≤ 5 s |
| R-09 | Fraude por reutilizar o falsificar un código QR | Media | Medio | Cada QR es un código único (UUID). En la puerta se valida con una actualización condicional que solo deja usarlo una vez, y el segundo intento muestra "Entrada ya utilizada". Cada intento queda en la bitácora de accesos | RTO < 1 min / RPO = 0 |
| R-10 | Fallan los lectores de QR o la conexión a internet en un cine | Alta | Medio | Un dispositivo de repuesto por sala y reintentos automáticos. Si todo falla, hay un plan manual: una lista de boletos válidos por función en el puesto de control, que después se sincroniza para que cada boleto siga valiendo una sola vez | RTO < 10 min / RPO = 0 |
| R-11 | Uso indebido de privilegios por parte del personal interno | Media | Crítico | Roles con privilegio mínimo. Una bitácora administrativa que no se puede modificar, con fecha, hora, IP, rol y usuario. Los reembolsos forzados y las cortesías siempre tienen un responsable identificado. Revisamos los accesos cada cierto tiempo | RTO n/a (preventivo) / RPO = 0 |
| R-12 | Se pierden registros de auditoría o se llena el almacenamiento antes de cumplir los 5 años de retención | Baja | Medio | Logs divididos por mes, archivado de los meses antiguos en almacenamiento barato que no se puede modificar, copias en otra región y alertas cuando se esté llenando el espacio | RTO < 4 h (restaurar una partición archivada) / RPO = 0 |

---

## 3. De dónde salen los objetivos de recuperación

Los objetivos de la matriz no los inventamos: se apoyan en lo que documentan los servicios administrados. Estos son los dos casos que determinan R-01 y R-02:

| Capacidad | Qué dice la documentación | Riesgo que respalda |
|---|---|---|
| Azure Database for PostgreSQL con alta disponibilidad zona-redundante | Tiene una copia en espera en otra zona, cambia sola en 60 a 120 segundos y no pierde datos. Su SLA de disponibilidad es de 99.99% [1] [2] | R-01 |
| Amazon Aurora Global Database | La replicación entre regiones suele tardar menos de 1 segundo. La documentación dice que el RPO típico es de segundos (no cero) y el RTO del orden de minutos, mientras que el material comercial habla de menos de 1 minuto [3] [4] | R-02 |

Por eso R-01 usa un RPO de 0 (la copia dentro de la región se mantiene sincronizada) y R-02 usa un RPO de hasta 5 segundos (la copia entre regiones es asíncrona). Así cumplimos la meta del enunciado sin pedir un RPO cero entre regiones, algo que no se puede lograr con replicación asíncrona.

---

## 4. Prioridad de atención

Los riesgos con probabilidad Media o Alta e impacto Crítico son donde más conviene gastar en mitigación:

| Prioridad | Riesgos | Por qué |
|---|---|---|
| 1 | R-01, R-04, R-05, R-06 | Son probables y pueden detener el estreno |
| 2 | R-03, R-08, R-11 | Probabilidad media, pero con impacto crítico |
| 3 | R-02, R-07 | Es poco probable que pasen, pero sus consecuencias no se pueden deshacer |
| 4 | R-09, R-10, R-12 | Impacto medio, con soluciones baratas |

---

## 5. Referencias

Consultadas en octubre de 2026.

1. Microsoft. *High availability in Azure Database for PostgreSQL - Flexible Server*. https://learn.microsoft.com/azure/postgresql/flexible-server/concepts-high-availability
2. Microsoft. *Business continuity in Azure Database for PostgreSQL - Flexible Server*. https://learn.microsoft.com/azure/postgresql/flexible-server/concepts-business-continuity
3. Amazon Web Services. *Using switchover or failover in Amazon Aurora Global Database*. https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-disaster-recovery
4. Amazon Web Services. *Amazon Aurora Global Database*. https://aws.amazon.com/rds/aurora/global-database
