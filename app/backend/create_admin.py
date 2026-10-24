from getpass import getpass
import os
from sqlalchemy import text
from .core.security import hash_password
from .database import SessionLocal


def main():
    email=os.environ.get("INITIAL_ADMIN_EMAIL")
    if not email:
        raise SystemExit("Defina INITIAL_ADMIN_EMAIL antes de ejecutar esta provisión única.")
    name=input("Nombre del administrador inicial: ").strip()
    password=getpass("Contraseña inicial (mínimo 12 caracteres): ")
    confirmation=getpass("Repita la contraseña: ")
    if password!=confirmation: raise SystemExit("Las contraseñas no coinciden.")
    db=SessionLocal()
    try:
        if db.execute(text("SELECT EXISTS(SELECT 1 FROM usuario u JOIN rol r USING(id_rol) WHERE r.nombre_rol='administrador/gerente' AND u.activo)")).scalar_one():
            raise SystemExit("Ya existe un administrador activo; la provisión inicial se cancela.")
        role=db.execute(text("SELECT id_rol FROM rol WHERE nombre_rol='administrador/gerente'")).scalar_one()
        db.execute(text("INSERT INTO usuario(id_rol,nombre,correo,contrasena_hash) VALUES(:role,:name,lower(:email),:hash)"),
                   {"role":role,"name":name,"email":email,"hash":hash_password(password)})
        db.commit(); print("Administrador inicial creado.")
    finally: db.close()

if __name__=="__main__": main()
