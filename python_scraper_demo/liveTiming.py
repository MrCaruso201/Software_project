"""
Live Timing Scraper — Ottobiano Motorsport
GUI: customtkinter | Scraping: Playwright | Output: JSON
"""

import customtkinter as ctk
import threading
import json
import time
import os
import tempfile
import hashlib
from datetime import datetime
from playwright.sync_api import sync_playwright

# ── Tema racing: sfondo nero, accento giallo ──────────────────────────────────
ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("dark-blue")

ACCENT       = "#F5C518"   # giallo race
BG           = "#0D0D0D"
PANEL        = "#1A1A1A"
TEXT         = "#FFFFFF"
TEXT_DIM     = "#888888"
GREEN        = "#22C55E"
RED          = "#EF4444"

POLL_INTERVAL  = 3          # secondi tra un check e l'altro
REFRESH_EVERY  = 1         # refresh pagina ogni N poll (es. ogni 30 secondi)
JSON_PATH     = os.path.join(os.path.expanduser("~"), "live_timing_data.json")

JS_EXTRACT = """
() => {
    const tables = document.querySelectorAll('table');
    let bestTable = null;
    let maxRows = 0;
    tables.forEach(t => {
        const rows = t.querySelectorAll('tr');
        if (rows.length > maxRows) { maxRows = rows.length; bestTable = t; }
    });
    if (!bestTable) return { headers: [], rows: [] };

    const allRows = Array.from(bestTable.querySelectorAll('tr'));
    const headers = Array.from(allRows[0]?.querySelectorAll('th, td') || [])
                        .map(c => c.innerText.trim());

    const rows = allRows.slice(1).map(row => {
        return Array.from(row.querySelectorAll('td'))
                    .map(c => c.innerText.trim());
    }).filter(r => r.some(c => c !== ''));

    return { headers, rows };
}
"""


def data_hash(data: dict) -> str:
    return hashlib.md5(json.dumps(data, sort_keys=True).encode()).hexdigest()


def save_json(data: dict):
    """Scrittura atomica: scrive su tmp poi rinomina, così la lettura è sempre safe."""
    tmp_fd, tmp_path = tempfile.mkstemp(suffix=".json", dir=os.path.dirname(JSON_PATH))
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        os.replace(tmp_path, JSON_PATH)
    except Exception:
        os.unlink(tmp_path)
        raise


