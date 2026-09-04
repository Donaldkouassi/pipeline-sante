#!/usr/bin/env python3
"""
ORCHESTRATEUR — enchaîne les étapes et s'arrête à la première erreur.

Deux chemins de transformation coexistent volontairement :

  --dbt  (défaut)  les transformations sont gérées par dbt : ordre déduit des
                   références, tests déclaratifs, lignage et documentation.
  --sql            la version d'origine, en SQL brut ordonné à la main.
                   Conservée comme référence : c'est ce que dbt automatise.

Usage :
    python run_pipeline.py                      # aujourd'hui, via dbt
    python run_pipeline.py 2026-09-02           # rejoue une date précise
    python run_pipeline.py 2026-09-02 --sql     # même date, sans dbt
"""
import json
import subprocess
import sys
import time
from datetime import date
from pathlib import Path

import psycopg2

RACINE = Path(__file__).resolve().parent
sys.path.insert(0, str(RACINE / "ingestion"))

from config import DATABASE_URL, DOSSIER_SQL   # noqa: E402
import extract                                 # noqa: E402
import load_raw                                # noqa: E402

DOSSIER_DBT = RACINE / "dbt_sante"


# --------------------------------------------------------------------------
# Chemin dbt
# --------------------------------------------------------------------------
def lancer_dbt(jour: str) -> None:
    """Délègue transformations ET tests à dbt.

    `dbt build` exécute les modèles dans l'ordre déduit des `ref()`, puis les
    tests de chaque modèle. Il sort en code 1 si un test de sévérité 'error'
    échoue, en code 0 sur un simple avertissement — exactement la distinction
    que nous avions codée à la main.
    """
    commande = [
        "dbt", "build",
        "--profiles-dir", ".",
        "--vars", json.dumps({"date_ingestion": jour}),
    ]
    resultat = subprocess.run(commande, cwd=DOSSIER_DBT)
    if resultat.returncode != 0:
        raise SystemExit("\nPIPELINE ARRETE : dbt a signalé une erreur.")


# --------------------------------------------------------------------------
# Chemin SQL brut (version d'origine)
# --------------------------------------------------------------------------
def executer_sql(fichier: str, params: dict | None = None) -> None:
    chemin = DOSSIER_SQL / fichier
    with psycopg2.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(chemin.read_text(encoding="utf-8"), params or {})


def lancer_tests_sql() -> None:
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


# --------------------------------------------------------------------------
def etape(numero: int, libelle: str, fonction) -> None:
    print(f"\n[{numero}] {libelle}")
    debut = time.time()
    fonction()
    print(f"    terminé en {time.time() - debut:.1f}s")


def main() -> None:
    arguments = [a for a in sys.argv[1:] if not a.startswith("--")]
    options = [a for a in sys.argv[1:] if a.startswith("--")]

    jour = arguments[0] if arguments else date.today().isoformat()
    moteur = "sql" if "--sql" in options else "dbt"

    print("=" * 62)
    print(f"PIPELINE SANTÉ — date : {jour} — transformations : {moteur}")
    print("=" * 62)

    etape(1, "Extraction vers la landing zone", lambda: extract.extraire(jour))
    etape(2, "Chargement de la couche RAW", lambda: load_raw.charger(jour))

    if moteur == "dbt":
        etape(3, "Transformations et tests (dbt build)", lambda: lancer_dbt(jour))
    else:
        etape(3, "Transformation STAGING",
              lambda: executer_sql("01_staging.sql", {"date_ingestion": jour}))
        etape(4, "Construction des MARTS", lambda: executer_sql("02_marts.sql"))
        etape(5, "Tests de qualité", lancer_tests_sql)

    print("\n" + "=" * 62)
    print("PIPELINE TERMINÉ AVEC SUCCÈS")
    print("=" * 62)


if __name__ == "__main__":
    main()
