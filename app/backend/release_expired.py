from .database import SessionLocal
from sqlalchemy import text

if __name__ == "__main__":
    db=SessionLocal()
    try:
        count=db.execute(text("SELECT liberar_bloqueos_vencidos()")).scalar_one()
        db.commit()
        print(f"Bloqueos vencidos liberados: {count}")
    finally:
        db.close()
