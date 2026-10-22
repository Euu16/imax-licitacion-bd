# Dictamen Técnico de Rechazo de la Propuesta Legada

**Proyecto:** Licitación para el Ecosistema Digital de Cines IMAX
**Fase:** 1, Análisis de Factibilidad

---

## 1. Dictamen

Después de revisar la propuesta del proveedor anterior, concluimos que **hay que rechazarla por completo**.

Comparamos sus seis partes con lo que va a pasar en el estreno mundial: 8,000,000 de usuarios conectados al mismo tiempo y unas 50,000 transacciones por segundo durante los primeros 10 minutos. También las comparamos con las reglas de negocio del enunciado y con las metas de recuperación: una disponibilidad (SLA) de 99.99%, perder como máximo 5 segundos de datos (RPO) y volver a funcionar en menos de 5 minutos (RTO). Ninguna de las seis partes cumple lo que se le pide. Además, tres de ellas (cómo se manejan las tarjetas, la hoja de cálculo como inventario y el plan de respaldo) tienen riesgos legales y de dinero que no se arreglan con unos cuantos ajustes.

Los números de este documento salen de tres lugares: los datos del enunciado, los cálculos que hicimos en `requisitos.md` y `almacenamiento.md`, y los límites que publican las mismas empresas dueñas de los programas (están en las referencias). Cuando tuvimos que suponer algo, lo dejamos escrito.

### Resumen de brechas

| # | Parte de la propuesta | Lo que pide el proyecto | Lo que ofrece la propuesta del proveedor | Veredicto |
|---|---|---|---|---|
| 1 | Access o SQLite en un PC i3 de 2012 | Unas 10,000 escrituras por segundo y cerca de 2 TB a 5 años, con transacciones ACID | Access: 2 GB y 255 usuarios. SQLite: solo una persona puede escribir a la vez | Rechazado |
| 2 | Internet de casa de 50 Mbps con Wi-Fi 2.4 GHz | Una conexión de cientos de Mbps, solo para las transacciones | 50 Mbps compartidos y sin SLA | Rechazado |
| 3 | Hoja de Google Sheets donde se escriben los nombres a mano | Asientos que no se vendan dos veces, con bloqueo de 2 minutos y registro de lo que pasa | Máximo de 10 millones de celdas, sin transacciones ni forma de evitar repetidos | Rechazado |
| 4 | Tarjetas y CVV enviados por WhatsApp | PCI-DSS y RN-09: no guardar el número completo ni el CVV | Datos completos de la tarjeta en un chat, pasados a mano | Rechazado |
| 5 | "Reiniciar y cruzar los dedos" | RTO menor a 5 min, RPO máximo de 5 s y SLA de 99.99% | Sin respaldo, sin copia del servidor y sin plan | Rechazado |
| 6 | Cálculo del tamaño de la solución | Un cálculo claro de usuarios, TPS y 5 años de logs | No presenta ningún cálculo y lo que propone no aguanta esas cifras | Rechazado |

---

## 2. Análisis por componente

### 2.1 Motor de base de datos: Access o SQLite en un PC de escritorio

La propuesta consiste en usar una sola base de datos de Microsoft Access (o un archivo SQLite) guardada en un computador de escritorio con procesador Intel Core i3 de 2012, que estaría en una oficina en Los Ángeles.

Lo primero es el tamaño. Access solo permite bases de 2 GB [1], y lo que hay que guardar durante 5 años llega a unos 2.05 TB con índices (lo calculamos en `almacenamiento.md`). Es como unas 1,000 veces más de lo que le cabe.

Con la cantidad de usuarios pasa lo mismo. Access soporta máximo 255 usuarios a la vez [1], y en la práctica empieza a ir lento antes de llegar a ese número. Para el estreno se esperan 8,000,000 de usuarios al mismo tiempo, más de 31,000 veces ese límite.

SQLite tiene otro problema: muchas personas pueden leer a la vez, pero solo una puede escribir en cada momento [2]. Calculamos que se necesitarían unas 10,000 escrituras por segundo (50,000 TPS, de las cuales el 20% son escrituras según nuestro supuesto S-02), y todas tendrían que hacer fila para esperar su turno.

Además les faltan cosas que el proyecto pide: roles donde cada persona solo ve lo que necesita (RN-17), dividir los logs por fecha (RN-20), copias de los datos en otro servidor y poder volver a un momento exacto del pasado. Y todo estaría en un solo computador viejo con un solo disco, con los datos de todos los cines del mundo. Si ese disco se daña, se pierden también los 5 años de registros que la ley obliga a guardar.

**Requisitos que incumple:** RNF-02, RNF-03, RNF-05, RNF-08, RN-17 y RN-20.

---

### 2.2 Infraestructura y red: fibra residencial de 50 Mbps con Wi-Fi 2.4 GHz

Aquí proponen que todo lo que hagan los cines del mundo pase por una conexión de internet de casa de 50 Mbps, con Wi-Fi de 2.4 GHz y un repetidor de señal en el pasillo. No usarían ningún servicio en la nube.

