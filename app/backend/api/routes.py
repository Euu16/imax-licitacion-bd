from __future__ import annotations
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
import base64, secrets
import qrcode
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Response, status
from fastapi.responses import StreamingResponse
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session
from ..core.config import settings
from ..core.security import admin, admin_or_door, admin_or_teller, cashier_finance, cashier_sale, client_checkout, current_user, finance_reader, issue_token, verify_password
from ..database import get_db
from ..schemas.api import (CheckinIn, BoxOfficeIn, CourtesyIn, FunctionIn, LoginIn, MovieIn, PromotionIn, PurchaseIn, RegisterIn, RefundIn, ReservationIn, StaffIn, TariffIn, TicketOut, MovieOut, PurchaseOut, SeatOut, CountryIn, CityIn, GenreIn, TimeBandIn, AvailabilityOut, TokenOut)
from ..services.pricing import quote_seats

app = FastAPI(title="IMAX Licitación BD API", version="1.0.0", description="Backend académico. El pago es una simulación controlada.")

@app.exception_handler(IntegrityError)
def integrity_error_handler(request, exc):
    return Response(status_code=409, content='{"detail":"La operación contradice una restricción de integridad o disponibilidad."}', media_type="application/json")

@app.get("/health")
def health(db: Session = Depends(get_db)):
    db.execute(text("SELECT 1"))
    return {"status": "ok", "database": "connected"}

@app.post("/api/v1/auth/register", status_code=201)
def register(payload: RegisterIn, db: Session = Depends(get_db)):
    from ..core.security import hash_password
    role = db.execute(text("SELECT id_rol FROM rol WHERE nombre_rol='cliente'")).scalar_one_or_none()
    if role is None: raise HTTPException(503, "Falta el rol cliente en el esquema")
    try:
        row = db.execute(text("INSERT INTO usuario(id_rol,nombre_usuario,correo,telefono,contrasena_hash) VALUES(:role,:name,lower(:email),:phone,:hash) RETURNING id_usuario"),
                         {"role": role,"name":payload.nombre,"email":payload.correo,"phone":payload.telefono,"hash":hash_password(payload.password)}).scalar_one()
        db.commit()
    except IntegrityError: db.rollback(); raise HTTPException(409, "El correo ya está registrado")
    return {"id_usuario": row, "correo": payload.correo.lower()}

@app.post("/api/v1/auth/token", response_model=TokenOut)
def login(payload: LoginIn, db: Session = Depends(get_db)):
    row = db.execute(text("SELECT u.id_usuario,u.contrasena_hash,r.nombre_rol FROM usuario u JOIN rol r USING(id_rol) WHERE lower(u.correo)=lower(:email) AND u.usuario_esta_activo"), {"email":payload.username}).mappings().first()
    if not row or not verify_password(payload.password, row["contrasena_hash"]): raise HTTPException(401, "Correo o contraseña inválidos", headers={"WWW-Authenticate":"Bearer"})
    return TokenOut(access_token=issue_token(row["id_usuario"], row["nombre_rol"]))

@app.get("/api/v1/movies",response_model=list[MovieOut])
def movies(q: str | None = Query(default=None, max_length=200), genre: str | None = Query(default=None, max_length=50), limit:int=Query(100,ge=1,le=500), db: Session = Depends(get_db)):
    return list(db.execute(text("""SELECT p.id_pelicula,p.titulo,p.sinopsis,p.clasificacion_edad,p.duracion_minutos,p.poster_url,
      COALESCE(string_agg(DISTINCT g.nombre_genero, ', ' ORDER BY g.nombre_genero),'') AS generos
      FROM pelicula p LEFT JOIN pelicula_genero pg USING(id_pelicula) LEFT JOIN genero g USING(id_genero)
      WHERE p.pelicula_esta_activa AND (CAST(:q AS text) IS NULL OR p.titulo ILIKE '%'||CAST(:q AS text)||'%')
        AND (CAST(:genre AS text) IS NULL OR EXISTS (SELECT 1 FROM pelicula_genero x JOIN genero y USING(id_genero) WHERE x.id_pelicula=p.id_pelicula AND y.nombre_genero ILIKE CAST(:genre AS text)))
      GROUP BY p.id_pelicula ORDER BY p.titulo LIMIT :limit"""), {"q":q,"genre":genre,"limit":limit}).mappings())

@app.get("/api/v1/showtimes")
def showtimes(city: str | None = Query(default=None,max_length=150), cinema_id: int | None = Query(default=None,gt=0),
              on: date | None = None, genre: str | None = Query(default=None,max_length=50), movie_id: int | None = Query(default=None,gt=0), limit:int=Query(100,ge=1,le=500), offset:int=Query(0,ge=0), db: Session=Depends(get_db)):
    return list(db.execute(text("""SELECT f.id_funcion,f.fecha_hora_inicio,f.fecha_hora_fin,p.id_pelicula,p.titulo,p.clasificacion_edad,p.duracion_minutos,ci.id_cine,ci.nombre_cine AS cine,ci.zona_horaria,cd.id_ciudad,cd.nombre_ciudad AS ciudad,pa.nombre AS pais,pa.moneda
      FROM funcion f JOIN pelicula p USING(id_pelicula) JOIN sala s USING(id_sala) JOIN cine ci USING(id_cine) JOIN ciudad cd USING(id_ciudad) JOIN pais pa USING(id_pais)
      WHERE (CAST(:city AS text) IS NULL OR ci.nombre_cine ILIKE CAST(:city AS text) OR cd.nombre_ciudad ILIKE CAST(:city AS text) OR pa.nombre ILIKE CAST(:city AS text))
      AND (CAST(:cinema AS integer) IS NULL OR ci.id_cine=CAST(:cinema AS integer))
      AND (CAST(:on AS date) IS NULL OR (f.fecha_hora_inicio AT TIME ZONE ci.zona_horaria)::date=CAST(:on AS date))
      AND (CAST(:movie AS integer) IS NULL OR f.id_pelicula=CAST(:movie AS integer))
      AND (CAST(:genre AS text) IS NULL OR EXISTS(SELECT 1 FROM pelicula_genero pg JOIN genero g USING(id_genero) WHERE pg.id_pelicula=f.id_pelicula AND g.nombre_genero ILIKE CAST(:genre AS text)))
      AND f.estado_funcion='programada'
      ORDER BY f.fecha_hora_inicio LIMIT :limit OFFSET :offset"""), {"city": f"%{city}%" if city else None,"cinema":cinema_id,"on":on,"genre":genre,"movie":movie_id,"limit":limit,"offset":offset}).mappings())

@app.get("/api/v1/functions/{function_id}/seats",response_model=list[SeatOut])
def function_seats(function_id: int, limit:int=Query(500,ge=1,le=2000), db: Session=Depends(get_db)):
    rows = db.execute(text("SELECT a.id_asiento,a.fila,a.numero,a.id_zona,z.nombre_zona AS zona,COALESCE(e.estado,'disponible') AS estado,e.expiracion_bloqueo FROM funcion f JOIN sala s USING(id_sala) JOIN asiento a USING(id_sala) JOIN zona z USING(id_zona) LEFT JOIN estado_asiento_funcion e ON e.id_funcion=f.id_funcion AND e.id_asiento=a.id_asiento WHERE f.id_funcion=:id ORDER BY a.fila,a.numero LIMIT :limit"), {"id":function_id,"limit":limit}).mappings().all()
    if not rows: raise HTTPException(404,"Función no encontrada o la sala no tiene asientos")
    return list(rows)

