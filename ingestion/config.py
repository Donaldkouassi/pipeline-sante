"""Configuration centralisée : jamais de mot de passe en dur dans le code."""
import os
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
DOSSIER_RAW = RACINE / "data" / "raw"
DOSSIER_SQL = RACINE / "sql"


def _charger_env():
    """Lit .env s'il existe, sinon on garde les valeurs par défaut."""
    fichier = RACINE / ".env"
    if fichier.exists():
        for ligne in fichier.read_text().splitlines():
            ligne = ligne.strip()
            if ligne and not ligne.startswith("#") and "=" in ligne:
                cle, _, val = ligne.partition("=")
                os.environ.setdefault(cle.strip(), val.strip())


_charger_env()

DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgresql://data_eng:data_eng@localhost:5433/sante"
)