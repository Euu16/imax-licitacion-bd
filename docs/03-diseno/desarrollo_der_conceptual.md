# Diseño Conceptual de la Base de Datos

**Proyecto:** Licitación para el Ecosistema Digital de Cines IMAX
**Fase:** 3, Diseño de la Base de Datos (nivel conceptual)

El diseño conceptual describe **qué información maneja el negocio y cómo se relaciona**, sin comprometerse con tipos de dato, llaves ni tablas físicas. Por eso aquí las relaciones de muchos a muchos aparecen tal como son en el negocio. El diseño lógico (`der.md`) las convierte en tablas con llaves, y el físico (`01_schema.sql`) las implementa en PostgreSQL.


---

## 1. Diagrama Entidad-Relación conceptual