@app.get("/api/v1/rooms/{room_id}")
def room(room_id: int, db: Session=Depends(get_db)):
    head = db.execute(text("SELECT s.id_sala,s.id_cine,s.nombre_sala,s.capacidad_total,s.sala_esta_activa FROM sala s WHERE s.id_sala=:id"), {"id":room_id}).mappings().first()
    if not head: raise HTTPException(404,"Sala no encontrada")
    seats = db.execute(text("SELECT a.id_asiento,a.fila,a.numero,a.id_zona,z.nombre_zona AS zona FROM asiento a JOIN zona z USING(id_zona) WHERE a.id_sala=:id ORDER BY a.fila,a.numero"), {"id":room_id}).mappings().all()
    return {**head,"asientos":list(seats)}

@app.get("/api/v1/functions/{function_id}/availability",response_model=AvailabilityOut)
def availability(function_id: int, limit:int=Query(500,ge=1,le=2000), db: Session=Depends(get_db)):
    rows=db.execute(text("SELECT a.id_asiento,a.fila,a.numero,a.id_zona,z.nombre_zona AS zona,COALESCE(e.estado,'disponible') AS estado,e.expiracion_bloqueo FROM funcion f JOIN sala s USING(id_sala) JOIN asiento a USING(id_sala) JOIN zona z USING(id_zona) LEFT JOIN estado_asiento_funcion e ON e.id_funcion=f.id_funcion AND e.id_asiento=a.id_asiento WHERE f.id_funcion=:id ORDER BY a.fila,a.numero LIMIT :limit"),{"id":function_id,"limit":limit}).mappings().all()
    if not rows: raise HTTPException(404,"Función no encontrada o sin asientos")
    return {"id_funcion":function_id,"asientos":list(rows)}

@app.post("/api/v1/functions/{function_id}/reservations", status_code=201)
def reserve_seats(function_id:int,payload:ReservationIn,user=Depends(client_checkout),db:Session=Depends(get_db)):
    if payload.id_funcion!=function_id: raise HTTPException(422,"La función de la ruta y el cuerpo no coincide")
    if user.role!="cliente": raise HTTPException(403,"Solo clientes pueden reservar por web")
    try:
        db.execute(text("SELECT reservar_asientos(:fn,CAST(:ids AS integer[]),:uid)"),{"fn":function_id,"ids":payload.id_asientos,"uid":user.id})
        info=db.execute(text("SELECT min(e.expiracion_bloqueo) expira_en,c.bloqueo_minutos*60 duracion_segundos FROM estado_asiento_funcion e CROSS JOIN configuracion c WHERE e.id_funcion=:fn AND e.id_usuario=:uid AND e.id_asiento=ANY(CAST(:ids AS integer[])) AND e.estado='bloqueado' GROUP BY c.bloqueo_minutos"),{"fn":function_id,"uid":user.id,"ids":payload.id_asientos}).mappings().one()
        db.commit(); return {"id_funcion":function_id,"id_asientos":payload.id_asientos,"expira_en":info["expira_en"],"duracion_segundos":info["duracion_segundos"]}
    except (IntegrityError,SQLAlchemyError) as ex: db.rollback(); raise HTTPException(409,"Uno o más asientos no están disponibles") from ex

@app.delete("/api/v1/functions/{function_id}/reservations")
def release_seats(function_id:int,ids:list[int]=Query(min_length=1,max_length=6),user=Depends(current_user),db:Session=Depends(get_db)):
    count=db.execute(text("SELECT liberar_asientos(:fn,CAST(:ids AS integer[]),:uid)"),{"fn":function_id,"ids":ids,"uid":user.id}).scalar_one()
    db.commit(); return {"bloqueos_liberados":count}

