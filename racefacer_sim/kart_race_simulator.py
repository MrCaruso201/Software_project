#!/usr/bin/env python3
"""
Karting Race Simulator
================================
Simula una gara di kart aggiornando un singolo file JSON in place,
esattamente come fa il sito RaceFacer. La tua app di scraping può leggere
quel file e troverà i dati aggiornati ad ogni giro completato.

Utilizzo:
    python kart_race_simulator.py                        # velocità 10x (default)
    python kart_race_simulator.py --speed 1              # velocità reale (1:1)
    python kart_race_simulator.py --speed 60             # 1 min simulato = 1 sec reale
    python kart_race_simulator.py --seed 42              # risultati riproducibili
    python kart_race_simulator.py --duration 20          # sessione da 20 minuti
    python kart_race_simulator.py --output percorso_precedente/Software_project/python_scraper_server/data/live_timing.json

Il file viene sovrascritto ad ogni evento (completamento giro), con un intervallo
reale pari al tempo del giro diviso per --speed.
"""

import json
import random
import os
import time
import argparse
import csv
from datetime import datetime, timedelta
from typing import List, Optional

# ─── Configurazione ───────────────────────────────────────────────────────────

# Percorso della directory dello script
script_dir = os.path.dirname(os.path.abspath(__file__))

DEFAULT_DURATION_MINUTES = 15           # Durata gara
OUTPUT_FILE              = script_dir + "/sim_data/live_timing.json"   # File unico sovrascritto ad ogni update
BASE_URL                 = "https://simulator"

