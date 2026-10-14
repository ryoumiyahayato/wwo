"""CLI and CSV output; the model is implemented separately in economy.py."""
import argparse
import csv
import json
from pathlib import Path

from economy import Simulation


def write_csv(path, rows):
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path, default=Path(__file__).with_name("fixture.json"))
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).parent)
    args = parser.parse_args()
    config = json.loads(args.fixture.read_text(encoding="utf-8"))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for scenario in config["scenarios"]:
        simulation = Simulation(config, scenario).run()
        write_csv(args.output_dir / f"{scenario}.csv", simulation.rows)
        write_csv(args.output_dir / f"{scenario}_order_trace.csv", simulation.events)
        print(f"{scenario}: days={simulation.day}, deliveries={simulation.cumulative['terminal_delivered']}, "
              f"peak_backlog={max(r['terminal_backlog'] for r in simulation.rows)}, "
              f"final_backlog={simulation.backlog}, residuals={simulation.check_accounts()}")


if __name__ == "__main__":
    main()