@app.post("/api/v1/purchases", status_code=201, response_model=PurchaseOut)
def purchase(payload: PurchaseIn, idem: str | None = Header(default=None, alias="Idempotency-Key"),
             user=Depends(client_checkout), db: Session=Depends(get_db)):
    if user.role != "cliente": raise HTTPException(403,"Este canal de compra no está habilitado para el rol")
    if not settings.payment_simulation_enabled: raise HTTPException(503,"La simulación de pagos está deshabilitada")
    idem = idem or secrets.token_urlsafe(24)
    if len(idem)>150: raise HTTPException(422,"Idempotency-Key demasiado largo")
    simulator_token="academic-simulation:"+str(user.id)+":"+idem
    try:
        db.execute(text("SELECT pg_advisory_xact_lock(hashtextextended(:key,0))"), {"key":idem})
        old=db.execute(text("SELECT o.id_orden,p.id_pago,o.estado_orden,p.estado_pago,o.subtotal,o.descuento,o.cargo_servicio,o.total,o.moneda,(m.nombre_metodo_pago<>'efectivo') simulacion_academica,TRUE reintento,coalesce(json_agg(json_build_object('id_boleto',b.id_boleto,'codigo_qr',b.codigo_qr::text,'id_asiento',b.id_asiento)) FILTER (WHERE b.id_boleto IS NOT NULL),'[]') boletos FROM pago p JOIN orden o USING(id_orden) LEFT JOIN boleto b USING(id_orden) WHERE p.token_pasarela=:token AND o.id_usuario=:uid GROUP BY o.id_orden,p.id_pago"),{"token":simulator_token,"uid":user.id}).mappings().first()
        if old:
            db.commit(); return dict(old)
        # En el esquema recibido el cliente web se identifica como titular del bloqueo.
        ids=[x.id_asiento for x in payload.asientos]
        db.execute(text("SELECT reservar_asientos(:fn,CAST(:ids AS integer[]),:uid)"), {"fn":payload.id_funcion,"ids":ids,"uid":user.id})
        context=db.execute(text("""SELECT f.fecha_hora_inicio,ci.zona_horaria,pa.moneda FROM funcion f JOIN sala s USING(id_sala) JOIN cine ci USING(id_cine) JOIN ciudad cd USING(id_ciudad) JOIN pais pa USING(id_pais) WHERE f.id_funcion=:fn AND f.estado_funcion='programada'"""),{"fn":payload.id_funcion}).mappings().first()
        if not context: raise HTTPException(404,"Función no disponible")
        quote=quote_seats(db,payload.id_funcion,payload.asientos,context["fecha_hora_inicio"],context["zona_horaria"],payload.promocion_id)
        tickets=quote["tickets"]; subtotal=quote["subtotal"]; discount=quote["discount"]; promo=quote["promotion"]
        cfg=db.execute(text("SELECT cargo_servicio_porcentaje,max_asientos_en_orden FROM configuracion WHERE id_configuracion=1")).mappings().one()
        if len(tickets)>cfg["max_asientos_en_orden"]: raise HTTPException(422,"Máximo de asientos excedido")
        fee=((subtotal-discount)*Decimal(cfg["cargo_servicio_porcentaje"])/Decimal(100)).quantize(Decimal("0.01"),rounding=ROUND_HALF_UP)
        total=subtotal-discount+fee
        method=db.execute(text("SELECT nombre_metodo_pago FROM metodo_pago WHERE id_metodo_pago=:id"),{"id":payload.id_metodo_pago}).scalar_one_or_none()
        if not method or method in {"efectivo","cortesia"}: raise HTTPException(422,"Método de pago no permitido para checkout web")
        if total<=0: raise HTTPException(422,"El esquema requiere el método cortesía para una orden de monto cero")
        order_id=db.execute(text("""INSERT INTO orden(id_usuario,id_funcion,id_promocion,canal,estado_orden,subtotal,descuento,cargo_servicio,total,moneda)
          VALUES(:uid,:fn,:promo,'web','pendiente',:sub,:disc,:fee,:total,:currency) RETURNING id_orden"""),{"uid":user.id,"fn":payload.id_funcion,"promo":promo["id_promocion"] if promo else None,"sub":subtotal,"disc":discount,"fee":fee,"total":total,"currency":context["moneda"]}).scalar_one()
        payment_state="aprobado" if payload.pago_aprobado else "rechazado"
        payment_id=db.execute(text("INSERT INTO pago(id_orden,id_metodo_pago,estado_pago,monto,token_pasarela) VALUES(:order,:method,:state,:amount,:token) RETURNING id_pago"),{"order":order_id,"method":payload.id_metodo_pago,"state":payment_state,"amount":total,"token":simulator_token}).scalar_one()
        if payload.pago_aprobado:
            for t in tickets:
                db.execute(text("INSERT INTO boleto(id_orden,id_funcion,id_asiento,id_tipo_entrada,precio_final,origen) VALUES(:order,:fn,:seat,:type,:price,'online')"),{"order":order_id,"fn":payload.id_funcion,"seat":t["seat"],"type":t["type"],"price":t["final_price"]})
        else:
            db.execute(text("UPDATE orden SET estado_orden='fallida' WHERE id_orden=:id"),{"id":order_id})
            db.execute(text("SELECT liberar_asientos(:fn,CAST(:ids AS integer[]),:uid)"),{"fn":payload.id_funcion,"ids":ids,"uid":user.id})
        tickets_out=db.execute(text("SELECT id_boleto,id_asiento,codigo_qr::text FROM boleto WHERE id_orden=:id ORDER BY id_boleto"),{"id":order_id}).mappings().all()
        db.commit()
        return {"id_orden":order_id,"id_pago":payment_id,"estado_orden":"pagada" if payload.pago_aprobado else "fallida","estado_pago":payment_state,"subtotal":subtotal,"descuento":discount,"cargo_servicio":fee,"total":total,"moneda":context["moneda"],"simulacion_academica":True,"reintento":False,"boletos":[dict(t) for t in tickets_out]}
    except HTTPException:
        db.rollback(); raise
    except (IntegrityError, SQLAlchemyError) as ex:
        db.rollback(); raise HTTPException(409,"La reserva no se pudo completar; los cambios fueron revertidos") from ex

@app.post("/api/v1/box-office/purchases", status_code=201, response_model=PurchaseOut)
def box_office_purchase(payload:BoxOfficeIn,idem:str|None=Header(default=None,alias="Idempotency-Key"),user=Depends(cashier_sale),db:Session=Depends(get_db)):
    if user.role!="taquillero": raise HTTPException(403,"Este flujo está reservado al personal de taquilla")
    idem=idem or secrets.token_urlsafe(24)
    if len(idem)>150: raise HTTPException(422,"Idempotency-Key demasiado largo")
    idem=f"taquilla:{user.id}:{idem}"
    try:
        db.execute(text("SELECT pg_advisory_xact_lock(hashtextextended(:key,0))"),{"key":idem})
        old=db.execute(text("""SELECT o.id_orden,p.id_pago,o.estado_orden,p.estado_pago,o.subtotal,o.descuento,o.cargo_servicio,o.total,o.moneda,
          (m.nombre_metodo_pago<>'efectivo') simulacion_academica,TRUE reintento,coalesce(json_agg(json_build_object('id_boleto',b.id_boleto,'codigo_qr',b.codigo_qr::text,'id_asiento',b.id_asiento)) FILTER (WHERE b.id_boleto IS NOT NULL),'[]') boletos
          FROM transaccion_log l JOIN orden o ON o.id_orden=l.id_orden JOIN pago p ON p.id_orden=o.id_orden JOIN metodo_pago m USING(id_metodo_pago)
          LEFT JOIN boleto b ON b.id_orden=o.id_orden WHERE l.evento='solicitud_taquilla' AND l.detalle->>'clave_idempotencia'=:key
          GROUP BY o.id_orden,p.id_pago,m.nombre_metodo_pago"""),{"key":idem}).mappings().first()
        if old: db.commit(); return dict(old)
        ids=[x.id_asiento for x in payload.asientos]
        db.execute(text("SELECT reservar_asientos(:fn,CAST(:ids AS integer[]),:uid)"),{"fn":payload.id_funcion,"ids":ids,"uid":user.id})
        customer=payload.id_usuario_cliente
        if customer is None:
            customer=db.execute(text("SELECT u.id_usuario FROM usuario u JOIN rol r USING(id_rol) WHERE r.nombre_rol='cliente_mostrador' AND u.usuario_esta_activo")).scalar_one_or_none()
        if customer is None: raise HTTPException(503,"No existe el usuario genérico cliente_mostrador")
        context=db.execute(text("SELECT f.fecha_hora_inicio,ci.zona_horaria,pa.moneda FROM funcion f JOIN sala s USING(id_sala) JOIN cine ci USING(id_cine) JOIN ciudad cd USING(id_ciudad) JOIN pais pa USING(id_pais) WHERE f.id_funcion=:fn AND f.estado_funcion='programada'"),{"fn":payload.id_funcion}).mappings().first()
        if not context: raise HTTPException(404,"Función no disponible")
        quote=quote_seats(db,payload.id_funcion,payload.asientos,context["fecha_hora_inicio"],context["zona_horaria"],payload.promocion_id)
        tickets=quote["tickets"]; subtotal=quote["subtotal"]; discount=quote["discount"]; promo=quote["promotion"]
        cfg=db.execute(text("SELECT cargo_servicio_porcentaje,max_asientos_en_orden FROM configuracion WHERE id_configuracion=1")).mappings().one()
        if len(tickets)>min(6,cfg["max_asientos_en_orden"]): raise HTTPException(422,"Máximo de seis asientos excedido")
        fee=((subtotal-discount)*Decimal(cfg["cargo_servicio_porcentaje"])/Decimal(100)).quantize(Decimal("0.01"),rounding=ROUND_HALF_UP)
        total=subtotal-discount+fee
        method=db.execute(text("SELECT nombre_metodo_pago FROM metodo_pago WHERE id_metodo_pago=:id"),{"id":payload.id_metodo_pago}).scalar_one_or_none()
        if not method or method=="cortesia": raise HTTPException(422,"La cortesía se otorga únicamente mediante el flujo administrativo")
        if total<=0: raise HTTPException(422,"El esquema requiere que un pago de monto cero use el método cortesía")
        approved=True if method=="efectivo" else payload.pago_aprobado
        order_id=db.execute(text("INSERT INTO orden(id_usuario,vendedor_asociado,id_funcion,id_promocion,canal,estado_orden,subtotal,descuento,cargo_servicio,total,moneda) VALUES(:customer,:seller,:fn,:promo,'taquilla','pendiente',:sub,:disc,:fee,:total,:currency) RETURNING id_orden"),{"customer":customer,"seller":user.id,"fn":payload.id_funcion,"promo":promo["id_promocion"] if promo else None,"sub":subtotal,"disc":discount,"fee":fee,"total":total,"currency":context["moneda"]}).scalar_one()
        db.execute(text("INSERT INTO transaccion_log(id_orden,evento,monto,moneda,detalle) VALUES(:order,'solicitud_taquilla',:amount,:currency,jsonb_build_object('clave_idempotencia',:key,'id_vendedor',:seller))"),{"order":order_id,"amount":total,"currency":context["moneda"],"key":idem,"seller":user.id})
        token=None if method=="efectivo" else "academic-simulation:"+idem
        payment_id=db.execute(text("INSERT INTO pago(id_orden,id_metodo_pago,estado_pago,monto,token_pasarela) VALUES(:order,:method,:state,:amount,:token) RETURNING id_pago"),{"order":order_id,"method":payload.id_metodo_pago,"state":"aprobado" if approved else "rechazado","amount":total,"token":token}).scalar_one()
        if approved:
            for ticket in tickets: db.execute(text("INSERT INTO boleto(id_orden,id_funcion,id_asiento,id_tipo_entrada,precio_final,origen) VALUES(:order,:fn,:seat,:type,:price,'taquilla')"),{"order":order_id,"fn":payload.id_funcion,"seat":ticket["seat"],"type":ticket["type"],"price":ticket["final_price"]})
        else:
            db.execute(text("UPDATE orden SET estado_orden='fallida' WHERE id_orden=:id"),{"id":order_id})
            db.execute(text("SELECT liberar_asientos(:fn,CAST(:ids AS integer[]),:uid)"),{"fn":payload.id_funcion,"ids":ids,"uid":user.id})
        issued=db.execute(text("SELECT id_boleto,id_asiento,codigo_qr::text FROM boleto WHERE id_orden=:id"),{"id":order_id}).mappings().all()
        db.commit()
        return {"id_orden":order_id,"id_pago":payment_id,"estado_orden":"pagada" if approved else "fallida","estado_pago":"aprobado" if approved else "rechazado","subtotal":subtotal,"descuento":discount,"cargo_servicio":fee,"total":total,"moneda":context["moneda"],"simulacion_academica":method!="efectivo","reintento":False,"boletos":[dict(x) for x in issued]}
    except HTTPException: db.rollback(); raise
    except (IntegrityError,SQLAlchemyError) as ex: db.rollback(); raise HTTPException(409,"La venta de taquilla no se pudo completar") from ex

