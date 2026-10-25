**Implementacion y Pruebas**

# 1.Implementación realizada
Se utilizó PostgreSQL para motor de bases de datos, ademas de una API desarrollada con FastAPI y una interfaz web de apoyo para las consultas y reservas de asientos

La base de datos contiene las entidades necesarias para representar películas, cines, salas, asientos, funciones, usuarios, órdenes, pagos, boletos y bitácoras. Las relaciones se protegen con llaves primarias y foráneas, y las reglas que dependen del estado de los datos se controlan mediante restricciones, funciones y triggers.

La API tiene operaciones de POST, GET, DELETE entre otras. Se puede consultar acerca de disponibilidad de asientos, cines, funciones, salas, ordenes,pagos simulados, etc.Las relaciones estan protegido por PK´s y FK´S. Ademas los pagos son simulados

# 2. Método de prueba
Las pruebas se realizaron contra la base de datos PostgreSQL local y la API ejecutándose en el equipo de desarrollo. Para comprobar los flujos se usaron Swagger, consultas SQL en DBeaver y una prueba automatizada en Python.
Se dividen asi:
1- comprobacion de funcionamiento y conexion de API (debe conectarse con el motor de base de datos)
2- luego se hacen pruebas funcionales
3- pruebas de integridad: comprobar que llaves foraneas y todas las restricciones impuestas
4- luego se realizan pruebas de concurrencia que verifican que no haya doble venta en un mismo boleto.

|Caso|Procedimiento|Resultado observado|Estado|
|--- |     ---     |       ---         |  --- |
|Conexion con BD| Consultar el endpoint de salud de la API|esto verificó que estaba conectada al motor| Aprobado|
|consultas de peliculas y funciones| registrar peliculas, horarios, funciones desde configuracion de API y frontend|Se recibieron respuestas exitosas y funciones se ven en app|Aprobado para pruebas funcionales|
|Consulta de disponibilidad|consultar asientos de funcion|Se recibieron los asientos y su estado. Todo esto incluye bloqueado y disponible en estado|Aprobado|
|Registro e inicio de sesion| registrar cuenta de prueba y autenticarla| registro respondió correctamente y Swagger permitió autenticar la cuenta|Aprobado|
|Reserva de asiento|Enviar una solicitud autenticada para reservar un asiento| Una solicitud recibió UTTP 201| Aprobado para el caso de prueba|
|Concurrencia sobre mismo asiento| Enviar 30 solicitudes simultáneas para reservar mismo asiento| Se dio respuesta `201` y 29 resultados `409 Conflict`| Aprobado para este caso|
|Liberacion de reserva|Liberar un asiento reservado y volver a tener su disponibilidad|El asiento dejó de aparecer bloqueado|Aprobado para caso ejecutado|
|Compra y generacion de boleto| Completar una compra simulada para fines académicos|Se genera boleto y el QR random respectivo|Aprobado para cada caso|