# Piloti: nome, numero kart, tempo base giro (secondi), sigma (varianza = consistenza)
# team: nome della squadra (None = gara individuale)
# username: username dell'account app (None = pilota non iscritto)
DRIVERS = [
    {"name": "Marco Rossi",       "kart": "101", "base_time": 73.5, "sigma": 0.35, "team": "Scuderia Alpha", "username": "marco"},
    {"name": "Luca Ferrari",      "kart": "102", "base_time": 74.2, "sigma": 0.40, "team": "Scuderia Alpha", "username": None},
    {"name": "Sofia Esposito",    "kart": "103", "base_time": 75.8, "sigma": 0.55, "team": "Red Karts",     "username": None},
    {"name": "Giovanni Bianchi",  "kart": "104", "base_time": 76.1, "sigma": 0.45, "team": "Red Karts",     "username": None},
    {"name": "Elena Conti",       "kart": "105", "base_time": 77.0, "sigma": 0.60, "team": "Red Karts",     "username": None},
    {"name": "Andrea Ricci",      "kart": "106", "base_time": 73.8, "sigma": 0.38, "team": "Pit Stop FC",   "username": None},
    {"name": "Matteo Romano",     "kart": "107", "base_time": 78.5, "sigma": 0.70, "team": "Pit Stop FC",   "username": None},
    {"name": "Chiara Colombo",    "kart": "108", "base_time": 79.2, "sigma": 0.65, "team": "Pit Stop FC",   "username": None},
    {"name": "Francesco Mancini", "kart": "109", "base_time": 75.2, "sigma": 0.50, "team": None,            "username": None},
    {"name": "Valentina Leone",   "kart": "110", "base_time": 80.0, "sigma": 0.80, "team": None,            "username": None},
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
    def __init__(self, name: str, kart: str, base_time: float, sigma: float, grid_pos: int,
                 team: Optional[str] = None, username: Optional[str] = None):
        self.name      = name
        self.kart      = kart
        self.base_time = base_time
        self.sigma     = sigma
        self.team      = team        # nome della squadra (None = individuale)
        self.username  = username    # username app (None = non iscritto)

        self.lap_count: int         = 0
        self.lap_times: List[float] = []

        # Track position (tempo in cui ha tagliato il traguardo l'ultima volta)
        self.last_cross_time: float = 0.0

        # Simula una partenza in griglia: 0.5s di scarto tra ogni posizione
        self.initial_offset: float = grid_pos * 0.5
        
        # Genera in anticipo il tempo del primo giro
        self.current_lap_time: float = simulate_lap(base_time, sigma, 1)

        # Il primo evento sarà il momento in cui taglierà il primo traguardo
        self.next_event: float = self.initial_offset + self.current_lap_time

    @property
    def best_lap(self) -> Optional[float]:
        return min(self.lap_times) if self.lap_times else None

    @property
    def last_lap(self) -> Optional[float]:
        return self.lap_times[-1] if self.lap_times else None

    @property
    def total_time(self) -> float:
        return sum(self.lap_times) if self.lap_times else 0.0


# ─── Costruzione snapshot JSON ────────────────────────────────────────────────

def build_snapshot(
    drivers: List[Driver],
    session_start: datetime,
    sim_time: float,
) -> dict:
    """
    Costruisce il dict JSON di un singolo aggiornamento di timing.

    Classifica GARA: ordinata per numero di giri decrescente, e poi per tempo totale crescente.
    I piloti senza giri completi appaiono in fondo senza tempo.

    Colonne:
      P  | Kart | Driver | Lap Time (ultimo) | Gap (dal leader) | Int (dal precedente)
      Best (miglior personale) | Laps | (vuoto)
    """
    # Ordina chi ha completato almeno un giro per posizione in pista (laps desc, last_cross_time asc)
    ranked   : List[Driver] = sorted(
        [d for d in drivers if d.lap_count > 0],
        key=lambda d: (-d.lap_count, d.last_cross_time),
    )
    no_time  : List[Driver] = [d for d in drivers if d.lap_count == 0]
    classified = ranked + no_time

    leader: Optional[Driver] = ranked[0] if ranked else None

    rows = []
    for pos, driver in enumerate(classified, start=1):
        if driver.lap_count > 0:
            last_str = seconds_to_laptime(driver.last_lap)   # type: ignore[arg-type]
            best_str = seconds_to_laptime(driver.best_lap)

            if pos == 1:
                gap_str = "-"
                int_str = "-"
            else:
                # Gap = distacco dal leader in tempo assoluto di attraversamento
                assert leader is not None
                laps_behind_leader = leader.lap_count - driver.lap_count
                if laps_behind_leader == 0:
                    gap_val = driver.last_cross_time - leader.last_cross_time
                    gap_str = f"+{gap_val:.3f}"
                elif laps_behind_leader == 1:
                    # Stesso giro in corso, mostriamo il distacco al giro precedente completato da entrambi
                    leader_time_at_d_lap = leader.initial_offset + sum(leader.lap_times[:driver.lap_count])
                    gap_val = driver.last_cross_time - leader_time_at_d_lap
                    gap_str = f"+{gap_val:.3f}"
                else:
                    # Se il leader è avanti di 2 o più conteggi, ha effettivamente doppiato il pilota
                    laps_down = laps_behind_leader - 1
                    gap_str = f"+{laps_down} Laps" if laps_down > 1 else "+1 Lap"

                # Int = distacco dal pilota immediatamente davanti (prev_driver)
                prev_driver = classified[pos - 2]
                laps_behind_prev = prev_driver.lap_count - driver.lap_count
                if laps_behind_prev == 0:
                    int_val = driver.last_cross_time - prev_driver.last_cross_time
                    int_str = f"+{int_val:.3f}"
                elif laps_behind_prev == 1:
                    prev_time_at_d_lap = prev_driver.initial_offset + sum(prev_driver.lap_times[:driver.lap_count])
                    int_val = driver.last_cross_time - prev_time_at_d_lap
                    int_str = f"+{int_val:.3f}"
                else:
                    laps_down = laps_behind_prev - 1
                    int_str = f"+{laps_down} Laps" if laps_down > 1 else "+1 Lap"
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

    drivers          = [Driver(**d, grid_pos=i) for i, d in enumerate(DRIVERS)]
    session_duration = duration_minutes * 60
    session_start    = datetime.now()

    sim_time     = 0.0
    update_count = 0

    print(f"\n🏁  GARA SIMULATA")
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
        lap_t = driver.current_lap_time
        driver.lap_times.append(lap_t)
        driver.last_cross_time = sim_time
        
        # Pianifica il PROSSIMO giro
        next_lap_t = simulate_lap(driver.base_time, driver.sigma, driver.lap_count + 1)
        driver.current_lap_time = next_lap_t
        driver.next_event = sim_time + next_lap_t

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
    print("  CLASSIFICA FINALE — GARA")
    print("═" * 68)

    finished = sorted(
        [d for d in drivers if d.lap_count > 0],
        key=lambda d: (-d.lap_count, d.last_cross_time),
    )
    no_time_final = [d for d in drivers if d.lap_count == 0]

    leader = finished[0] if finished else None
    for i, d in enumerate(finished, 1):
        assert leader is not None
        if i == 1:
            gap_str = "Leader"
        else:
            if d.lap_count == leader.lap_count:
                gap_str = f"+{d.last_cross_time - leader.last_cross_time:>8.3f}s"
            else:
                laps_behind = leader.lap_count - d.lap_count
                gap_str = f"+{laps_behind} giri" if laps_behind > 1 else "+1 giro"

        print(
            f"  P{i:2d}  K{d.kart}  {d.name:<22}"
            f"  Tempo Tot: {seconds_to_laptime(d.total_time)}"
            f"  Gap: {gap_str:<10}"
            f"  ({d.lap_count:2d} giri)"
        )

    for d in no_time_final:
        print(f"  ---  K{d.kart}  {d.name:<22}  nessun giro completato")

    print("═" * 68)
    print(f"\n✅  {update_count} aggiornamenti scritti su '{output_file}'")
    
    # ─── Salva CSV ────────────────────────────────────────────────────────────
    csv_file = output_file.rsplit('.', 1)[0] + ".csv"
    try:
        with open(csv_file, mode="w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["Posizione", "Pilota", "Squadra", "Miglior Giro", "Gap", "Giri", "username"])
            
            # Calcola la posizione in base al team (stessa pos per tutti i membri del team)
            team_positions: dict = {}
            pos_counter = 1
            for d in finished:
                team_key = d.team if d.team else d.name  # Piloti individuali: chiave = nome
                if team_key not in team_positions:
                    team_positions[team_key] = pos_counter
                    pos_counter += 1

            for i, d in enumerate(finished, 1):
                assert leader is not None
                if i == 1:
                    gap_str = "Leader"
                else:
                    if d.lap_count == leader.lap_count:
                        gap_str = f"+{d.last_cross_time - leader.last_cross_time:.3f}s"
                    else:
                        laps_behind = leader.lap_count - d.lap_count
                        gap_str = f"+{laps_behind} giro" if laps_behind == 1 else f"+{laps_behind} giri"

                best_lap_str = seconds_to_laptime(d.best_lap) if d.best_lap else "-"
                team_key = d.team if d.team else d.name
                position = team_positions.get(team_key, i)
                writer.writerow([
                    str(position),
                    d.name,
                    d.team if d.team else "",
                    best_lap_str,
                    gap_str,
                    str(d.lap_count),
                    d.username if d.username else "",
                ])

            for d in no_time_final:
                team_key = d.team if d.team else d.name
                position = team_positions.get(team_key, "-")
                writer.writerow([
                    str(position), d.name,
                    d.team if d.team else "",
                    "-", "-", "0",
                    d.username if d.username else ""
                ])
        print(f"✅  Classifica finale salvata in CSV su '{csv_file}'")
    except Exception as e:
        print(f"⚠️  Errore durante il salvataggio del CSV: {e}")


# ─── Entry point ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Simula una gara di kart aggiornando un singolo file JSON in place.",
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
        help=f"Durata della gara in minuti (default: {DEFAULT_DURATION_MINUTES})",
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
