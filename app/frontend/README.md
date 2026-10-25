# Frontend IMAX

Interfaz web académica conectada al backend FastAPI del proyecto.

## Iniciar

Desde la carpeta raíz del repositorio:

```powershell
py -m uvicorn app.backend.main:app --reload
```

Abre <http://127.0.0.1:8000/>. La documentación interactiva de la API sigue disponible en <http://127.0.0.1:8000/docs>.

## Qué incluye

- Cartelera con búsqueda por título y filtro por género.
- Próximas funciones con filtro por cine o ciudad.
- Registro e inicio de sesión de clientes.
- Consulta de disponibilidad y selección de hasta seis asientos.
- Compra con pago simulado y acceso al QR del boleto.

La compra usa el método de entrada y el método de pago disponibles en la base de datos. El pago es solo una simulación académica; no se procesa dinero real. Para que haya contenido visible, la base debe tener películas, funciones futuras, asientos, tipos de entrada y métodos de pago cargados.