50 Mbps son unos 6.25 MB por segundo. Supongamos que cada transacción mueve solo 1 KB entre lo que se pide y lo que se responde (es poco, porque el mapa de asientos pesa bastante más). Con 50,000 TPS serían unos 50 MB por segundo, es decir, 400 Mbps. Eso es ocho veces lo que aguanta la conexión.

Con la primera descarga pasa algo parecido. Si cada usuario bajara 100 KB solo para ver la cartelera (otro supuesto nuestro), los 8 millones de usuarios necesitarían 800 GB. A 6.25 MB por segundo eso se demoraría cerca de 36 horas, y el momento crítico dura 10 minutos.

El Wi-Fi de 2.4 GHz lo comparte todo el que esté conectado y le afectan las interferencias, y un repetidor barato baja todavía más la velocidad real. No es algo que se use para el servidor de un sistema de ventas.

Una conexión de casa tampoco tiene SLA, ni otro proveedor de respaldo, ni protección contra ataques que saturan el servicio, ni reparto de la carga entre varios servidores. Garantizar 99.99% de disponibilidad (unos 52 minutos caído al año) así no se puede. Y como todo pasaría por un solo punto en Los Ángeles, a las personas de Asia o Europa les respondería más lento, y no habría una red de servidores cercanos que lo compense.

**Requisitos que incumple:** RNF-01, RNF-04 y RNF-05.

---

### 2.3 Inventario de asientos: hoja de cálculo compartida en Google Drive

La propuesta es guardar las compras de 8 millones de usuarios en una sola hoja de cálculo compartida, donde cada cliente escribe a mano su nombre en el asiento que quiere.

El problema principal es que una hoja de cálculo no tiene transacciones ni forma de impedir valores repetidos. Si dos personas escriben en la misma celda casi al mismo tiempo, lo último que se escribe borra lo anterior y nadie se entera. Eso es justo la doble venta de un asiento que queremos evitar (RNF-03). Tampoco existe el bloqueo de 2 minutos que se libera solo (RN-05), ni estados del asiento (disponible, bloqueado, ocupado) que cambien de forma segura.

También hay un límite de tamaño: Google Sheets permite máximo 10 millones de celdas por archivo [3]. Con 15 millones de boletos al mes, aunque se use una sola celda por boleto, ya se pasa en el primer mes. En 5 años serían 900 millones de boletos, 90 veces el límite.

Hay más problemas:

- Un nombre escrito a mano puede tener errores, o alguien puede hacerse pasar por otra persona o hacer daño a propósito, porque cualquiera con acceso puede borrar o cambiar reservas de otros.
- No hay un registro confiable de quién cambió qué (RN-20), ni un QR único para cada asiento (RN-12), ni forma de revisar en la puerta que la entrada se use una sola vez (RN-14).
- Nada une el asiento marcado con un pago aprobado, así que tampoco se puede soltar el asiento cuando el pago falla (RN-10).

**Requisitos que incumple:** RNF-03, RN-03, RN-05, RN-10, RN-12, RN-14 y RN-20.

---

### 2.4 Seguridad y pagos: tarjetas completas y CVV a un chat de WhatsApp

Esta propuesta cambia la pasarela de pago (el servicio que cobra las tarjetas) por un formulario web simple que manda el número completo de la tarjeta y el código CVV a un chat grupal de WhatsApp de la empresa. Ahí un pasante las pasa una por una por un datáfono.

Creemos que es lo más grave de todo. El estándar PCI-DSS prohíbe guardar el CVV después de que se autoriza el pago y pide proteger el número de la tarjeta siempre. Un chat se copia en los celulares, en los respaldos y en el historial de cada persona del grupo, así que los datos quedan guardados sin ningún control. Además, cualquiera del grupo puede ver todas las tarjetas, y no queda registro de quién las vio. Y como el formulario no usa una pasarela certificada, los datos no pasan por el sistema de tokens que pide RN-09.

También es imposible de hacer a esa escala. Si un pasante se demora 10 segundos por tarjeta (es un supuesto), pasa 6 por minuto. En el pico se necesitan unas 10,000 escrituras por segundo, así que harían falta unos 100,000 pasantes trabajando al mismo tiempo. Aun con el promedio de 5.8 boletos por segundo se necesitarían unos 58.

Si se filtran los números de tarjeta y los CVV, IMAX se arriesga a multas, a que le quiten la posibilidad de cobrar con tarjeta y a demandas de los clientes. Ningún ahorro vale eso. Por último, un pago hecho a mano no puede confirmar el asiento y generar el QR de forma segura (RN-11), ni soltar el asiento si el pago falla (RN-10).

**Requisitos que incumple:** RNF-06, RN-09, RN-10 y RN-11.

---

### 2.5 Recuperación ante desastres: "reiniciarla y cruzar los dedos"

El plan del proveedor dice que, si el computador se sobrecalienta, se apaga o se va la luz, se reinicia y se espera que los clientes tengan paciencia.

