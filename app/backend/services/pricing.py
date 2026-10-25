from decimal import Decimal, ROUND_HALF_UP
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from sqlalchemy import text
from sqlalchemy.orm import Session
from fastapi import HTTPException


def quote_seats(db: Session, function_id: int, choices, start, zone_name: str, promotion_id: int | None):
    """Resolve all ticket prices from persisted tariff, local cinema time and promotion rows."""
    try:
        local=start.astimezone(ZoneInfo(zone_name))
    except ZoneInfoNotFoundError as exc:
        raise HTTPException(500,"Zona horaria inválida para el cine") from exc
    dow=(local.weekday()+1)%7  # PostgreSQL EXTRACT(DOW): Sunday=0.
    ids=[item.id_asiento for item in choices]
    types=[item.id_tipo_entrada for item in choices]
    rows=db.execute(text("""SELECT a.id_asiento,a.id_zona,te.id_tipo_entrada,te.nombre_tipo_de_entrada tipo,te.requiere_credencial,
      fr.id_franja,fr.nombre_franja franja,fr.hora_inicio,fr.hora_fin,t.precio_base
      FROM asiento a JOIN zona z USING(id_zona) JOIN tarifa t ON t.id_zona=z.id_zona
      JOIN tipo_entrada te ON te.id_tipo_entrada=t.id_tipo_entrada JOIN franja_horaria fr ON fr.id_franja=t.id_franja
      WHERE a.id_sala=(SELECT id_sala FROM funcion WHERE id_funcion=:fn)
        AND a.id_asiento=ANY(CAST(:ids AS integer[])) AND t.id_tipo_entrada=ANY(CAST(:types AS integer[]))
        AND t.dia_semana_para_tarifa=:dow AND fr.hora_inicio<=:tm AND fr.hora_fin>:tm
        AND t.id_pais=(SELECT cd.id_pais FROM funcion f JOIN sala s USING(id_sala) JOIN cine c USING(id_cine) JOIN ciudad cd USING(id_ciudad) WHERE f.id_funcion=:fn)"""),
        {"fn":function_id,"ids":ids,"types":types,"dow":dow,"tm":local.timetz().replace(tzinfo=None)}).mappings().all()
    prices={(row["id_asiento"],row["id_tipo_entrada"]):row for row in rows}
    tickets=[]
    for choice in choices:
        row=prices.get((choice.id_asiento,choice.id_tipo_entrada))
        if not row: raise HTTPException(422,"No existe tarifa aplicable para uno o más asientos/tipos de entrada")
        price=Decimal(row["precio_base"])
        tickets.append({"seat":choice.id_asiento,"type":choice.id_tipo_entrada,"price":price,"zone":row["id_zona"],"final_price":price})
    subtotal=sum((item["price"] for item in tickets),Decimal("0.00"))
    promotions=db.execute(text("SELECT * FROM promocion WHERE promocion_esta_activa AND (:id IS NULL OR id_promocion=:id) AND (tipo_regla='2x1' OR dia_semana=:dow) ORDER BY id_promocion"),{"id":promotion_id,"dow":dow}).mappings().all()
    if promotion_id and not promotions: raise HTTPException(422,"Promoción inexistente, inactiva o no aplicable hoy")
    selected=None; discount=Decimal("0.00"); selected_tickets=tickets
    for promotion in promotions:
        if len(tickets)<promotion["condicion_minima"]:
            if promotion_id: raise HTTPException(422,"La selección no cumple la cantidad mínima de la promoción")
            continue
        if promotion["tipo_regla"]=="2x1" and len(tickets)<2:
            if promotion_id: raise HTTPException(422,"La promoción 2x1 requiere al menos dos entradas")
            continue
        candidate_tickets=[{**ticket,"final_price":ticket["price"]} for ticket in tickets]
        if promotion["tipo_regla"]=="descuento_dia":
            rate=Decimal(promotion["descuento_porcentaje"])/Decimal(100)
            for ticket in candidate_tickets:
                ticket["final_price"]=(ticket["price"]*(Decimal(1)-rate)).quantize(Decimal("0.01"),rounding=ROUND_HALF_UP)
        else:
            by_type={}
            for ticket in candidate_tickets: by_type.setdefault(ticket["type"],[]).append(ticket)
            for group in by_type.values():
                ordered=sorted(group,key=lambda item:item["price"],reverse=True)
                for index in range(1,len(ordered),2): ordered[index]["final_price"]=Decimal("0.00")
        candidate_discount=subtotal-sum((ticket["final_price"] for ticket in candidate_tickets),Decimal("0.00"))
        if selected is None or candidate_discount>discount:
            selected=promotion; discount=candidate_discount; selected_tickets=candidate_tickets
        if promotion_id: break
    tickets=selected_tickets
    return {"local_start":local,"tickets":tickets,"subtotal":subtotal,"discount":discount,"promotion":selected}
