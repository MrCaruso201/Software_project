#!/usr/bin/env python3
"""
Karting Team Race Simulator
================================
Simula una gara di kart A SQUADRE con pit stop per cambio pilota.
Ogni squadra ha più piloti che si alternano in pista tramite soste ai box.
Il file JSON viene aggiornato ad ogni giro completato, esattamente come il
simulatore individuale. Al termine viene salvata anche una classifica CSV.

Utilizzo:
    python kart_team_race_simulator.py                        # velocità 10x (default)
    python kart_team_race_simulator.py --speed 1              # velocità reale
    python kart_team_race_simulator.py --speed 60             # 1 min sim = 1 sec reale
    python kart_team_race_simulator.py --seed 42              # risultati riproducibili
    python kart_team_race_simulator.py --duration 60          # 60 min di gara
    python kart_team_race_simulator.py --pit-duration 90      # pit stop da 90 secondi

Struttura del file JSON: identica al simulatore individuale (compatibile con lo scraper).
Classifica CSV: Posizione, Pilota, Squadra, Miglior Giro, Gap, Giri, username
"""

import json
import random
import os
import time
import argparse
import csv
from datetime import datetime, timedelta
from typing import List, Optional, Dict

# ─── Configurazione ───────────────────────────────────────────────────────────

script_dir = os.path.dirname(os.path.abspath(__file__))

DEFAULT_DURATION_MINUTES = 60       # Gara endurance: 1 ora
DEFAULT_PIT_DURATION_SEC = 60       # Sosta ai box: 1 minuto fisso
OUTPUT_FILE = script_dir + "/sim_data/live_timing.json"
BASE_URL    = "https://live.racefacer.com/simulator"

# Squadre: ogni squadra ha una lista di piloti con i propri parametri
# min_stint / max_stint: durata minima/massima dello stint in secondi prima di poter/dover rientrare
TEAMS: List[Dict] = [
    {
        "name": "Scuderia Alpha",
        "kart": "101",
        "min_stint": 600,    # almeno 10 min in pista
        "max_stint": 1200,   # massimo 20 min prima del pit obbligatorio
        "drivers": [
            {"name": "Marco Rossi",   "base_time": 73.5, "sigma": 0.35, "username": "marco"},
            {"name": "Luca Ferrari",  "base_time": 74.2, "sigma": 0.40, "username": None},
            {"name": "Sofia Conti",   "base_time": 75.0, "sigma": 0.45, "username": "sofia"},
        ],
    },
    {
        "name": "Red Karts",
        "kart": "102",
        "min_stint": 600,
        "max_stint": 1200,
        "drivers": [
            {"name": "Andrea Ricci",     "base_time": 73.8, "sigma": 0.38, "username": None},
            {"name": "Giovanni Bianchi", "base_time": 76.1, "sigma": 0.45, "username": None},
            {"name": "Elena Bruno",      "base_time": 77.0, "sigma": 0.60, "username": None},
        ],
    },
    {
        "name": "Pit Stop FC",
        "kart": "103",
        "min_stint": 700,
        "max_stint": 1100,
        "drivers": [
            {"name": "Matteo Romano",  "base_time": 74.5, "sigma": 0.55, "username": None},
            {"name": "Chiara Colombo", "base_time": 79.2, "sigma": 0.65, "username": None},
        ],
    },
    {
        "name": "Thunder Bulls",
        "kart": "104",
        "min_stint": 500,
        "max_stint": 1300,
        "drivers": [
            {"name": "Francesco Mancini", "base_time": 75.2, "sigma": 0.50, "username": None},
            {"name": "Valentina Leone",   "base_time": 76.8, "sigma": 0.62, "username": None},
            {"name": "Roberto Gallo",     "base_time": 77.5, "sigma": 0.58, "username": None},
        ],
    },
    {
        "name": "Veloce Racing",
        "kart": "105",
        "min_stint": 600,
        "max_stint": 1200,
        "drivers": [
            {"name": "Sara Fontana",  "base_time": 74.8, "sigma": 0.42, "username": None},
            {"name": "Paolo Marini",  "base_time": 76.3, "sigma": 0.50, "username": None},
        ],
    },
]

