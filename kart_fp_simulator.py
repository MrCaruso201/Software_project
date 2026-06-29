#!/usr/bin/env python3
"""
Karting Free Practice Simulator
================================
Simula una prova libera di kart aggiornando un singolo file JSON in place,
esattamente come fa il sito RaceFacer. La tua app di scraping può leggere
quel file e troverà i dati aggiornati ad ogni giro completato.

Utilizzo:
    python kart_fp_simulator.py                        # velocità 10x (default)
    python kart_fp_simulator.py --speed 1              # velocità reale (1:1)
    python kart_fp_simulator.py --speed 60             # 1 min simulato = 1 sec reale
    python kart_fp_simulator.py --seed 42              # risultati riproducibili
    python kart_fp_simulator.py --duration 20          # sessione da 20 minuti
    python kart_fp_simulator.py --output percorso_precedente/Software_project/python_scraper_server/data/live_timing.json

Il file viene sovrascritto ad ogni evento (completamento giro), con un intervallo
reale pari al tempo del giro diviso per --speed.
"""

import json
import random
import os
import time
import argparse
from datetime import datetime, timedelta
from typing import List, Optional

# ─── Configurazione ───────────────────────────────────────────────────────────

DEFAULT_DURATION_MINUTES = 15           # Durata prova libera
OUTPUT_FILE              = "live_timing.json"   # File unico sovrascritto ad ogni update
BASE_URL                 = "https://live.racefacer.com/simulator"

# Piloti: nome, numero kart, tempo base giro (secondi), sigma (varianza = consistenza)
DRIVERS = [
    {"name": "Marco Rossi",       "kart": "101", "base_time": 73.5, "sigma": 0.35},
    {"name": "Luca Ferrari",      "kart": "102", "base_time": 74.2, "sigma": 0.40},
    {"name": "Sofia Esposito",    "kart": "103", "base_time": 75.8, "sigma": 0.55},
    {"name": "Giovanni Bianchi",  "kart": "104", "base_time": 76.1, "sigma": 0.45},
    {"name": "Elena Conti",       "kart": "105", "base_time": 77.0, "sigma": 0.60},
    {"name": "Andrea Ricci",      "kart": "106", "base_time": 73.8, "sigma": 0.38},
    {"name": "Matteo Romano",     "kart": "107", "base_time": 78.5, "sigma": 0.70},
    {"name": "Chiara Colombo",    "kart": "108", "base_time": 79.2, "sigma": 0.65},
    {"name": "Francesco Mancini", "kart": "109", "base_time": 75.2, "sigma": 0.50},
    {"name": "Valentina Leone",   "kart": "110", "base_time": 80.0, "sigma": 0.80},
]

# ─── Utilità ──────────────────────────────────────────────────────────────────