class LiveTimingApp(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title("Live Timing Scraper")
        self.geometry("980x720")
        self.configure(fg_color=BG)
        self.resizable(True, True)

        self._running   = False
        self._thread    = None
        self._last_hash = None
        self._row_count = 0

        self._build_ui()

    # ── UI ────────────────────────────────────────────────────────────────────

    def _build_ui(self):
        # Header bar
        header = ctk.CTkFrame(self, fg_color=PANEL, corner_radius=0, height=64)
        header.pack(fill="x", side="top")
        header.pack_propagate(False)

        title_lbl = ctk.CTkLabel(header, text="⏱  LIVE TIMING SCRAPER",
                                 font=ctk.CTkFont("Helvetica", 20, "bold"),
                                 text_color=ACCENT)
        title_lbl.pack(side="left", padx=20, pady=16)

        self.status_dot = ctk.CTkLabel(header, text="●", font=ctk.CTkFont(size=18),
                                       text_color=TEXT_DIM)
        self.status_dot.pack(side="right", padx=8)
        self.status_lbl = ctk.CTkLabel(header, text="Inattivo",
                                       font=ctk.CTkFont(size=13),
                                       text_color=TEXT_DIM)
        self.status_lbl.pack(side="right", padx=4)

        # URL bar
        url_bar = ctk.CTkFrame(self, fg_color=PANEL, corner_radius=0, height=52)
        url_bar.pack(fill="x")
        url_bar.pack_propagate(False)

        ctk.CTkLabel(url_bar, text="URL:", font=ctk.CTkFont(size=13),
                     text_color=TEXT_DIM).pack(side="left", padx=(16, 6), pady=12)

        self.url_entry = ctk.CTkEntry(url_bar, width=560,
                                      font=ctk.CTkFont(size=13),
                                      fg_color="#111111", border_color="#333333",
                                      text_color=TEXT,
                                      placeholder_text="https://live.racefacer.com/...")
        self.url_entry.pack(side="left", pady=10)
        self.url_entry.insert(0, "https://live.racefacer.com/ottobianomotorsport")

        self.start_btn = ctk.CTkButton(url_bar, text="▶  START",
                                       width=120, height=34,
                                       font=ctk.CTkFont(size=13, weight="bold"),
                                       fg_color=ACCENT, text_color="#000000",
                                       hover_color="#D4A800",
                                       command=self.toggle)
        self.start_btn.pack(side="left", padx=12)

        # Stats bar
        stats = ctk.CTkFrame(self, fg_color="#111111", corner_radius=0, height=32)
        stats.pack(fill="x")
        stats.pack_propagate(False)

        self.update_lbl = ctk.CTkLabel(stats, text="Nessun aggiornamento",
                                        font=ctk.CTkFont(size=11), text_color=TEXT_DIM)
        self.update_lbl.pack(side="left", padx=16)

        self.json_lbl = ctk.CTkLabel(stats, text=f"JSON → {JSON_PATH}",
                                      font=ctk.CTkFont(size=11), text_color=TEXT_DIM)
        self.json_lbl.pack(side="right", padx=16)

        # Tabella
        self.table_frame = ctk.CTkScrollableFrame(self, fg_color=BG,
                                                   label_text="",
                                                   scrollbar_button_color="#333",
                                                   scrollbar_button_hover_color=ACCENT)
        self.table_frame.pack(fill="both", expand=True, padx=0, pady=(4, 0))

        # Log
        log_frame = ctk.CTkFrame(self, fg_color=PANEL, corner_radius=0, height=160)
        log_frame.pack(fill="x", side="bottom")
        log_frame.pack_propagate(False)

        ctk.CTkLabel(log_frame, text="LOG", font=ctk.CTkFont(size=10, weight="bold"),
                     text_color=TEXT_DIM).pack(anchor="w", padx=12, pady=(6, 0))

        self.log_box = ctk.CTkTextbox(log_frame, fg_color="#0A0A0A",
                                       text_color=TEXT_DIM,
                                       font=ctk.CTkFont("Courier", 11),
                                       border_width=0)
        self.log_box.pack(fill="both", expand=True, padx=8, pady=(2, 8))
        self.log_box.configure(state="disabled")

    # ── Helpers UI ────────────────────────────────────────────────────────────

    def log(self, msg: str, color: str = TEXT_DIM):
        ts = datetime.now().strftime("%H:%M:%S")
        line = f"[{ts}] {msg}\n"
        self.log_box.configure(state="normal")
        self.log_box.insert("end", line)
        self.log_box.see("end")
        self.log_box.configure(state="disabled")

    def set_status(self, text: str, color: str):
        self.status_lbl.configure(text=text, text_color=color)
        self.status_dot.configure(text_color=color)

    def render_table(self, headers: list, rows: list):
        # Pulisci
        for w in self.table_frame.winfo_children():
            w.destroy()

        col_count = max(len(headers), max((len(r) for r in rows), default=0))
        if col_count == 0:
            ctk.CTkLabel(self.table_frame, text="Nessun dato",
                         text_color=TEXT_DIM).pack(pady=40)
            return

        # Pesi colonne uniformi
        for c in range(col_count):
            self.table_frame.columnconfigure(c, weight=1, minsize=80)

        # Header
        for c, h in enumerate(headers):
            cell = ctk.CTkLabel(self.table_frame, text=h.upper(),
                                 font=ctk.CTkFont(size=10, weight="bold"),
                                 text_color=ACCENT,
                                 fg_color="#1E1E1E",
                                 corner_radius=0,
                                 anchor="center")
            cell.grid(row=0, column=c, sticky="nsew", padx=1, pady=(0, 1), ipady=6)

        # Righe
        for r_idx, row in enumerate(rows):
            bg = "#161616" if r_idx % 2 == 0 else "#111111"
            for c_idx in range(col_count):
                val = row[c_idx] if c_idx < len(row) else ""

                # Colora posizione 1
                txt_color = TEXT
                if c_idx == 0 and val == "1":
                    txt_color = ACCENT

                cell = ctk.CTkLabel(self.table_frame, text=val,
                                     font=ctk.CTkFont(size=12),
                                     text_color=txt_color,
                                     fg_color=bg,
                                     corner_radius=0,
                                     anchor="center")
                cell.grid(row=r_idx + 1, column=c_idx,
                          sticky="nsew", padx=1, pady=1, ipady=5)

    # ── Scraping thread ───────────────────────────────────────────────────────

    def toggle(self):
        if self._running:
            self._running = False
            self.start_btn.configure(text="▶  START", fg_color=ACCENT,
                                     text_color="#000000", hover_color="#D4A800")
            self.set_status("Inattivo", TEXT_DIM)
            self.log("Scraping fermato.")
        else:
            url = self.url_entry.get().strip()
            if not url.startswith("http"):
                self.log("URL non valido.", RED)
                return
            self._running = True
            self.start_btn.configure(text="■  STOP", fg_color=RED,
                                     text_color=TEXT, hover_color="#B91C1C")
            self.set_status("Connessione...", ACCENT)
            self.log(f"Avvio scraping → {url}")
            self._thread = threading.Thread(target=self._scrape_loop,
                                            args=(url,), daemon=True)
            self._thread.start()

    def _scrape_loop(self, url: str):
        try:
            with sync_playwright() as pw:
                browser = pw.chromium.launch(headless=True)
                page    = browser.new_page()

                self.log("Browser avviato, caricamento pagina...")
                page.goto(url, wait_until="networkidle", timeout=30_000)
                self.after(0, lambda: self.set_status("Live", GREEN))
                self.log("Pagina caricata. Inizio polling.")
                poll_count = 0

                while self._running:
                    try:
                        # Refresh periodico della pagina
                        if poll_count > 0 and poll_count % REFRESH_EVERY == 0:
                            self.after(0, lambda: self.log("Refresh pagina..."))
                            page.goto(url, wait_until="networkidle", timeout=30_000)

                        poll_count += 1
                        result  = page.evaluate(JS_EXTRACT)
                        headers = result.get("headers", [])
                        rows    = result.get("rows", [])

                        payload = {
                            "url":        url,
                            "updated_at": datetime.now().isoformat(),
                            "headers":    headers,
                            "rows":       rows,
                        }
                        h = data_hash(payload)

                        if h != self._last_hash:
                            self._last_hash = h
                            save_json(payload)
                            now = datetime.now().strftime("%H:%M:%S")
                            self.after(0, lambda h=headers, r=rows: self.render_table(h, r))
                            self.after(0, lambda t=now, n=len(rows):
                                self.update_lbl.configure(
                                    text=f"Ultimo aggiornamento: {t}  |  {n} righe",
                                    text_color=GREEN))
                            self.after(0, lambda n=len(rows):
                                self.log(f"Dati aggiornati: {n} righe → JSON salvato.", GREEN))

                        time.sleep(POLL_INTERVAL)

                    except Exception as e:
                        self.after(0, lambda e=e: self.log(f"Errore polling: {e}", RED))
                        time.sleep(POLL_INTERVAL)

                browser.close()

        except Exception as e:
            self.after(0, lambda e=e: self.log(f"Errore browser: {e}", RED))
            self.after(0, lambda: self.set_status("Errore", RED))
            self._running = False
            self.after(0, lambda: self.start_btn.configure(
                text="▶  START", fg_color=ACCENT,
                text_color="#000000", hover_color="#D4A800"))


if __name__ == "__main__":
    app = LiveTimingApp()
    app.mainloop()