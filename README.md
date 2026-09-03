# Pipeline de données santé publique — COVID-19

Pipeline ELT complète : ingestion d'une source publique, entreposage en couches,
modélisation en schéma en étoile et tests de qualité automatisés.

**Stack** : Python · PostgreSQL · SQL · Docker

---

## Le problème

Les séries temporelles COVID-19 de Johns Hopkins (CSSE) sont publiées dans un
format inexploitable en l'état :

| Défaut de la source | Conséquence |
|---|---|
| 1 143 colonnes de dates | Format large, impossible à agréger en SQL |
| Valeurs cumulées depuis 2020 | Mesure semi-additive : `SUM` dans le temps donne un résultat faux |
| Grain incohérent (la France sur 12 lignes) | Double comptage ou perte de territoires |
| Corrections rétroactives négatives | 362 incréments négatifs |

## L'architecture

```
Source (GitHub CSSE)
   │
   ├─ 1. EXTRACTION ──► data/raw/<date>/*.csv  + manifeste SHA-256
   │                    (copie fidèle, horodatée, traçable)
   │
   ├─ 2. RAW ─────────► raw.covid_landing (JSONB)
   │                    (aucun nettoyage — filet de sécurité)
   │
   ├─ 3. STAGING ─────► staging.covid_long  (973 836 lignes)
   │                    dépivotage · typage · cumul → incrément quotidien
   │
   ├─ 4. MARTS ───────► marts.dim_pays · marts.dim_date
   │                    marts.fait_covid_journalier (331 470 lignes)
   │                    schéma en étoile, grain pays × territoire × jour
   │
   └─ 5. TESTS ───────► unicité · intégrité · complétude · réconciliation
```

## Décisions de conception

**Idempotence par delete-insert.** Avant chaque insertion, la partition
`(date_ingestion, métrique)` est supprimée. Relancer le job dix fois produit
exactement le même résultat qu'une seule exécution — condition nécessaire pour
exploiter une pipeline en production, où les jobs échouent et sont rejoués.

**Couche RAW non transformée.** Les données sont stockées en JSONB, telles que
reçues. Si une règle de nettoyage se révèle fausse, l'original est intact.

**Grain le plus fin (règle de Kimball).** La table de faits conserve le détail
territorial ; l'agrégation au niveau pays se fait à la lecture via une vue. On
peut toujours agréger vers le haut, jamais redescendre.

**Clés de substitution.** `id_pays` est un entier généré, indépendant du nom du
pays dans la source. Un renommage amont ne casse pas l'historique.

**Deux niveaux de gravité des tests.** Les tests structurels (unicité, intégrité,
réconciliation) bloquent la pipeline. Les anomalies légitimes de la source
(décès supérieurs aux cas lors de régularisations) émettent un avertissement.
Un test qui bloque à tort finit désactivé par l'équipe.

## Résultats de validation

| Contrôle | Résultat |
|---|---|
| Unicité du grain | ✅ 0 doublon sur 331 470 lignes |
| Intégrité référentielle | ✅ 0 fait orphelin |
| Complétude des dates | ✅ 1 143 / 1 143 jours |
| Réconciliation incréments / cumul source | ✅ écart nul sur les 201 pays |
| Plage de valeurs | ⚠️ 1 943 anomalies de déclaration amont (documentées) |

## Installation

Prérequis : Python 3.10+, Docker Desktop.

```bash
git clone https://github.com/donaldkouassi/pipeline-sante.git
cd pipeline-sante

python3 -m venv .venv && source .venv/bin/activate   # Windows : .venv\Scripts\activate
pip install -r requirements.txt

cp .env.example .env
docker compose up -d          # PostgreSQL sur le port 5434

docker exec -i sante_postgres psql -U data_eng -d sante -c \
  "CREATE SCHEMA IF NOT EXISTS raw; CREATE SCHEMA IF NOT EXISTS staging;
   CREATE SCHEMA IF NOT EXISTS marts;"

python run_pipeline.py        # exécution complète
```

## Utilisation

```bash
python run_pipeline.py                # date du jour
python run_pipeline.py 2026-09-02     # rejoue une date précise (idempotent)
```

Connexion à la base pour explorer :

```bash
psql postgresql://data_eng:data_eng@localhost:5434/sante
```

```sql
SELECT * FROM marts.vue_covid_pays_mois
WHERE nom_pays = 'France' ORDER BY annee_mois DESC LIMIT 12;
```

## Structure

```
pipeline-sante/
├── ingestion/
│   ├── config.py         Configuration (variables d'environnement)
│   ├── extract.py        Source → landing zone, avec empreinte SHA-256
│   └── load_raw.py       Landing zone → couche RAW (idempotent)
├── sql/
│   ├── 01_staging.sql    Dépivotage, typage, incréments quotidiens
│   ├── 02_marts.sql      Schéma en étoile
│   └── 03_tests.sql      Tests de qualité avec niveaux de gravité
├── run_pipeline.py       Orchestrateur
├── docker-compose.yml    PostgreSQL 16
└── requirements.txt
```

## Suites prévues

- Migration des transformations vers **dbt** (tests déclaratifs, lignage, documentation)
- Orchestration par un DAG **Airflow** (planification, reprise, alertes)
- Chargement **incrémental** par date plutôt que rechargement complet
- Déploiement sur un entrepôt cloud (BigQuery ou Snowflake)

---

**Source des données** : [JHU CSSE COVID-19 Data Repository](https://github.com/CSSEGISandData/COVID-19) (licence : usage éducatif et de recherche).