def seconds_to_laptime(seconds: float) -> str:
    """Converte secondi float nel formato M:SS.mmm  (es. 1:13.742)"""
    minutes = int(seconds // 60)
    secs    = seconds % 60
    return f"{minutes}:{secs:06.3f}"


def simulate_lap(base_time: float, sigma: float, lap_num: int) -> float:
    """
    Genera un tempo giro realistico applicando:
      - Penalità out-lap / riscaldamento gomme (giri 1-3)
      - Leggero miglioramento progressivo dal giro 5 (massimo 1.2 s)
      - Varianza casuale distribuita normalmente (sigma = consistenza del pilota)
    """
    # Penalità di riscaldamento
    if lap_num == 1:
        penalty = random.uniform(4.0, 10.0)   # out-lap, gomme fredde
    elif lap_num == 2:
        penalty = random.uniform(1.5, 4.0)
    elif lap_num == 3:
        penalty = random.uniform(0.3, 1.5)
    else:
        penalty = 0.0

    # Miglioramento progressivo (track rubbering + pilota che prende feeling)
    improvement = min(0.08 * max(0, lap_num - 4), 1.2) if lap_num > 4 else 0.0

    # Varianza casuale
    variance = random.gauss(0, sigma)

    lap_time = base_time + penalty - improvement + variance

    # Floor: mai più di 2% oltre il potenziale teorico del pilota
    return max(lap_time, base_time * 0.98)


# ─── Stato pilota ─────────────────────────────────────────────────────────────

class Driver:
    def __init__(self, name: str, kart: str, base_time: float, sigma: float):
        self.name      = name
        self.kart      = kart
        self.base_time = base_time
        self.sigma     = sigma

        self.lap_count: int         = 0
        self.lap_times: List[float] = []

        # Uscita dal pit sfasata tra 0 e 30 secondi (uscite non contemporanee)
        self.next_event: float = random.uniform(0.0, 30.0)

    @property
    def best_lap(self) -> Optional[float]:
        return min(self.lap_times) if self.lap_times else None

    @property
    def last_lap(self) -> Optional[float]:
        return self.lap_times[-1] if self.lap_times else None


# ─── Costruzione snapshot JSON ────────────────────────────────────────────────

def build_snapshot(
    drivers: List[Driver],
    session_start: datetime,
    sim_time: float,
) -> dict:
    """
    Costruisce il dict JSON di un singolo aggiornamento di timing.

    Classifica PROVA LIBERA: ordinata per miglior tempo (best lap).
    I piloti senza giri completi appaiono in fondo senza tempo.

    Colonne:
      P  | Kart | Driver | Lap Time (ultimo) | Gap (dal leader) | Int (dal precedente)
      Best (miglior personale) | Laps | (vuoto)
    """
    # Ordina chi ha completato almeno un giro per miglior tempo
    ranked   : List[Driver] = sorted(
        [d for d in drivers if d.best_lap is not None],
        key=lambda d: d.best_lap,   # type: ignore[return-value]
    )
    no_time  : List[Driver] = [d for d in drivers if d.best_lap is None]
    classified = ranked + no_time

    leader_best: Optional[float] = ranked[0].best_lap if ranked else None

    rows = []
    for pos, driver in enumerate(classified, start=1):
        if driver.best_lap is not None:
            last_str = seconds_to_laptime(driver.last_lap)   # type: ignore[arg-type]
            best_str = seconds_to_laptime(driver.best_lap)

            if pos == 1:
                gap_str = "-"
                int_str = "-"
            else:
                # Gap = distacco dal leader (best lap)
                gap_val = driver.best_lap - leader_best          # type: ignore[operator]
                gap_str = f"+{gap_val:.3f}"

                # Int = distacco dal pilota immediatamente davanti
                # ranked è 0-indexed, driver in pos P ha indice pos-1 in ranked
                # il precedente è ranked[pos-2]
                int_val = driver.best_lap - ranked[pos - 2].best_lap  # type: ignore[operator]
                int_str = f"+{int_val:.3f}"
        else:
            last_str = "-"
            best_str = "-"
            gap_str  = "-"
            int_str  = "-"

        rows.append([
            str(pos),
            driver.kart,
            driver.name,
            last_str,
            gap_str,
            int_str,
            best_str,
            str(driver.lap_count),
            "",
        ])

    timestamp = (session_start + timedelta(seconds=sim_time)).isoformat()

    return {
        "type":       "timing_update",
        "url":        BASE_URL,
        "updated_at": timestamp,
        "headers":    ["P", "Kart", "Driver", "Lap Time", "Gap", "Int", "Best", "Laps", ""],
        "rows":       rows,
    }


# ─── Loop di simulazione ──────────────────────────────────────────────────────

def run_simulation(
    duration_minutes: int   = DEFAULT_DURATION_MINUTES,
    speed:            float = 10.0,
    seed:             Optional[int] = None,
    output_file:      str   = OUTPUT_FILE,
):
    if seed is not None:
        random.seed(seed)
        print(f"    Seed: {seed}")

    # Crea la directory padre se non esiste (es. --output /some/dir/live_timing.json)
    parent = os.path.dirname(os.path.abspath(output_file))
    os.makedirs(parent, exist_ok=True)

    drivers          = [Driver(**d) for d in DRIVERS]
    session_duration = duration_minutes * 60
    session_start    = datetime.now()

    sim_time     = 0.0
    update_count = 0

    print(f"\n🏁  PROVA LIBERA SIMULATA")
    print(f"    Durata: {duration_minutes} min  |  Piloti: {len(drivers)}")
    print(f"    Output: {output_file}  (sovrascrittura ad ogni giro)  |  Speed: {speed}x")
    print()
    print(f"  {'Tempo':>8}  {'G':>3}  {'Pilota':<22}  {'K':>3}  {'Giro':>10}  {'Migliore':>10}")
    print("  " + "─" * 66)

    while True:
        # Prossimo evento: primo pilota a completare un giro entro la fine sessione
        candidates = [(d.next_event, i, d) for i, d in enumerate(drivers)
                      if d.next_event <= session_duration]
        if not candidates:
            break
        candidates.sort(key=lambda x: (x[0], x[1]))  # stabile in caso di parità
        event_time, _, driver = candidates[0]

        # Attende il tempo reale proporzionato alla velocità di simulazione
        sleep_s = (event_time - sim_time) / speed
        time.sleep(max(0.0, sleep_s))

        sim_time = event_time

        # ── Completa il giro ──────────────────────────────────────────────────
        driver.lap_count += 1
        lap_t = simulate_lap(driver.base_time, driver.sigma, driver.lap_count)
        driver.lap_times.append(lap_t)
        driver.next_event = sim_time + lap_t   # pianifica il prossimo giro

        # ── Sovrascrive il singolo file JSON ─────────────────────────────────
        snapshot = build_snapshot(drivers, session_start, sim_time)
        with open(output_file, "w", encoding="utf-8") as f:
            json.dump(snapshot, f, indent=2, ensure_ascii=False)

        # ── Log a terminale ──────────────────────────────────────────────────
        is_new_best = (driver.best_lap == lap_t)
        flag = " ⚡" if is_new_best else ""
        print(
            f"  {sim_time/60:>6.2f}min"
            f"  G{driver.lap_count:>2d}"
            f"  {driver.name:<22}"
            f"  K{driver.kart}"
            f"  {seconds_to_laptime(lap_t):>10}"
            f"  {seconds_to_laptime(driver.best_lap):>10}"   # type: ignore[arg-type]
            + flag
        )

        update_count += 1

    # ─── Classifica finale ────────────────────────────────────────────────────
    print("\n" + "═" * 68)
    print("  CLASSIFICA FINALE — PROVA LIBERA")
    print("═" * 68)

    finished = sorted(
        [d for d in drivers if d.best_lap is not None],
        key=lambda d: d.best_lap,   # type: ignore[return-value]
    )
    no_time_final = [d for d in drivers if d.best_lap is None]

    leader_best = finished[0].best_lap if finished else 0.0
    for i, d in enumerate(finished, 1):
        gap_str = "          " if i == 1 else f"+{d.best_lap - leader_best:>9.3f}"   # type: ignore[operator]
        print(
            f"  P{i:2d}  K{d.kart}  {d.name:<22}"
            f"  {seconds_to_laptime(d.best_lap)}"   # type: ignore[arg-type]
            f"  {gap_str}"
            f"  {d.lap_count:2d} giri"
        )

    for d in no_time_final:
        print(f"  ---  K{d.kart}  {d.name:<22}  nessun giro completato")

    print("═" * 68)
    print(f"\n✅  {update_count} aggiornamenti scritti su '{output_file}'")


# ─── Entry point ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Simula una prova libera di kart aggiornando un singolo file JSON in place.",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument(
        "--speed",
        type=float,
        default=10.0,
        help="Velocità di simulazione rispetto al real-time (default: 10x).\n"
             "  --speed 1   → velocità reale (giro da 75s = attesa 75s)\n"
             "  --speed 10  → giro da 75s = attesa 7.5s  (default)\n"
             "  --speed 60  → 1 minuto simulato = 1 secondo reale",
    )
    parser.add_argument(
        "--duration",
        type=int,
        default=DEFAULT_DURATION_MINUTES,
        help=f"Durata della prova libera in minuti (default: {DEFAULT_DURATION_MINUTES})",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help="Seed random per risultati riproducibili",
    )
    parser.add_argument(
        "--output",
        type=str,
        default=OUTPUT_FILE,
        help=f"Percorso del file JSON di output (default: {OUTPUT_FILE})",
    )
    args = parser.parse_args()

    run_simulation(
        duration_minutes=args.duration,
        speed=args.speed,
        seed=args.seed,
        output_file=args.output,
    )
