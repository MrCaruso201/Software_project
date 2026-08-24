import io
import base64
from datetime import datetime
from fpdf import FPDF

def generate_release_pdf(
    event_title: str,
    event_date: str,
    event_location: str,
    release_text: str,
    first_name: str,
    last_name: str,
    codice_fiscale: str = "",
    birth_date: str = "",
    residence: str = "",
    signature_base64: str = ""
) -> bytes:
    """
    Genera il PDF della liberatoria firmata.
    
    :param event_title: Titolo dell'evento.
    :param event_date: Data dell'evento.
    :param event_location: Circuito/Luogo dell'evento.
    :param release_text: Testo della liberatoria.
    :param first_name: Nome dell'utente.
    :param last_name: Cognome dell'utente.
    :param codice_fiscale: Codice fiscale dell'utente.
    :param birth_date: Data di nascita dell'utente.
    :param residence: Residenza dell'utente.
    :param signature_base64: Immagine della firma in formato base64.
    :return: I byte del PDF generato.
    """
    pdf = FPDF()
    pdf.add_page()
    
    # Intestazione Evento
    pdf.set_font("Helvetica", "B", 16)
    pdf.cell(0, 10, f"Liberatoria: {event_title}", new_x="LMARGIN", new_y="NEXT", align="C")
    
    pdf.set_font("Helvetica", "", 12)
    if event_date:
        pdf.cell(0, 8, f"Data Evento: {event_date}", new_x="LMARGIN", new_y="NEXT", align="C")
    if event_location:
        pdf.cell(0, 8, f"Circuito/Luogo: {event_location}", new_x="LMARGIN", new_y="NEXT", align="C")
    
    pdf.ln(10)
    
    # Testo della liberatoria
    pdf.set_font("Helvetica", "", 12)
    if not release_text:
        release_text = "Nessun testo specificato per questa liberatoria."
        
    pdf.multi_cell(0, 8, release_text)
    pdf.ln(15)
    
    # Dati utente
    pdf.set_font("Helvetica", "B", 12)
    pdf.cell(0, 10, "Dichiarante:", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 12)
    pdf.cell(0, 10, f"Nome e Cognome: {first_name} {last_name}", new_x="LMARGIN", new_y="NEXT")
    if codice_fiscale:
        pdf.cell(0, 10, f"Codice Fiscale: {codice_fiscale}", new_x="LMARGIN", new_y="NEXT")
    if birth_date:
        pdf.cell(0, 10, f"Data di nascita: {birth_date}", new_x="LMARGIN", new_y="NEXT")
    if residence:
        pdf.cell(0, 10, f"Residenza: {residence}", new_x="LMARGIN", new_y="NEXT")
        
    current_date = datetime.now().strftime("%d/%m/%Y %H:%M")
    pdf.cell(0, 8, f"Data e Ora: {current_date}", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(5)
    
    # Firma
    pdf.cell(0, 10, "Firma:", new_x="LMARGIN", new_y="NEXT")
    
    if signature_base64:
        try:
            # Rimuovi eventuale prefisso (es. "data:image/png;base64,")
            if "," in signature_base64:
                signature_base64 = signature_base64.split(",")[1]
                
            img_bytes = base64.b64decode(signature_base64)
            img_stream = io.BytesIO(img_bytes)
            
            # Aggiungiamo l'immagine. w=80 fissa la larghezza, l'altezza è proporzionale
            pdf.image(img_stream, w=80)
        except Exception as e:
            pdf.set_font("Helvetica", "I", 10)
            pdf.cell(0, 10, f"[Errore caricamento firma: {str(e)}]", new_x="LMARGIN", new_y="NEXT")
            
    # Restituisce i byte del PDF
    return pdf.output()