@app.get("/api/v1/tickets/{ticket_id}",response_model=TicketOut)
def get_ticket(ticket_id:int,user=Depends(current_user),db:Session=Depends(get_db)):
    row=db.execute(text("""SELECT b.id_boleto,b.id_funcion,b.id_asiento,b.codigo_qr::text,b.estado_boleto,b.precio_final,b.fecha_emision,o.id_usuario,o.vendedor_asociado
      FROM boleto b JOIN orden o USING(id_orden) WHERE b.id_boleto=:id"""),{"id":ticket_id}).mappings().first()
    if not row: raise HTTPException(404,"Boleto no encontrado")
    if user.role!="administrador/gerente" and row["id_usuario"]!=user.id and not (user.role=="taquillero" and row["vendedor_asociado"]==user.id): raise HTTPException(404,"Boleto no encontrado")
    result={k:v for k,v in row.items() if k not in {"id_usuario","vendedor_asociado"}}
    return result

@app.get("/api/v1/tickets/{ticket_id}/qr")
def ticket_qr(ticket_id:int,user=Depends(current_user),db:Session=Depends(get_db)):
    row=db.execute(text("SELECT b.codigo_qr::text,o.id_usuario,o.vendedor_asociado,b.estado_boleto FROM boleto b JOIN orden o USING(id_orden) WHERE b.id_boleto=:id"),{"id":ticket_id}).mappings().first()
    if not row or (row["id_usuario"]!=user.id and row["vendedor_asociado"]!=user.id and user.role!="administrador/gerente"): raise HTTPException(404,"Boleto no encontrado")
    if row["estado_boleto"]!="emitido": raise HTTPException(409,"El boleto no está habilitado")
    img=qrcode.make(row["codigo_qr"])
    from io import BytesIO
    buf=BytesIO(); img.save(buf,format="PNG"); buf.seek(0)
    return StreamingResponse(buf,media_type="image/png")

@app.post("/api/v1/access/validate")
def validate_qr(payload:CheckinIn,user=Depends(admin_or_door),db:Session=Depends(get_db)):
    try: code=str(UUID(payload.codigo_qr))
    except ValueError:
        db.execute(text("INSERT INTO acceso_puerta_log(id_dispositivo,resultado,motivo) VALUES(:device, 'invalido', 'Código QR malformado')"), {"device":payload.id_dispositivo})
        db.commit(); return {"resultado":"invalido","acceso_concedido":False}
    result=db.execute(text("SELECT validar_acceso_qr(CAST(:qr AS uuid),:device,:credential)"),{"qr":code,"device":payload.id_dispositivo,"credential":payload.credencial_validada}).scalar_one()
    db.commit()
    return {"resultado":result,"acceso_concedido":result=="exitoso"}

@app.post("/api/v1/tickets/{ticket_id}/refund",status_code=201)
def refund(ticket_id:int,payload:RefundIn,user=Depends(admin),db:Session=Depends(get_db)):
    if payload.id_boleto is not None and payload.id_boleto!=ticket_id: raise HTTPException(422,"El boleto del cuerpo debe coincidir con la ruta")
    try:
        row=db.execute(text("INSERT INTO reembolso(id_boleto,id_pago,id_usuario,monto_reembolso,motivo,forzado) VALUES(:ticket,:payment,:actor,:amount,:reason,:forced) RETURNING id_reembolso"),{"ticket":ticket_id,"payment":payload.id_pago,"actor":user.id,"amount":payload.monto,"reason":payload.motivo,"forced":payload.forzado}).scalar_one()
        db.commit(); return {"id_reembolso":row,"estado":"registrado"}
    except (IntegrityError,SQLAlchemyError) as ex: db.rollback(); raise HTTPException(409,"No se pudo registrar el reembolso conforme a la política") from ex

