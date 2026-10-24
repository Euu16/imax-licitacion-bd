from datetime import datetime, timedelta, timezone
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from pwdlib import PasswordHash
from sqlalchemy import text
from sqlalchemy.orm import Session
from ..database import get_db
from .config import settings

password_hash = PasswordHash.recommended()
oauth2 = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/token")

class Principal(dict):
    @property
    def id(self) -> int: return self["id_usuario"]
    @property
    def role(self) -> str: return self["nombre_rol"]

def hash_password(password: str) -> str:
    if len(password) < 12: raise ValueError("La contraseña debe tener al menos 12 caracteres")
    return password_hash.hash(password)

def verify_password(password: str, encoded: str) -> bool:
    try: return password_hash.verify(password, encoded)
    except Exception: return False

def issue_token(user_id: int, role: str) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode({"sub": str(user_id), "role": role, "iat": now,
                       "exp": now + timedelta(minutes=settings.jwt_expire_minutes)}, settings.jwt_secret, algorithm="HS256")

def current_user(token: str = Depends(oauth2), db: Session = Depends(get_db)) -> Principal:
    err = HTTPException(status.HTTP_401_UNAUTHORIZED, "Credenciales inválidas", headers={"WWW-Authenticate": "Bearer"})
    try:
        claims = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
        user_id = int(claims["sub"])
    except (jwt.PyJWTError, KeyError, TypeError, ValueError): raise err
    row = db.execute(text("SELECT u.id_usuario, r.nombre_rol FROM usuario u JOIN rol r USING(id_rol) WHERE u.id_usuario=:id AND u.activo"), {"id": user_id}).mappings().first()
    if not row or row["nombre_rol"] != claims.get("role"): raise err
    return Principal(row)

def require_permission(module: str, levels: set[str], roles: set[str]):
    """Authorize through the project's persisted rol_permiso matrix, then restrict intended roles."""
    def dependency(user: Principal = Depends(current_user), db: Session = Depends(get_db)) -> Principal:
        if user.role not in roles:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Permiso insuficiente")
        level=db.execute(text("SELECT rp.nivel FROM rol_permiso rp JOIN modulo m USING(id_modulo) JOIN rol r USING(id_rol) WHERE r.nombre_rol=:role AND m.nombre=:module"),{"role":user.role,"module":module}).scalar_one_or_none()
        if level not in levels:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Permiso insuficiente")
        return user
    return dependency

admin=require_permission("Auditoría y Gestión de Roles",{"total"},{"administrador/gerente"})
admin_or_teller=require_permission("Emisión y Acceso (QR)",{"lectura","total"},{"administrador/gerente","taquillero"})
finance_reader=require_permission("Reportes y Finanzas",{"lectura","total"},{"administrador/gerente","contador"})
admin_or_door=require_permission("Emisión y Acceso (QR)",{"ejecucion","total"},{"administrador/gerente","operador de sala"})
client_checkout=require_permission("Selección de Asientos y Pago",{"ejecucion"},{"cliente"})
cashier_sale=require_permission("Selección de Asientos y Pago",{"ejecucion"},{"taquillero"})
cashier_finance=require_permission("Reportes y Finanzas",{"lectura","total"},{"administrador/gerente","taquillero"})
