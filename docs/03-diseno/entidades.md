# Fase de identificación de entidades y atributos
--ENTIDADES--

* Funciones: cartelera como tal no es una entidad (es una vista, que presenta las funciones en imax cinema). Con atributos: id_funcion,horarios(podria ser compuesta, pero con un timestamp se llena completa),estado(solo uno posible)
*Pelicula: con atributos de id_pelicula,titulo, sinopsis, clasificacion de edad, duracion y genero.  PERO NOTE QUE PELICULA SI ES UNA ENTIDAD FUERTE, PERO LA FUNCION SE DEBE RELACIONAR CON LA PELICULA, PERO LA FUNCION DEPENDE DE QUE HAYA PELICULA, ENTONCES DEBE HABER UNA FK  
*Sala: id_sala, num_sala, ubicacion_sala   (LO MISMO ACÁ, SE NECESITARÁ UNA FK  )    


* RN-01 + RN-02> -> para cumplir esta regla necesito guardar: detalles relacionados a cada película que se reproduce (basado en películas activas y no se hayan reproducido). Entidad: pelicula (detallada anteriormente)

* Basado en el contexto del negocio brindado, en el cual mencionan que tienen cines por todo el mundo, podemos agregar lo siguiente
Necesito la entidad sucursal_cine con atributos: id_sucursal,nombre_sucursal,ubicacion, pais,ciudad
y ademas, la entidad sala con atributos: id_sala, nombre_sala, capacidad_total. 

| Regla Base | Entidades necesarias |