# Consultas analíticas: cada subconsulta agrega antes de combinarse para evitar multiplicar importes.
@app.get("/api/v1/reports/occupancy")
def report_occupancy(function_id:int|None=None, user=Depends(finance_reader), db:Session=Depends(get_db)):
    return list(db.execute(text("""WITH sold AS (SELECT id_funcion,count(*) AS tickets FROM boleto WHERE estado_boleto<>'anulado' GROUP BY id_funcion),
      sales AS (SELECT id_funcion,sum(o.total) gross FROM orden o WHERE o.estado_orden='pagada' GROUP BY id_funcion),
      refunds AS (SELECT p.id_orden,sum(r.monto_reembolso) amount FROM reembolso r JOIN pago p USING(id_pago) GROUP BY p.id_orden),
      returned AS (SELECT o.id_funcion,sum(r.amount) amount FROM refunds r JOIN orden o USING(id_orden) GROUP BY o.id_funcion)
      SELECT f.id_funcion,p.titulo,s.capacidad_total,coalesce(x.tickets,0) boletos_vendidos,
      round(100.0*coalesce(x.tickets,0)/nullif(s.capacidad_total,0),2) ocupacion_pct,coalesce(g.gross,0)-coalesce(r.amount,0) recaudacion
      FROM funcion f JOIN pelicula p USING(id_pelicula) JOIN sala s USING(id_sala) LEFT JOIN sold x USING(id_funcion)
      LEFT JOIN sales g USING(id_funcion) LEFT JOIN returned r USING(id_funcion)
      WHERE (CAST(:id AS integer) IS NULL OR f.id_funcion=CAST(:id AS integer)) ORDER BY f.fecha_hora_inicio DESC"""),{"id":function_id}).mappings())

@app.get("/api/v1/reports/top-movies")
def report_top_movies(user=Depends(finance_reader),db:Session=Depends(get_db)):
    return list(db.execute(text("""SELECT p.id_pelicula,p.titulo,count(*) boletos_vendidos FROM boleto b JOIN funcion f USING(id_funcion) JOIN pelicula p USING(id_pelicula)
      WHERE b.estado_boleto<>'anulado' AND b.fecha_emision>=now()-interval '7 days' GROUP BY p.id_pelicula,p.titulo ORDER BY boletos_vendidos DESC,p.titulo LIMIT 5""")).mappings())

@app.get("/api/v1/reports/payment-methods")
def report_payment_methods(user=Depends(finance_reader),db:Session=Depends(get_db)):
    return list(db.execute(text("""WITH counts AS (SELECT m.nombre_metodo_pago,count(*)::bigint n FROM pago p JOIN metodo_pago m USING(id_metodo_pago) WHERE p.estado_pago='aprobado' AND m.nombre_metodo_pago<>'cortesia' GROUP BY m.nombre_metodo_pago)
      SELECT nombre_metodo_pago nombre,n cantidad,round(100.0*n/nullif(sum(n) OVER(),0),2) porcentaje FROM counts ORDER BY n DESC""")).mappings())

@app.get("/api/v1/reports/critical-audit")
def report_audit(user=Depends(admin),db:Session=Depends(get_db)):
    return list(db.execute(text("""WITH events AS (
      SELECT id_usuario,operacion FROM admin_operacion_audit WHERE fecha_hora>=now()-interval '1 month' AND (operacion='cortesia' OR operacion IN ('crear','cambio_manual','cambio_asiento','modificacion_manual'))
      UNION ALL SELECT id_usuario,'reembolso' FROM reembolso WHERE fecha_reembolso>=now()-interval '1 month')
      SELECT id_usuario id_administrador,count(*) FILTER(WHERE operacion<>'cortesia' AND operacion<>'reembolso') modificaciones_manuales,
      count(*) FILTER(WHERE operacion='cortesia') cortesias,count(*) FILTER(WHERE operacion='reembolso') reembolsos
      FROM events GROUP BY id_usuario ORDER BY id_usuario""")).mappings())

def audit(db:Session, actor, operation:str, entity:str, entity_id:str, old=None, new=None):
    db.execute(text("""INSERT INTO admin_operacion_audit
      (id_usuario,id_rol,ip_origen,operacion,entidad,id_entidad,valor_anterior,valor_nuevo)
      SELECT :actor,u.id_rol,COALESCE(inet_client_addr(),'127.0.0.1'::inet)::text,
        :operation,:entity,CAST(:id AS integer),CAST(:old AS jsonb),CAST(:new AS jsonb)
      FROM usuario u WHERE u.id_usuario=:actor"""),
      {"actor":actor.id,"operation":operation,"entity":entity,"id":entity_id,
       "old":None if old is None else __import__('json').dumps(old,default=str),
       "new":None if new is None else __import__('json').dumps(new,default=str)})

@app.post("/api/v1/admin/movies",status_code=201)
def create_movie(payload:MovieIn,user=Depends(admin),db:Session=Depends(get_db)):
    row=db.execute(text("INSERT INTO pelicula(titulo,sinopsis,clasificacion_edad,duracion_minutos,poster_url,pelicula_esta_activa) VALUES(:titulo,:sinopsis,:rating,:duration,:poster,:active) RETURNING *"),{"titulo":payload.titulo,"sinopsis":payload.sinopsis,"rating":payload.clasificacion_edad,"duration":payload.duracion_minutos,"poster":payload.poster_url,"active":payload.pelicula_esta_activa}).mappings().one()
    audit(db,user,"crear","pelicula",str(row["id_pelicula"]),new=dict(row)); db.commit(); return row

@app.put("/api/v1/admin/movies/{movie_id}")
def update_movie(movie_id:int,payload:MovieIn,user=Depends(admin),db:Session=Depends(get_db)):
    old=db.execute(text("SELECT * FROM pelicula WHERE id_pelicula=:id FOR UPDATE"),{"id":movie_id}).mappings().first()
    if not old: raise HTTPException(404,"Película no encontrada")
    new=db.execute(text("UPDATE pelicula SET titulo=:titulo,sinopsis=:sinopsis,clasificacion_edad=:rating,duracion_minutos=:duration,poster_url=:poster,pelicula_esta_activa=:active WHERE id_pelicula=:id RETURNING *"),{"id":movie_id,"titulo":payload.titulo,"sinopsis":payload.sinopsis,"rating":payload.clasificacion_edad,"duration":payload.duracion_minutos,"poster":payload.poster_url,"active":payload.pelicula_esta_activa}).mappings().one()
    audit(db,user,"modificacion_manual","pelicula",str(movie_id),dict(old),dict(new)); db.commit(); return new

@app.post("/api/v1/admin/functions",status_code=201)
def create_function(payload:FunctionIn,user=Depends(admin),db:Session=Depends(get_db)):
    if payload.fecha_hora_inicio.tzinfo is None or payload.fecha_hora_fin.tzinfo is None: raise HTTPException(422,"Las fechas deben incluir zona horaria")
    row=db.execute(text("INSERT INTO funcion(id_pelicula,id_sala,fecha_hora_inicio,fecha_hora_fin) VALUES(:movie,:room,:start,:end) RETURNING *"),{"movie":payload.id_pelicula,"room":payload.id_sala,"start":payload.fecha_hora_inicio,"end":payload.fecha_hora_fin}).mappings().one()
    audit(db,user,"crear","funcion",str(row["id_funcion"]),new=dict(row)); db.commit(); return row

