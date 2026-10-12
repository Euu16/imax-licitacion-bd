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
| RN-03, RN-04 y RN-05 |estado que se refleja temporalmente acerca de los asientos, en el momento que usuario interacciona con mapa en la app|asientos_en_funcion con atributos: id_funcion[PK,FK],id_asiento[PK,FK],estado, id_reservacion_temporal_usuario,expiracion_bloqueo (este debería ser un timestamp y lo vamos a fijar en 2 minutos)