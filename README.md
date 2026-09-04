# Pipeline de données santé publique — COVID-19

Pipeline ELT complète : ingestion d'une source publique, entreposage en couches,
modélisation en schéma en étoile, tests de qualité automatisés et documentation
générée.

**Stack** : Python · PostgreSQL · dbt · Docker · SQL analytique

---

## Le problème

Les séries temporelles COVID-19 de Johns Hopkins (CSSE) sont publiées dans un
format inexploitable en l'état :

| Défaut de la source | Conséquence |
|---|---|
| 1 143 colonnes de dates | Format large, impossible à agréger en SQL |
| Valeurs cumulées depuis 2020 | Mesure semi-additive : `SUM` dans le temps donne un résultat 400× trop grand |
| Grain incohérent (la France sur 12 lignes) | Double comptage ou perte de territoires |
| Corrections rétroactives | 362 incréments négatifs |

## L'architecture

```
Source (GitHub CSSE)
   │
   ├─ 1. EXTRACTION ──► data/raw/<date>/*.csv + manifeste SHA-256
   │                    copie fidèle, horodatée, traçable
   │
   ├─ 2. RAW ─────────► raw.covid_landing (JSONB)
   │                    aucun nettoyage — filet de sécurité
   │
   └─ 3. dbt build ───► staging.stg_covid          (973 836 lignes)
                        dépivotage · typage · cumul → incrément quotidien
                            │
                        marts.dim_pays · marts.dim_date
                        marts.fait_covid_journalier  (331 470 lignes)
                        marts.vue_covid_pays_mois
                            │
                        17 tests déclaratifs + 3 tests métier
```

L'ordre d'exécution n'est pas écrit : dbt le déduit des références entre modèles.

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

**Deux niveaux de gravité des tests.** Les tests structurels bloquent la
pipeline. Les anomalies légitimes de la source — la Chine a publié 59 895 décès
le 15/01/2023 avec 0 cas déclaré — émettent un avertissement. Un test qui bloque
à tort finit désactivé par l'équipe, et n'est plus écouté le jour où il détecte
un vrai problème.

**Deux implémentations de la même logique.** Les transformations existent en SQL
brut ordonné à la main (`sql/`) et en modèles dbt (`dbt_sante/`). La première est
conservée délibérément : elle documente ce que dbt automatise.

## Tests de qualité

| Test | Type | Sévérité |
|---|---|---|
| Unicité du grain pays × territoire × jour | singulier | error |
| Réconciliation somme des incréments / cumul source | singulier | error |
| Intégrité référentielle vers `dim_pays` et `dim_date` | générique | error |
| Unicité et non-nullité des clés de dimension | générique | error |
| Valeurs acceptées pour `metrique` | générique | error |
| Décès supérieurs aux cas le même jour | singulier | **warn** |

Résultat de la dernière exécution : `PASS=21 WARN=1 ERROR=0`.

Le test de réconciliation est le plus important : il vérifie que la somme de nos
incréments quotidiens retombe exactement sur le cumul publié par la source, pour
les 201 pays. C'est la preuve que le calcul de différence est juste.

## Installation

Prérequis : Python 3.10+, Docker Desktop.

```bash
git clone https://github.com/Donaldkouassi/pipeline-sante.git
cd pipeline-sante

python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
docker compose up -d

docker exec -i sante_postgres psql -U data_eng -d sante -c \
  "CREATE SCHEMA IF NOT EXISTS raw; CREATE SCHEMA IF NOT EXISTS staging;
   CREATE SCHEMA IF NOT EXISTS marts;"

python run_pipeline.py 2026-09-02
```

## Utilisation

```bash
python run_pipeline.py                      # date du jour, transformations dbt
python run_pipeline.py 2026-09-02           # rejoue une date précise (idempotent)
python run_pipeline.py 2026-09-02 --sql     # version SQL brut, sans dbt
```

Documentation et graphe de lignage :

```bash
cd dbt_sante
dbt docs generate --profiles-dir . --vars '{date_ingestion: "2026-09-02"}'
dbt docs serve --profiles-dir . --port 8081
```

Explorer les résultats :

```sql
SELECT * FROM marts.vue_covid_pays_mois
WHERE nom_pays = 'France' ORDER BY annee_mois DESC LIMIT 12;
```

## Structure

```
pipeline-sante/
├── ingestion/
│   ├── config.py              Configuration par variables d'environnement
│   ├── extract.py             Source → landing zone, empreinte SHA-256
│   └── load_raw.py            Landing zone → couche RAW (idempotent)
├── dbt_sante/
│   ├── models/staging/        Source déclarée, dépivotage, incréments
│   ├── models/marts/          Dimensions, table de faits, vue agrégée
│   ├── tests/                 Tests métier singuliers
│   └── macros/                Résolution des noms de schéma
├── sql/                       Version d'origine en SQL brut (référence)
├── run_pipeline.py            Orchestrateur
├── docker-compose.yml         PostgreSQL 16
└── requirements.txt
```

## Suites prévues

- Orchestration par un DAG **Airflow** (planification, reprise, alertes)
- Chargement **incrémental** par date plutôt que rechargement complet
- Déploiement sur un entrepôt cloud (BigQuery ou Snowflake) — les modèles dbt
  s'y exécutent sans modification, seul le profil de connexion change

---

**Source des données** : [JHU CSSE COVID-19 Data Repository](https://github.com/CSSEGISandData/COVID-19) (licence : usage éducatif et de recherche).