@app.post("/api/v1/admin/tariffs",status_code=201)
def create_tariff(payload:TariffIn,user=Depends(admin),db:Session=Depends(get_db)):
    row=db.execute(text("INSERT INTO tarifa(id_pais,id_zona,id_tipo_entrada,id_franja,dia_semana_para_tarifa,precio_base) VALUES(:country,:zone,:type,:band,:day,:price) RETURNING *"),{"country":payload.id_pais,"zone":payload.id_zona,"type":payload.id_tipo_entrada,"band":payload.id_franja,"day":payload.dia_semana,"price":payload.precio_base}).mappings().one()
    audit(db,user,"crear","tarifa",str(row["id_tarifa"]),new=dict(row)); db.commit(); return row

@app.post("/api/v1/admin/promotions",status_code=201)
def create_promotion(payload:PromotionIn,user=Depends(admin),db:Session=Depends(get_db)):
    if payload.tipo_regla=="descuento_dia" and (payload.dia_semana is None or payload.descuento_pct is None): raise HTTPException(422,"descuento_dia requiere día y porcentaje")
    if payload.tipo_regla=="2x1" and payload.dia_semana is not None: raise HTTPException(422,"2x1 no acepta día específico")
    row=db.execute(text("INSERT INTO promocion(nombre_promocion,tipo_regla,descuento_porcentaje,condicion_minima,dia_semana,promocion_esta_activa) VALUES(:name,:type,:discount,:minimum,:day,:active) RETURNING *"),{"name":payload.nombre_promocion,"type":payload.tipo_regla,"discount":payload.descuento_pct,"minimum":payload.condicion_minima,"day":payload.dia_semana,"active":payload.activa}).mappings().one()
    audit(db,user,"crear","promocion",str(row["id_promocion"]),new=dict(row)); db.commit(); return row

@app.patch("/api/v1/admin/functions/{function_id}/cancel")
def cancel_function(function_id:int,user=Depends(admin),db:Session=Depends(get_db)):
    old=db.execute(text("SELECT * FROM funcion WHERE id_funcion=:id FOR UPDATE"),{"id":function_id}).mappings().first()
    if not old: raise HTTPException(404,"Función no encontrada")
    if db.execute(text("SELECT EXISTS(SELECT 1 FROM boleto b WHERE b.id_funcion=:id AND b.estado_boleto<>'anulado')"),{"id":function_id}).scalar(): raise HTTPException(409,"La función tiene boletos vigentes; reembolse antes")
    db.execute(text("UPDATE estado_asiento_funcion SET estado='disponible',id_usuario=NULL,expiracion_bloqueo=NULL WHERE id_funcion=:id AND estado='bloqueado'"),{"id":function_id})
    row=db.execute(text("UPDATE funcion SET estado_funcion='cancelada' WHERE id_funcion=:id RETURNING *"),{"id":function_id}).mappings().one()
    audit(db,user,"modificacion_manual","funcion",str(function_id),dict(old),dict(row)); db.commit(); return row

@app.post("/api/v1/admin/rooms/{room_id}/seats",status_code=201)
def add_seat(room_id:int, fila:str=Query(min_length=1,max_length=8), numero:int=Query(gt=0,le=999), id_zona:int=Query(gt=0),user=Depends(admin),db:Session=Depends(get_db)):
    row=db.execute(text("INSERT INTO asiento(id_sala,id_zona,fila,numero) VALUES(:room,:zone,:row,:number) RETURNING *"),{"room":room_id,"zone":id_zona,"row":fila,"number":numero}).mappings().one()
    audit(db,user,"crear","asiento",str(row["id_asiento"]),new=dict(row)); db.commit(); return row

@app.post("/api/v1/admin/rooms",status_code=201)
def create_room(id_cine:int=Query(gt=0),nombre_sala:str=Query(min_length=1,max_length=120),capacidad_total:int=Query(gt=0),user=Depends(admin),db:Session=Depends(get_db)):
    row=db.execute(text("INSERT INTO sala(id_cine,nombre_sala,capacidad_total) VALUES(:cinema,:name,:capacity) RETURNING *"),{"cinema":id_cine,"name":nombre_sala,"capacity":capacidad_total}).mappings().one()
    audit(db,user,"crear","sala",str(row["id_sala"]),new=dict(row)); db.commit(); return row

@app.post("/api/v1/admin/refunds",status_code=201)
def create_refund(payload:RefundIn,user=Depends(admin),db:Session=Depends(get_db)):
    row=db.execute(text("INSERT INTO reembolso(id_pago,id_boleto,id_usuario,monto_reembolso,motivo,forzado) VALUES(:payment,:ticket,:actor,:amount,:reason,:forced) RETURNING *"),{"payment":payload.id_pago,"ticket":payload.id_boleto,"actor":user.id,"amount":payload.monto,"reason":payload.motivo,"forced":payload.forzado}).mappings().one()
    db.commit(); return row

@app.get("/api/v1/admin/orders/{order_id}")
def admin_order(order_id:int,user=Depends(admin_or_teller),db:Session=Depends(get_db)):
    order=db.execute(text("SELECT * FROM orden WHERE id_orden=:id"),{"id":order_id}).mappings().first()
    if not order or (user.role=="taquillero" and order["vendedor_asociado"]!=user.id): raise HTTPException(404,"Orden no encontrada")
    payments=db.execute(text("SELECT id_pago,id_metodo_pago,estado_pago,monto,fecha_operacion FROM pago WHERE id_orden=:id ORDER BY fecha_operacion"),{"id":order_id}).mappings().all()
    tickets=db.execute(text("SELECT id_boleto,id_funcion,id_asiento,id_tipo_entrada,precio_final,codigo_qr::text,estado_boleto,origen,fecha_emision FROM boleto WHERE id_orden=:id ORDER BY id_boleto"),{"id":order_id}).mappings().all()
    return {"orden":order,"pagos":list(payments),"boletos":list(tickets)}

@app.post("/api/v1/admin/maintenance/release-expired")
def release_expired(user=Depends(admin),db:Session=Depends(get_db)):
    count=db.execute(text("SELECT liberar_bloqueos_vencidos()")).scalar_one(); db.commit(); return {"bloqueos_liberados":count}

@app.get("/api/v1/admin/audit")
def list_audit(limit:int=Query(100,ge=1,le=500),user=Depends(admin),db:Session=Depends(get_db)):
    return list(db.execute(text("SELECT id_log,fecha_hora,id_usuario,id_rol,operacion,entidad,id_entidad,valor_anterior,valor_nuevo FROM admin_operacion_audit ORDER BY fecha_hora DESC LIMIT :limit"),{"limit":limit}).mappings())



