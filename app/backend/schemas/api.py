from datetime import datetime, time
from decimal import Decimal
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

class StaffIn(BaseModel):
    nombre: str = Field(min_length=1,max_length=150)
    correo: EmailStr
    role: str = Field(pattern="^(cliente|taquillero|operador de sala|contador)$")
    password: str = Field(min_length=12,max_length=200)

class LoginIn(BaseModel):
    username: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=200)

class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"

class RegisterIn(BaseModel):
    nombre: str = Field(min_length=1, max_length=150)
    correo: EmailStr
    telefono: str | None = Field(default=None, max_length=30)
    password: str = Field(min_length=12, max_length=200)

class SeatChoice(BaseModel):
    id_asiento: int = Field(gt=0)
    id_tipo_entrada: int = Field(gt=0)

class PurchaseIn(BaseModel):
    id_funcion: int = Field(gt=0)
    asientos: list[SeatChoice] = Field(min_length=1, max_length=6)
    id_metodo_pago: int = Field(gt=0)
    pago_aprobado: bool = True
    promocion_id: int | None = Field(default=None, gt=0)

    @field_validator("asientos")
    @classmethod
    def unique_seats(cls, rows):
        ids = [x.id_asiento for x in rows]
        if len(ids) != len(set(ids)): raise ValueError("Asientos duplicados")
        return rows

class ReservationIn(BaseModel):
    id_funcion: int = Field(gt=0)
    id_asientos: list[int] = Field(min_length=1,max_length=6)

    @field_validator("id_asientos")
    @classmethod
    def unique_ids(cls, values):
        if len(values)!=len(set(values)): raise ValueError("Asientos duplicados")
        return values

class BoxOfficeIn(PurchaseIn):
    id_usuario_cliente: int | None = Field(default=None,gt=0)

class CheckinIn(BaseModel):
    codigo_qr: str = Field(min_length=1,max_length=64)
    id_dispositivo: int = Field(gt=0)
    credencial_validada: bool = True

class CourtesyIn(BaseModel):
    id_funcion: int = Field(gt=0)
    asientos: list[SeatChoice] = Field(min_length=1,max_length=6)
    id_usuario_cliente: int | None = Field(default=None,gt=0)

    @field_validator("asientos")
    @classmethod
    def unique_courtesy_seats(cls, rows):
        ids=[x.id_asiento for x in rows]
        if len(ids)!=len(set(ids)): raise ValueError("Asientos duplicados")
        return rows

class RefundIn(BaseModel):
    id_pago: int = Field(gt=0)
    id_boleto: int | None = Field(default=None, gt=0)
    monto: Decimal = Field(gt=0, max_digits=12, decimal_places=2)
    motivo: str = Field(min_length=5, max_length=1000)
    forzado: bool = False

class MovieIn(BaseModel):
    titulo: str = Field(min_length=1, max_length=200)
    sinopsis: str = Field(max_length=20000)
    clasificacion_edad: str = Field(max_length=30)
    duracion_minutos: int = Field(gt=0, le=600)
    poster_url: str = Field(max_length=2048)
    pelicula_esta_activa: bool = True

class FunctionIn(BaseModel):
    id_pelicula: int = Field(gt=0)
    id_sala: int = Field(gt=0)
    fecha_hora_inicio: datetime
    fecha_hora_fin: datetime

class TariffIn(BaseModel):
    id_pais: int = Field(gt=0); id_zona: int = Field(gt=0); id_tipo_entrada: int = Field(gt=0)
    id_franja: int = Field(gt=0); dia_semana: int = Field(ge=0, le=6); precio_base: Decimal = Field(ge=0, max_digits=12, decimal_places=2)

class PromotionIn(BaseModel):
    nombre_promocion: str = Field(min_length=1, max_length=110)
    tipo_regla: str
    descuento_pct: Decimal | None = Field(default=None, ge=0, le=100)
    condicion_minima: int = Field(default=1, ge=1)
    dia_semana: int | None = Field(default=None, ge=0, le=6)
    activa: bool = True

    @field_validator("tipo_regla")
    @classmethod
    def promotion_type(cls, value):
        if value not in {"2x1", "descuento_dia"}: raise ValueError("Tipo de promoción inválido")
        return value

class CountryIn(BaseModel):
    nombre: str = Field(min_length=1,max_length=110)
    moneda: str = Field(pattern="^[A-Z]{3}$")

class CityIn(BaseModel):
    id_pais: int = Field(gt=0)
    nombre: str = Field(min_length=1,max_length=150)

class GenreIn(BaseModel):
    nombre: str = Field(min_length=1,max_length=50)

class TimeBandIn(BaseModel):
    nombre: str = Field(min_length=1,max_length=50)
    hora_inicio: time
    hora_fin: time

class MovieOut(BaseModel):
    id_pelicula: int
    titulo: str
    sinopsis: str | None = None
    clasificacion_edad: str
    duracion_minutos: int
    poster_url: str | None = None
    generos: str = ""


class SeatOut(BaseModel):
    id_asiento: int
    fila: str | None = None
    numero: int | None = None
    zona: str | None = None
    estado: str | None = None
    expiracion_bloqueo: datetime | None = None


class PurchaseOut(BaseModel):
    id_orden: int
    id_pago: int
    estado_orden: str
    estado_pago: str
    subtotal: Decimal
    descuento: Decimal
    cargo_servicio: Decimal
    total: Decimal
    moneda: str
    simulacion_academica: bool
    reintento: bool
    boletos: list[dict]


class TicketOut(BaseModel):
    id_boleto: int
    id_funcion: int
    id_asiento: int
    codigo_qr: str
    estado_boleto: str
    precio_final: Decimal
    fecha_emision: datetime


class AvailabilityOut(BaseModel):
    id_funcion: int
    asientos: list[SeatOut]
