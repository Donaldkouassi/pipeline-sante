#!/usr/bin/env python3
"""
ORCHESTRATEUR — enchaîne les étapes et s'arrête à la première erreur.

Usage :
    python run_pipeline.py                 # date du jour
    python run_pipeline.py 2026-09-02      # rejoue une date précise
"""
import sys
import time
from datetime import date
from pathlib import Path

import psycopg2

sys.path.insert(0, str(Path(__file__).resolve().parent / "ingestion"))

from config import DATABASE_URL, DOSSIER_SQL   # noqa: E402
import extract                                 # noqa: E402
import load_raw                                # noqa: E402


def executer_sql(fichier: str, params: dict | None = None) -> None:
    chemin = DOSSIER_SQL / fichier
    with psycopg2.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(chemin.read_text(encoding="utf-8"), params or {})


def lancer_tests() -> None:
    """Seuls les tests de sévérité 'erreur' bloquent la pipeline."""
    chemin = DOSSIER_SQL / "03_tests.sql"
    blocs = [b for b in chemin.read_text(encoding="utf-8").split(";") if b.strip()]

    bloquants, avertissements = [], []
    with psycopg2.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            numero = 0
            for bloc in blocs:
                code = "\n".join(l for l in bloc.splitlines()
                                 if l.strip() and not l.strip().startswith("--"))
                if not code.strip():
                    continue
                numero += 1
                severite = ("avertissement"
                            if "@severite: avertissement" in bloc else "erreur")
                cur.execute(bloc)
                lignes = cur.fetchall()
                nom = lignes[0][0] if lignes else f"test_{numero}"

                if not lignes:
                    print(f"  OK        test {numero}")
                elif severite == "erreur":
                    bloquants.append(nom)
                    print(f"  ECHEC     {nom} : {len(lignes)} ligne(s)")
                else:
                    avertissements.append(nom)
                    print(f"  ATTENTION {nom} : {len(lignes)} ligne(s) "
                          f"(anomalie de la source, non bloquante)")

    if bloquants:
        raise SystemExit(f"\nPIPELINE ARRETE : {len(bloquants)} test(s) bloquant(s).")
    if avertissements:
        print(f"    {len(avertissements)} avertissement(s) — données livrées.")


def etape(numero: int, libelle: str, fonction) -> None:
    print(f"\n[{numero}] {libelle}")
    debut = time.time()
    fonction()
    print(f"    terminé en {time.time() - debut:.1f}s")


def main() -> None:
    jour = sys.argv[1] if len(sys.argv) > 1 else date.today().isoformat()
    print("=" * 62)
    print(f"PIPELINE SANTÉ — date d'ingestion : {jour}")
    print("=" * 62)

    etape(1, "Extraction vers la landing zone", lambda: extract.extraire(jour))
    etape(2, "Chargement de la couche RAW", lambda: load_raw.charger(jour))
    etape(3, "Transformation STAGING",
          lambda: executer_sql("01_staging.sql", {"date_ingestion": jour}))
    etape(4, "Construction des MARTS", lambda: executer_sql("02_marts.sql"))
    etape(5, "Tests de qualité", lancer_tests)

    print("\n" + "=" * 62)
    print("PIPELINE TERMINÉ AVEC SUCCÈS")
    print("=" * 62)


if __name__ == "__main__":
    main()