@app.post("/api/v1/admin/staff",status_code=201)
def create_staff(payload:StaffIn,user=Depends(admin),db:Session=Depends(get_db)):
    from ..core.security import hash_password
    role_id=db.execute(text("SELECT id_rol FROM rol WHERE nombre_rol=:role"),{"role":payload.role}).scalar_one_or_none()
    if role_id is None: raise HTTPException(422,"Rol inexistente")
    new=db.execute(text("INSERT INTO usuario(id_rol,nombre_usuario,correo,contrasena_hash,usuario_esta_activo) VALUES(:role,:name,lower(:email),:hash,true) RETURNING id_usuario,nombre_usuario AS nombre,correo,id_rol,usuario_esta_activo AS activo"),
                   {"role":role_id,"name":payload.nombre,"email":payload.correo,"hash":hash_password(payload.password)}).mappings().one()
    audit(db,user,"crear","usuario",str(new["id_usuario"]),new=dict(new)); db.commit(); return new

@app.post("/api/v1/admin/zones",status_code=201)
def create_zone(nombre:str=Query(min_length=1,max_length=100),user=Depends(admin),db:Session=Depends(get_db)):
    row=db.execute(text("INSERT INTO zona(nombre_zona) VALUES(:name) RETURNING *"),{"name":nombre}).mappings().one()
    audit(db,user,"crear","zona",str(row["id_zona"]),new=dict(row)); db.commit(); return row

@app.patch("/api/v1/admin/rooms/{room_id}")
def update_room(room_id:int,nombre_sala:str|None=Query(default=None,max_length=120),sala_esta_activa:bool|None=None,
                user=Depends(admin),db:Session=Depends(get_db)):
    old=db.execute(text("SELECT * FROM sala WHERE id_sala=:id FOR UPDATE"),{"id":room_id}).mappings().first()
    if not old: raise HTTPException(404,"Sala no encontrada")
    row=db.execute(text("UPDATE sala SET nombre_sala=coalesce(:name,nombre_sala),sala_esta_activa=coalesce(:active,sala_esta_activa) WHERE id_sala=:id RETURNING *"),{"id":room_id,"name":nombre_sala,"active":sala_esta_activa}).mappings().one()
    audit(db,user,"modificacion_manual","sala",str(room_id),dict(old),dict(row)); db.commit(); return row

@app.patch("/api/v1/admin/seats/{seat_id}")
def update_seat(seat_id:int,id_zona:int|None=Query(default=None,gt=0),fila:str|None=Query(default=None,max_length=8),
                numero:int|None=Query(default=None,gt=0,le=999),user=Depends(admin),db:Session=Depends(get_db)):
    old=db.execute(text("SELECT * FROM asiento WHERE id_asiento=:id FOR UPDATE"),{"id":seat_id}).mappings().first()
    if not old: raise HTTPException(404,"Asiento no encontrado")
    row=db.execute(text("UPDATE asiento SET id_zona=coalesce(:zone,id_zona),fila=coalesce(:row,fila),numero=coalesce(:number,numero) WHERE id_asiento=:id RETURNING *"),{"id":seat_id,"zone":id_zona,"row":fila,"number":numero}).mappings().one()
    audit(db,user,"modificacion_manual","asiento",str(seat_id),dict(old),dict(row)); db.commit(); return row

@app.patch("/api/v1/admin/functions/{function_id}")
def update_function(function_id:int,fecha_hora_inicio:datetime|None=None,fecha_hora_fin:datetime|None=None,
                    user=Depends(admin),db:Session=Depends(get_db)):
    old=db.execute(text("SELECT * FROM funcion WHERE id_funcion=:id FOR UPDATE"),{"id":function_id}).mappings().first()
    if not old: raise HTTPException(404,"Función no encontrada")
    active=db.execute(text("SELECT EXISTS(SELECT 1 FROM boleto WHERE id_funcion=:id AND estado_boleto<>'anulado') OR EXISTS(SELECT 1 FROM estado_asiento_funcion WHERE id_funcion=:id AND estado='bloqueado' AND expiracion_bloqueo>clock_timestamp())"),{"id":function_id}).scalar_one()
    if active: raise HTTPException(409,"No se cambia el horario con boletos o bloqueos vigentes")
    start=fecha_hora_inicio or old["fecha_hora_inicio"]; end=fecha_hora_fin or old["fecha_hora_fin"]
    if start.tzinfo is None or end.tzinfo is None or end<=start: raise HTTPException(422,"Horario inválido; las fechas requieren zona horaria y fin posterior al inicio")
    row=db.execute(text("UPDATE funcion SET fecha_hora_inicio=:start,fecha_hora_fin=:end WHERE id_funcion=:id RETURNING *"),{"id":function_id,"start":start,"end":end}).mappings().one()
    audit(db,user,"modificacion_manual","funcion",str(function_id),dict(old),dict(row)); db.commit(); return row

@app.patch("/api/v1/admin/tariffs/{tariff_id}")
def update_tariff(tariff_id:int,payload:TariffIn,user=Depends(admin),db:Session=Depends(get_db)):
    old=db.execute(text("SELECT * FROM tarifa WHERE id_tarifa=:id FOR UPDATE"),{"id":tariff_id}).mappings().first()
    if not old: raise HTTPException(404,"Tarifa no encontrada")
    row=db.execute(text("UPDATE tarifa SET id_pais=:country,id_zona=:zone,id_tipo_entrada=:type,id_franja=:band,dia_semana_para_tarifa=:day,precio_base=:price WHERE id_tarifa=:id RETURNING *"),{"id":tariff_id,"country":payload.id_pais,"zone":payload.id_zona,"type":payload.id_tipo_entrada,"band":payload.id_franja,"day":payload.dia_semana,"price":payload.precio_base}).mappings().one()
    audit(db,user,"modificacion_manual","tarifa",str(tariff_id),dict(old),dict(row)); db.commit(); return row

@app.patch("/api/v1/admin/promotions/{promotion_id}")
def update_promotion(promotion_id:int,payload:PromotionIn,user=Depends(admin),db:Session=Depends(get_db)):
    if payload.tipo_regla=="descuento_dia" and (payload.dia_semana is None or payload.descuento_pct is None): raise HTTPException(422,"descuento_dia requiere día y porcentaje")
    if payload.tipo_regla=="2x1" and payload.dia_semana is not None: raise HTTPException(422,"2x1 no acepta día específico")
    old=db.execute(text("SELECT * FROM promocion WHERE id_promocion=:id FOR UPDATE"),{"id":promotion_id}).mappings().first()
    if not old: raise HTTPException(404,"Promoción no encontrada")
    row=db.execute(text("UPDATE promocion SET nombre_promocion=:name,tipo_regla=:type,descuento_porcentaje=:discount,condicion_minima=:minimum,dia_semana=:day,promocion_esta_activa=:active WHERE id_promocion=:id RETURNING *"),{"id":promotion_id,"name":payload.nombre_promocion,"type":payload.tipo_regla,"discount":payload.descuento_pct,"minimum":payload.condicion_minima,"day":payload.dia_semana,"active":payload.activa}).mappings().one()
    audit(db,user,"modificacion_manual","promocion",str(promotion_id),dict(old),dict(row)); db.commit(); return row

