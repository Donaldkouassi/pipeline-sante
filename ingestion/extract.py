"""
EXTRACTION — source externe vers la zone d'atterrissage (landing zone).

Principe : on ne transforme RIEN. On copie la source, on l'horodate, on calcule
une empreinte du contenu.
"""
import hashlib
import json
import sys
from datetime import date

import requests

from config import DOSSIER_RAW

BASE = ("https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/"
        "csse_covid_19_data/csse_covid_19_time_series/")

SOURCES = {
    "confirmed": "time_series_covid19_confirmed_global.csv",
    "deaths": "time_series_covid19_deaths_global.csv",
    "recovered": "time_series_covid19_recovered_global.csv",
}


def empreinte(contenu: bytes) -> str:
    """SHA-256 : permet de savoir si la source a changé depuis hier."""
    return hashlib.sha256(contenu).hexdigest()


def extraire(jour_ingestion: str | None = None) -> dict:
    """Télécharge chaque source dans data/raw/<date>/<metrique>.csv.

    Idempotent : le chemin est déterministe, donc relancer pour la même date
    réécrit le même fichier. Aucun doublon possible.
    """
    jour = jour_ingestion or date.today().isoformat()
    cible = DOSSIER_RAW / jour
    cible.mkdir(parents=True, exist_ok=True)

    manifeste = {"date_ingestion": jour, "fichiers": {}}

    for metrique, fichier in SOURCES.items():
        reponse = requests.get(BASE + fichier, timeout=120)
        reponse.raise_for_status()      # on échoue fort et tôt, jamais en silence
        contenu = reponse.content

        (cible / f"{metrique}.csv").write_bytes(contenu)

        manifeste["fichiers"][metrique] = {
            "url": BASE + fichier,
            "octets": len(contenu),
            "sha256": empreinte(contenu),
        }
        print(f"  [{metrique:>9}] {len(contenu):>9,} octets  "
              f"sha256={empreinte(contenu)[:12]}…")

    (cible / "_manifeste.json").write_text(
        json.dumps(manifeste, indent=2), encoding="utf-8"
    )
    return manifeste


if __name__ == "__main__":
    jour = sys.argv[1] if len(sys.argv) > 1 else None
    print(f"EXTRACTION — {jour or date.today().isoformat()}")
    extraire(jour)