Eso no es un plan. No hay copias de seguridad, ni otro servidor de respaldo, ni pasos para recuperarse. Por eso el RPO (cuántos datos se pueden perder) queda sin definir: se perdería todo lo que pasó desde la última copia, y no existe ninguna. El enunciado pide perder máximo 5 segundos de datos (idealmente 0), volver a funcionar en menos de 5 minutos (RTO) y una disponibilidad de 99.99%, y reiniciar un computador de escritorio no asegura ninguna de las tres.

Hay que pensar también en lo que cuesta estar caído. En el pico se procesan unas 50,000 operaciones por segundo, así que cada minuto sin servicio son unas 3,000,000 de operaciones que fallan. Como es un estreno mundial, las personas afectadas serían las de todas las salas a la vez.

Además, el computador, la conexión de casa, la electricidad, Google Drive y WhatsApp no tienen respaldo, y si falla cualquiera se detiene todo. Y sin copias, si se daña el disco se pierden los registros de auditoría que RN-20 obliga a guardar durante 5 años.

**Requisitos que incumple:** RNF-01, RNF-02, RNF-10 y RN-20.

---

### 2.6 Dimensionamiento de datos y volumen esperado

Lo que se pide es calcular el tamaño de la solución para 8,000,000 de usuarios al mismo tiempo, un pico de 50,000 TPS durante los primeros 10 minutos, 500 títulos en 1,500 salas, 15 millones de boletos al mes y 5 años de registros de auditoría.

La propuesta del proveedor no incluye ningún cálculo, y lo que describe no alcanza para esas cifras. La tabla lo resume:

| Variable | Valor del proyecto | Lo que tiene la propuesta del proveedor | Diferencia |
|---|---|---|---|
| Usuarios al mismo tiempo | 8,000,000 | 255 (límite de Access) | Más de 31,000 veces |
| Operaciones en el pico | 30,000,000 en 10 minutos | Un solo escritor y un solo disco | No lo aguanta |
| Ancho de banda en el pico | Unos 400 Mbps (suponiendo 1 KB por transacción) | 50 Mbps | 8 veces |
| Almacenamiento a 5 años | Unos 2.05 TB con índices | 2 GB (Access) | Unas 1,000 veces |
| Boletos al mes | 15,000,000 | 10,000,000 de celdas por hoja | Se pasa en el primer mes |
| Relación pico / promedio | Unas 8,600 veces | Capacidad fija, no crece ni baja | No se adapta |

La última fila es la más importante: la carga del estreno es unas 8,600 veces el promedio de un día normal. Con la nube se puede crecer solo durante los minutos que hace falta y pagar por eso, en vez de comprar todo el año el equipo que se necesita un solo día.

---

## 3. Conclusión y recomendación

Con este análisis vemos que la propuesta del proveedor no es una opción barata: es un riesgo que ni siquiera se puede asegurar. No cumple en capacidad, en que los datos estén correctos, en seguridad ni en recuperación, y deja a IMAX expuesta a perder datos, a recibir sanciones por incumplir PCI-DSS y a quedarse sin servicio justo en su evento más importante.

Recomendamos cambiarla por una solución en la nube. Estos son sus elementos principales:

| Necesidad | Respuesta de la solución propuesta |
|---|---|
| Datos correctos y muchos usuarios a la vez | Base de datos PostgreSQL administrada, con transacciones ACID (los cambios se hacen completos o no se hacen), una regla de unicidad `(id_funcion, id_asiento)` y bloqueo de asientos en un solo paso |
| Picos de tráfico | Crece sola cuando hay más gente, sala de espera virtual, caché para el mapa de asientos y un grupo de conexiones compartidas a la base de datos (pool) |
| Que el servicio no se caiga | Si el servidor falla, se pasa automáticamente (failover) a una copia en otra zona o región |
| Red y seguridad | Balanceador de carga que reparte el tráfico, con firewall para aplicaciones web (WAF) y protección contra ataques que saturan el servicio |
| Pagos | Pasarela certificada PCI-DSS, donde solo se guarda un token y los últimos 4 dígitos |
| Guardar 5 años | Logs divididos por mes, almacenamiento barato para lo antiguo y respaldos automáticos |
| Recuperación | Respaldos continuos y copias del servidor para cumplir RPO ≤ 5 s y RTO < 5 min |

Más adelante en este documento desarrollamos el detalle técnico, económico y de riesgos de la propuesta, en las secciones de factibilidad técnica, factibilidad económica y matriz de riesgos.

---

## 4. Referencias

Consultadas en octubre de 2026.

1. Microsoft. *Access specifications*. https://support.microsoft.com/en-us/access/access-specifications
2. SQLite. *Appropriate Uses For SQLite*. https://www.sqlite.org/whentouse.html
3. Google Workspace Updates. *Google Sheets doubles cell limit*. https://workspaceupdates.googleblog.com/2022/03/ten-million-cells-google-sheets.html
