"""
CHARGEMENT — landing zone vers la couche RAW.

La couche RAW reste fidèle à la source : chaque ligne du CSV est stockée telle
quelle en JSONB, avec ses métadonnées de traçabilité. Le nettoyage viendra
en staging.

IDEMPOTENCE : motif "delete-insert par partition". Avant d'insérer le lot du
jour, on supprime ce qui existe déjà pour cette date et cette métrique.
Relancer dix fois donne exactement le même résultat qu'une seule fois.
"""
import csv
import json
import sys
from datetime import date

import psycopg2
from psycopg2.extras import execute_values

from config import DATABASE_URL, DOSSIER_RAW

DDL = """
CREATE SCHEMA IF NOT EXISTS raw;

CREATE TABLE IF NOT EXISTS raw.covid_landing (
    id              BIGSERIAL PRIMARY KEY,
    date_ingestion  DATE        NOT NULL,
    metrique        TEXT        NOT NULL,
    numero_ligne    INT         NOT NULL,
    charge_utile    JSONB       NOT NULL,
    fichier_source  TEXT        NOT NULL,
    charge_le       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index sur la clé de partition : la suppression du lot doit être rapide.
CREATE INDEX IF NOT EXISTS idx_landing_partition
    ON raw.covid_landing (date_ingestion, metrique);
"""


def charger(jour_ingestion: str | None = None) -> dict:
    jour = jour_ingestion or date.today().isoformat()
    dossier = DOSSIER_RAW / jour
    if not dossier.exists():
        raise FileNotFoundError(f"Aucune extraction pour {jour} : {dossier}")

    resultats = {}
    with psycopg2.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(DDL)

            for chemin in sorted(dossier.glob("*.csv")):
                metrique = chemin.stem

                # 1. On efface la partition : c'est ce qui rend le job rejouable.
                cur.execute(
                    "DELETE FROM raw.covid_landing "
                    "WHERE date_ingestion = %s AND metrique = %s",
                    (jour, metrique),
                )
                supprimees = cur.rowcount

                # 2. On relit le CSV et on insère chaque ligne en JSONB.
                with chemin.open(encoding="utf-8-sig", newline="") as f:
                    lot = [
                        (jour, metrique, i, json.dumps(ligne), chemin.name)
                        for i, ligne in enumerate(csv.DictReader(f), start=1)
                    ]

                execute_values(
                    cur,
                    "INSERT INTO raw.covid_landing (date_ingestion, metrique, "
                    "numero_ligne, charge_utile, fichier_source) VALUES %s",
                    lot,
                    page_size=500,
                )
                resultats[metrique] = {"supprimees": supprimees,
                                       "inserees": len(lot)}
                print(f"  [{metrique:>9}] {supprimees:>5} supprimées → "
                      f"{len(lot):>5} insérées")
    return resultats


if __name__ == "__main__":
    jour = sys.argv[1] if len(sys.argv) > 1 else None
    print(f"CHARGEMENT RAW — {jour or date.today().isoformat()}")
    charger(jour)