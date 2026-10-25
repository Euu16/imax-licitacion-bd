from pathlib import Path

from fastapi.staticfiles import StaticFiles

from .api.routes import app

frontend_dir = Path(__file__).resolve().parents[1] / "frontend"
if frontend_dir.is_dir():
    app.mount("/", StaticFiles(directory=frontend_dir, html=True), name="frontend")

__all__ = ["app"]
