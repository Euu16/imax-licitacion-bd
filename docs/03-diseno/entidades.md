# Fase de identificación de entidades y atributos
--ENTIDADES--

* Funciones: cartelera como tal no es una entidad (es una vista, que presenta las funciones en imax cinema). Con atributos: id_funcion,horarios(podria ser compuesta, pero con un timestamp se llena completa),estado(solo uno posible)
*Pelicula: con atributos de id_pelicula,titulo, sinopsis, clasificacion de edad, duracion y genero.  PERO NOTE QUE PELICULA SI ES UNA ENTIDAD FUERTE, PERO LA FUNCION SE DEBE RELACIONAR CON LA PELICULA, PERO LA FUNCION DEPENDE DE QUE HAYA PELICULA, ENTONCES DEBE HABER UNA FK  
*Sala: id_sala, num_sala, ubicacion_sala   (LO MISMO ACÁ, SE NECESITARÁ UNA FK  )    


* RN-01 + RN-02> -> para cumplir esta regla necesito guardar: detalles relacionados a cada película que se reproduce (basado en películas activas y no se hayan reproducido). Entidad: pelicula (detallada anteriormente) con atributos: id_pelicula,titulo,sinopsis,clasificacion_edad,duracion,estado

* Basado en el contexto del negocio brindado, en el cual mencionan que tienen cines por todo el mundo, podemos agregar lo siguiente
Necesito la entidad sucursal_cine con atributos: id_sucursal,nombre_sucursal,ubicacion, pais,ciudad
y ademas, la entidad sala con atributos: id_sala, nombre_sala, capacidad_total y una FK que apunta a cine_id, lo cual haría cine_id[FK]

| Regla Base | Se necesita guardar | Entidades Necesarias |
|     ---    |         ---         |         ---          |
| RN-01      |  programaciones de funciones relacionada con una película en x sala con su horario completo específico | funcion: con atributos: id_funcion,id_pelicula[FK] (porque una funcion depende de que haya pelicula),fecha_hora_inicio,estado_funcion|
|RN-03     | conocer si un asientos está ocupado o no físicamente por cada sala y conocer su distribución | asiento, con atributos: id_asiento,id_sala[FK] (pues se necesita referenciar la sala para los asientos),fila,numero, zona|
| RN-03, RN-04 y RN-05 |estado que se refleja temporalmente acerca de los asientos, en el momento que usuario interacciona con mapa en la app|asientos_en_funcion con atributos: id_funcion[PK,FK],id_asiento[PK,FK],estado, id_reservacion_temporal_usuario,expiracion_bloqueo (este debería ser un timestamp y lo vamos a fijar en 2 minutos) |
|RN-06,RN-07 y RN-08 | información acerca de las tarifas por cada tipo de usuario, pues puede variar si son niños, estudiantes o tercera edad y todo lo relacionado a descuentos | tarifas con atributos: id_tarifa[PK],tipo_perfil (a este luego se le hará un constraint para verificar que solo este en uno de los posibles perfiles), precio_base. Además tenemos promociones con atributos: id_promocion[PK],nombre_promocion,tipo_regla, descuento_en_porcentaje,condicion_minima (no se debe incluir una FK acá, pues el precio final se calcula con la unión de ambas tablas)|
|RN-09|los intentos de pago relacionado con la respuesta de la pasarela y que no se almacene en la BD datos sensibles del usuario, ademas necesitamos tener una tabla específica para identificar a los distintos usuarios(cliente, operador de sala, etc) y otra aparte para el rol del usuario| usuarios con atributos:id_usuario[PK],nombre,correo,telefonos, id_rol[FK],contraseña_en_hash (porque si se pone un atributo de contraseña seria poco seguro en caso de ataques a la BD),fecha_registro. Otra entidad "operacion_pago" con atributos: id_transaccion[PK], id_usuario[FK],monto_total_a_pagar,metodo_de_pago,estado_pago(solo puede ser uno de 3 posibles, se hace un constraint para este atributo),token_de_pasarela (para cumplir con temas de seguridad),fecha_operacion. Y por último la entidad rol con atributos: id_rol[Pk], nombre_rol (para identificar si es operador de salas, algun cliente, taquilleros, etc), descripcion |