# ─── Utilità ──────────────────────────────────────────────────────────────────

def seconds_to_laptime(seconds: float) -> str:
    """Converte secondi float nel formato M:SS.mmm  (es. 1:13.742)"""
    minutes = int(seconds // 60)
    secs    = seconds % 60
    return f"{minutes}:{secs:06.3f}"


def simulate_lap(base_time: float, sigma: float, lap_num: int) -> float:
    """Genera un tempo giro realistico con varianza e penalità di riscaldamento."""
    if lap_num == 1:
        penalty = random.uniform(4.0, 10.0)
    elif lap_num == 2:
        penalty = random.uniform(1.5, 4.0)
    elif lap_num == 3:
        penalty = random.uniform(0.3, 1.5)
    else:
        penalty = 0.0

    improvement = min(0.08 * max(0, lap_num - 4), 1.2) if lap_num > 4 else 0.0
    variance    = random.gauss(0, sigma)
    lap_time    = base_time + penalty - improvement + variance
    return max(lap_time, base_time * 0.98)


# ─── Stato pilota (dentro una squadra) ───────────────────────────────────────

class TeamDriver:
    def __init__(self, name: str, base_time: float, sigma: float, username: Optional[str]):
        self.name      = name
        self.base_time = base_time
        self.sigma     = sigma
        self.username  = username

        self.lap_count: int         = 0
        self.lap_times: List[float] = []   # solo giri completati da questo pilota

    @property
    def best_lap(self) -> Optional[float]:
        return min(self.lap_times) if self.lap_times else None

    @property
    def total_drive_time(self) -> float:
        return sum(self.lap_times)


# ─── Stato squadra ────────────────────────────────────────────────────────────

class Team:
    def __init__(self, cfg: Dict, grid_pos: int):
        self.name        = cfg["name"]
        self.kart        = cfg["kart"]
        self.min_stint   = cfg["min_stint"]
        self.max_stint   = cfg["max_stint"]

        self.drivers: List[TeamDriver] = [
            TeamDriver(d["name"], d["base_time"], d["sigma"], d["username"])
            for d in cfg["drivers"]
        ]

        # ── Stato gara ────────────────────────────────────────────────
        self.current_driver_idx: int = 0          # indice pilota attivo
        self.current_stint_time: float = 0.0      # secondi passati in pista in questo stint
        self.current_lap_in_stint: int = 0        # giri nello stint corrente (per penalità in-lap)
        self.lap_count: int = 0                   # giri totali della squadra (kart)
        self.lap_times: List[float] = []          # tempo di ogni giro completato dal kart
        self.last_cross_time: float = 0.0         # tempo simulato dell'ultimo traguardo tagliato
        self.in_pit: bool = False                 # True mentre il kart è ai box
        self.pit_end_time: float = 0.0            # quando finirà la sosta corrente
        self.total_pit_time: float = 0.0          # tempo totale speso ai box

        # Partenza sfalsata in griglia
        self.initial_offset: float = grid_pos * 0.5

        # Pre-genera il primo giro
        driver = self.current_driver
        self.current_lap_time: float = simulate_lap(driver.base_time, driver.sigma, 1)
        self.next_event: float = self.initial_offset + self.current_lap_time

    @property
    def current_driver(self) -> TeamDriver:
        return self.drivers[self.current_driver_idx]

    @property
    def best_lap(self) -> Optional[float]:
        return min(self.lap_times) if self.lap_times else None

    @property
    def last_lap(self) -> Optional[float]:
        return self.lap_times[-1] if self.lap_times else None

    def should_pit(self) -> bool:
        """Decide se la squadra deve/può fare il pit stop dopo questo giro."""
        # Solo se c'è più di un pilota
        if len(self.drivers) == 1:
            return False
        # Pit obbligatorio se supera il max stint
        if self.current_stint_time >= self.max_stint:
            return True
        # Pit facoltativo se supera il min stint con una probabilità crescente
        if self.current_stint_time >= self.min_stint:
            overtime = self.current_stint_time - self.min_stint
            window   = self.max_stint - self.min_stint
            prob     = overtime / window  # 0→1 man mano che si avvicina al max
            if random.random() < prob * 0.4:   # smorzato: decisione graduale
                return True
        return False

    def do_pit_stop(self, sim_time: float, pit_duration: float) -> None:
        """Esegue il cambio pilota e imposta il tempo di fine sosta."""
        self.in_pit       = True
        self.pit_end_time = sim_time + pit_duration
        self.total_pit_time += pit_duration

        # Cambia pilota (round-robin)
        self.current_driver_idx = (self.current_driver_idx + 1) % len(self.drivers)
        self.current_stint_time = 0.0
        self.current_lap_in_stint = 0

        # Primo giro del nuovo pilota (ha la penalità out-lap)
        driver = self.current_driver
        self.current_lap_time = simulate_lap(driver.base_time, driver.sigma, 1)
        # Il prossimo evento è la fine sosta + il primo giro
        self.next_event = self.pit_end_time + self.current_lap_time


# ─── Costruzione snapshot JSON ────────────────────────────────────────────────

def build_snapshot(teams: List[Team], session_start: datetime, sim_time: float) -> dict:
    """
    Costruisce il dict JSON aggiornamento timing.

    Classifica: giri totali decrescenti, poi last_cross_time crescente.
    Headers: P | Kart | Driver (pilota attivo) | Lap Time | Gap | Int | Best | Laps | Pit
    """
    ranked   = sorted([t for t in teams if t.lap_count > 0],
                      key=lambda t: (-t.lap_count, t.last_cross_time))
    no_time  = [t for t in teams if t.lap_count == 0]
    classified = ranked + no_time

    leader: Optional[Team] = ranked[0] if ranked else None

    rows = []
    for pos, team in enumerate(classified, start=1):
        if team.lap_count > 0:
            last_str = seconds_to_laptime(team.last_lap)      # type: ignore[arg-type]
            best_str = seconds_to_laptime(team.best_lap)      # type: ignore[arg-type]

            if pos == 1:
                gap_str = "-"
                int_str = "-"
            else:
                assert leader is not None
                laps_behind_leader = leader.lap_count - team.lap_count
                if laps_behind_leader == 0:
                    gap_val = team.last_cross_time - leader.last_cross_time
                    gap_str = f"+{gap_val:.3f}"
                elif laps_behind_leader == 1:
                    leader_time = leader.initial_offset + sum(leader.lap_times[:team.lap_count])
                    gap_val = team.last_cross_time - leader_time
                    gap_str = f"+{gap_val:.3f}"
                else:
                    laps_down = laps_behind_leader - 1
                    gap_str = f"+{laps_down} Laps" if laps_down > 1 else "+1 Lap"

                prev_team = classified[pos - 2]
                laps_behind_prev = prev_team.lap_count - team.lap_count
                if laps_behind_prev == 0:
                    int_val = team.last_cross_time - prev_team.last_cross_time
                    int_str = f"+{int_val:.3f}"
                elif laps_behind_prev == 1:
                    prev_time = prev_team.initial_offset + sum(prev_team.lap_times[:team.lap_count])
                    int_val = team.last_cross_time - prev_time
                    int_str = f"+{int_val:.3f}"
                else:
                    laps_down = laps_behind_prev - 1
                    int_str = f"+{laps_down} Laps" if laps_down > 1 else "+1 Lap"
        else:
            last_str = "-"
            best_str = "-"
            gap_str  = "-"
            int_str  = "-"

        pit_str = "PIT" if team.in_pit else ""

        rows.append([
            str(pos),
            team.kart,
            f"{team.current_driver.name} [{team.name}]",
            last_str,
            gap_str,
            int_str,
            best_str,
            str(team.lap_count),
            pit_str,
        ])

    timestamp = (session_start + timedelta(seconds=sim_time)).isoformat()

    return {
        "type":       "timing_update",
        "url":        BASE_URL,
        "updated_at": timestamp,
        "headers":    ["P", "Kart", "Driver", "Lap Time", "Gap", "Int", "Best", "Laps", "Pit"],
        "rows":       rows,
    }


# ─── Loop di simulazione ──────────────────────────────────────────────────────

def run_simulation(
    duration_minutes: int   = DEFAULT_DURATION_MINUTES,
    speed:            float = 10.0,
    pit_duration:     float = DEFAULT_PIT_DURATION_SEC,
    seed:             Optional[int] = None,
    output_file:      str   = OUTPUT_FILE,
):
    if seed is not None:
        random.seed(seed)
        print(f"    Seed: {seed}")

    parent = os.path.dirname(os.path.abspath(output_file))
    os.makedirs(parent, exist_ok=True)

    teams            = [Team(cfg, i) for i, cfg in enumerate(TEAMS)]
    session_duration = duration_minutes * 60
    session_start    = datetime.now()

    sim_time     = 0.0
    update_count = 0

    print(f"\n🏁  GARA A SQUADRE SIMULATA")
    print(f"    Durata: {duration_minutes} min  |  Squadre: {len(teams)}  |  Pit stop: {pit_duration:.0f}s")
    print(f"    Output: {output_file}  |  Speed: {speed}x")
    print()
    print(f"  {'Tempo':>8}  {'G':>3}  {'Squadra':<18}  {'Pilota':<20}  {'Giro':>10}  {'Pit'}")
    print("  " + "─" * 74)

    while True:
        # Prossimo evento: completamento giro (tutte le squadre, anche quelle in pit)
        # Le squadre in pit hanno next_event = pit_end_time + lap_time, quindi
        # verranno selezionate solo quando la sosta sarà finita e il giro completato.
        candidates = [
            (t.next_event, i, t)
            for i, t in enumerate(teams)
            if t.next_event <= session_duration
        ]
        if not candidates:
            break
        candidates.sort(key=lambda x: (x[0], x[1]))
        event_time, _, team = candidates[0]

        sleep_s = (event_time - sim_time) / speed
        time.sleep(max(0.0, sleep_s))
        sim_time = event_time

        # ── Uscita dal pit (se la sosta è terminata) ──────────────────
        if team.in_pit:
            team.in_pit = False   # La sosta è finita, il pilota rientra in gara

        # ── Completa il giro ──────────────────────────────────────────
        driver = team.current_driver
        lap_t  = team.current_lap_time
        team.lap_count += 1
        team.lap_times.append(lap_t)
        team.last_cross_time = sim_time
        driver.lap_count += 1
        driver.lap_times.append(lap_t)
        team.current_stint_time += lap_t
        team.current_lap_in_stint += 1

        # ── Decisione pit stop ────────────────────────────────────────
        pit_this_lap = team.should_pit() and (sim_time + pit_duration < session_duration)
        pit_flag = ""

        if pit_this_lap:
            team.do_pit_stop(sim_time, pit_duration)
            pit_flag = " 🔧"
        else:
            # Prossimo giro nello stesso stint
            next_lap_t = simulate_lap(driver.base_time, driver.sigma, team.current_lap_in_stint + 1)
            team.current_lap_time = next_lap_t
            team.next_event = sim_time + next_lap_t

        # ── Sovrascrive il file JSON ──────────────────────────────────
        snapshot = build_snapshot(teams, session_start, sim_time)
        with open(output_file, "w", encoding="utf-8") as f:
            json.dump(snapshot, f, indent=2, ensure_ascii=False)

        # ── Log a terminale ───────────────────────────────────────────
        is_new_best = (team.best_lap == lap_t)
        flag = " ⚡" if is_new_best else ""
        print(
            f"  {sim_time/60:>6.2f}min"
            f"  G{team.lap_count:>2d}"
            f"  {team.name:<18}"
            f"  {driver.name:<20}"
            f"  {seconds_to_laptime(lap_t):>10}"
            + flag + pit_flag
        )

        update_count += 1

    # ─── Classifica finale ────────────────────────────────────────────────────
    print("\n" + "═" * 72)
    print("  CLASSIFICA FINALE — GARA A SQUADRE")
    print("═" * 72)

    finished = sorted(
        [t for t in teams if t.lap_count > 0],
        key=lambda t: (-t.lap_count, t.last_cross_time),
    )
    no_time_final = [t for t in teams if t.lap_count == 0]
    leader = finished[0] if finished else None

    for i, t in enumerate(finished, 1):
        assert leader is not None
        if i == 1:
            gap_str = "Leader"
        else:
            if t.lap_count == leader.lap_count:
                gap_str = f"+{t.last_cross_time - leader.last_cross_time:>8.3f}s"
            else:
                laps_behind = leader.lap_count - t.lap_count
                gap_str = f"+{laps_behind} giri" if laps_behind > 1 else "+1 giro"

        print(
            f"  P{i:2d}  K{t.kart}  {t.name:<18}"
            f"  Giri: {t.lap_count:2d}"
            f"  Gap: {gap_str:<12}"
            f"  Pit: {t.total_pit_time/60:.1f}min"
        )
        for d in t.drivers:
            best_str = seconds_to_laptime(d.best_lap) if d.best_lap else "-"
            print(f"         └ {d.name:<22}  giri: {d.lap_count:2d}  best: {best_str}")

    for t in no_time_final:
        print(f"  ---  K{t.kart}  {t.name:<18}  nessun giro completato")

    print("═" * 72)
    print(f"\n✅  {update_count} aggiornamenti scritti su '{output_file}'")

    # ─── Salva CSV ────────────────────────────────────────────────────────────
    csv_file = output_file.rsplit('.', 1)[0] + ".csv"
    try:
        with open(csv_file, mode="w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["Posizione", "Pilota", "Squadra", "Miglior Giro", "Gap", "Giri", "username"])

            for i, t in enumerate(finished, 1):
                assert leader is not None
                if i == 1:
                    gap_str = "Leader"
                else:
                    if t.lap_count == leader.lap_count:
                        gap_str = f"+{t.last_cross_time - leader.last_cross_time:.3f}s"
                    else:
                        laps_behind = leader.lap_count - t.lap_count
                        gap_str = f"+{laps_behind} giro" if laps_behind == 1 else f"+{laps_behind} giri"

                for d in t.drivers:
                    best_lap_str = seconds_to_laptime(d.best_lap) if d.best_lap else "-"
                    writer.writerow([
                        str(i),
                        d.name,
                        t.name,
                        best_lap_str,
                        gap_str,
                        str(d.lap_count),
                        d.username if d.username else "",
                    ])

            for t in no_time_final:
                for d in t.drivers:
                    writer.writerow(["-", d.name, t.name, "-", "-", "0", d.username if d.username else ""])

        print(f"✅  Classifica finale salvata in CSV su '{csv_file}'")
    except Exception as e:
        print(f"⚠️  Errore durante il salvataggio del CSV: {e}")


# ─── Entry point ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Simula una gara di kart A SQUADRE con pit stop per cambio pilota.",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument(
        "--speed",
        type=float,
        default=10.0,
        help="Velocità di simulazione rispetto al real-time (default: 10x).\n"
             "  --speed 1   → velocità reale\n"
             "  --speed 60  → 1 minuto simulato = 1 secondo reale",
    )
    parser.add_argument(
        "--duration",
        type=int,
        default=DEFAULT_DURATION_MINUTES,
        help=f"Durata della gara in minuti (default: {DEFAULT_DURATION_MINUTES})",
    )
    parser.add_argument(
        "--pit-duration",
        type=float,
        default=DEFAULT_PIT_DURATION_SEC,
        help=f"Durata fissa del pit stop in secondi (default: {DEFAULT_PIT_DURATION_SEC})",
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
        pit_duration=args.pit_duration,
        seed=args.seed,
        output_file=args.output,
    )
