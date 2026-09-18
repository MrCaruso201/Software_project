# Immagine ufficiale Playwright: include Python, i browser headless
# e tutte le librerie di sistema necessarie
FROM mcr.microsoft.com/playwright/python:v1.48.0-jammy

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Copia solo requirements prima, per sfruttare la cache di build
COPY python_scraper_server/requirements.txt python_scraper_server/requirements.txt
RUN pip install --no-cache-dir -r python_scraper_server/requirements.txt

# Allinea i browser Playwright alla versione della libreria in requirements.txt
RUN playwright install --with-deps chromium

# Copia TUTTO il progetto (python_scraper_server, racefacer_sim, ecc.)
# mantenendo la stessa struttura relativa che hanno sul disco
COPY . .

# main.py fa riferimento a ../racefacer_sim: eseguendolo da qui
# quel path relativo punta correttamente a /app/racefacer_sim
WORKDIR /app/python_scraper_server

EXPOSE 8000

CMD ["python", "main.py"]
