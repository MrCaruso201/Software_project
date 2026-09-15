"""Temporary browser links for PDFs produced by the app (valid for one hour)."""
import re
import secrets
import tempfile
import time
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import Response
from auth.dependencies import get_current_user

router = APIRouter(prefix="/documents", tags=["documents"])
PDF_DIR = Path(tempfile.gettempdir()) / "kart-timing-pdfs"
TTL = 3600
MAX_BYTES = 10 * 1024 * 1024


@router.post("/pdf")
async def publish_pdf(request: Request, user: dict = Depends(get_current_user)):
    data = bytearray()
    async for chunk in request.stream():
        data.extend(chunk)
        if len(data) > MAX_BYTES:
            raise HTTPException(413, "PDF troppo grande")
    if not data.startswith(b"%PDF-"):
        raise HTTPException(400, "Documento PDF non valido")
    PDF_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    for old in PDF_DIR.glob("*.pdf"):
        try:
            if old.stat().st_mtime < time.time() - TTL:
                old.unlink(missing_ok=True)
        except FileNotFoundError:
            pass
    key = secrets.token_urlsafe(32)
    (PDF_DIR / f"{key}.pdf").write_bytes(data)
    return {"path": f"documents/pdf/{key}.pdf"}


@router.get("/pdf/{filename}")
def view_pdf(filename: str):
    # The unguessable link grants access only to this document until expiry.
    if not re.fullmatch(r"[A-Za-z0-9_-]{43}\.pdf", filename):
        raise HTTPException(404, "PDF non trovato")
    path = PDF_DIR / filename
    try:
        if path.stat().st_mtime < time.time() - TTL:
            path.unlink(missing_ok=True)
            raise HTTPException(410, "Link PDF scaduto: riaprire il documento dall'app")
        data = path.read_bytes()
    except FileNotFoundError:
        raise HTTPException(404, "PDF non trovato")
    return Response(data, media_type="application/pdf", headers={
        "Content-Disposition": 'inline; filename="documento.pdf"',
        "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
    })