@app.post("/api/v1/admin/door-devices",status_code=201)
def create_door_device(id_sala:int=Query(gt=0),nombre:str=Query(min_length=1,max_length=120),user=Depends(admin),db:Session=Depends(get_db)):
    row=db.execute(text("INSERT INTO dispositivo_puerta(id_sala,nombre_dispositivo) VALUES(:room,:name) RETURNING *"),{"room":id_sala,"name":nombre}).mappings().one()
    audit(db,user,"crear","dispositivo_puerta",str(row["id_dispositivo"]),new=dict(row)); db.commit(); return row


@app.post("/api/v1/admin/courtesies",status_code=201)
def grant_courtesy(payload:CourtesyIn,user=Depends(admin),db:Session=Depends(get_db)):
    ids=[x.id_asiento for x in payload.asientos]
    try:
        customer=payload.id_usuario_cliente
        if customer is None:
            customer=db.execute(text("SELECT u.id_usuario FROM usuario u JOIN rol r USING(id_rol) WHERE r.nombre_rol='cliente_mostrador' AND u.usuario_esta_activo")).scalar_one_or_none()
            if customer is None: raise HTTPException(503,"No existe el usuario genérico cliente_mostrador")
        db.execute(text("SELECT reservar_asientos(:fn,CAST(:ids AS integer[]),:actor)"),{"fn":payload.id_funcion,"ids":ids,"actor":user.id})
        currency=db.execute(text("SELECT pa.moneda FROM funcion f JOIN sala s USING(id_sala) JOIN cine c USING(id_cine) JOIN ciudad ci USING(id_ciudad) JOIN pais pa USING(id_pais) WHERE f.id_funcion=:fn AND f.estado_funcion='programada'"),{"fn":payload.id_funcion}).scalar_one_or_none()
        if not currency: raise HTTPException(404,"Función no disponible")
        order_id=db.execute(text("INSERT INTO orden(id_usuario,vendedor_asociado,id_funcion,canal,estado_orden,subtotal,descuento,cargo_servicio,total,moneda) VALUES(:customer,:actor,:fn,'administrativo','pendiente',0,0,0,0,:currency) RETURNING id_orden"),{"customer":customer,"actor":user.id,"fn":payload.id_funcion,"currency":currency}).scalar_one()
        method=db.execute(text("SELECT id_metodo_pago FROM metodo_pago WHERE nombre_metodo_pago='cortesia'")).scalar_one()
        db.execute(text("INSERT INTO pago(id_orden,id_metodo_pago,estado_pago,monto) VALUES(:order,:method,'aprobado',0)"),{"order":order_id,"method":method})
        for item in payload.asientos:
            db.execute(text("INSERT INTO boleto(id_orden,id_funcion,id_asiento,id_tipo_entrada,precio_final,origen) VALUES(:order,:fn,:seat,:type,0,'cortesia')"),{"order":order_id,"fn":payload.id_funcion,"seat":item.id_asiento,"type":item.id_tipo_entrada})
        codes=db.execute(text("SELECT id_boleto,id_asiento,codigo_qr::text FROM boleto WHERE id_orden=:id ORDER BY id_boleto"),{"id":order_id}).mappings().all()
        db.commit(); return {"id_orden":order_id,"estado":"pagada","metodo":"cortesia","auditoria":"registrada por disparador de base de datos","boletos":[dict(x) for x in codes]}
    except HTTPException: db.rollback(); raise
    except (IntegrityError,SQLAlchemyError) as ex: db.rollback(); raise HTTPException(409,"No se pudo otorgar la cortesía") from ex


@app.post("/api/v1/admin/countries",status_code=201)
def create_country(payload:CountryIn,user=Depends(admin),db:Session=Depends(get_db)):
    row=db.execute(text("INSERT INTO pais(nombre,moneda) VALUES(:name,:currency) RETURNING *"),{"name":payload.nombre,"currency":payload.moneda}).mappings().one()
    audit(db,user,"crear","pais",str(row["id_pais"]),new=dict(row)); db.commit(); return row

@app.post("/api/v1/admin/cities",status_code=201)
def create_city(payload:CityIn,user=Depends(admin),db:Session=Depends(get_db)):
    row=db.execute(text("INSERT INTO ciudad(id_pais,nombre_ciudad) VALUES(:country,:name) RETURNING *"),{"country":payload.id_pais,"name":payload.nombre}).mappings().one()
    audit(db,user,"crear","ciudad",str(row["id_ciudad"]),new=dict(row)); db.commit(); return row

@app.post("/api/v1/admin/genres",status_code=201)
def create_genre(payload:GenreIn,user=Depends(admin),db:Session=Depends(get_db)):
    row=db.execute(text("INSERT INTO genero(nombre_genero) VALUES(:name) RETURNING *"),{"name":payload.nombre}).mappings().one()
    audit(db,user,"crear","genero",str(row["id_genero"]),new=dict(row)); db.commit(); return row

@app.post("/api/v1/admin/time-bands",status_code=201)
def create_time_band(payload:TimeBandIn,user=Depends(admin),db:Session=Depends(get_db)):
    if payload.hora_fin<=payload.hora_inicio: raise HTTPException(422,"La franja debe terminar después de iniciar y no puede cruzar medianoche")
    row=db.execute(text("INSERT INTO franja_horaria(nombre_franja,hora_inicio,hora_fin) VALUES(:name,:start,:end) RETURNING *"),{"name":payload.nombre,"start":payload.hora_inicio,"end":payload.hora_fin}).mappings().one()
    audit(db,user,"crear","franja_horaria",str(row["id_franja"]),new=dict(row)); db.commit(); return row


@app.get("/api/v1/reports/cashier")
def cashier_closeout(since:date|None=None,user=Depends(cashier_finance),db:Session=Depends(get_db)):
    if user.role=="taquillero":
        return list(db.execute(text("""SELECT o.id_orden,o.fecha_creacion,o.estado_orden,o.subtotal,o.descuento,o.cargo_servicio,o.total,o.moneda,
          coalesce(sum(p.monto) FILTER(WHERE p.estado_pago='aprobado'),0) pagado
          FROM orden o LEFT JOIN pago p USING(id_orden) WHERE o.vendedor_asociado=:seller
            AND (CAST(:since AS date) IS NULL OR o.fecha_creacion>=CAST(:since AS date)) GROUP BY o.id_orden ORDER BY o.fecha_creacion DESC LIMIT 500"""),{"seller":user.id,"since":since}).mappings())
    return list(db.execute(text("""SELECT o.vendedor_asociado id_taquillero,count(*) ordenes,
      coalesce(sum(o.total) FILTER(WHERE o.estado_orden='pagada'),0) recaudacion
      FROM orden o WHERE o.canal='taquilla' AND (CAST(:since AS date) IS NULL OR o.fecha_creacion>=CAST(:since AS date))
      GROUP BY o.vendedor_asociado ORDER BY o.vendedor_asociado"""),{"since":since}).mappings())
