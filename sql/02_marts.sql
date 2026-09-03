-- ====================================================================
-- COUCHE MARTS : le schéma en étoile.
-- Grain de la table de faits : pays x territoire x date
-- ====================================================================

-- ---------- DIMENSION PAYS ----------
DROP TABLE IF EXISTS marts.dim_pays CASCADE;

CREATE TABLE marts.dim_pays AS
SELECT
    -- Clé de substitution : un entier généré, indépendant de la source.
    -- Si l'OMS renomme "Burma" en "Myanmar", la clé ne bouge pas.
    ROW_NUMBER() OVER (ORDER BY pays_source)  AS id_pays,
    pays_source                               AS nom_pays,
    count(DISTINCT COALESCE(territoire, '~')) AS nb_territoires,
    round(avg(latitude),  4)                  AS latitude_moyenne,
    round(avg(longitude), 4)                  AS longitude_moyenne
FROM staging.covid_long
GROUP BY pays_source;

ALTER TABLE marts.dim_pays ADD PRIMARY KEY (id_pays);
CREATE UNIQUE INDEX idx_dim_pays_nom ON marts.dim_pays (nom_pays);

-- ---------- DIMENSION DATE ----------
-- Une table de dates explicite est un réflexe d'entrepôt : elle permet
-- d'analyser par trimestre ou jour de semaine, et de repérer les trous.
DROP TABLE IF EXISTS marts.dim_date CASCADE;

CREATE TABLE marts.dim_date AS
SELECT
    d::DATE                          AS date_jour,
    EXTRACT(YEAR    FROM d)::INT     AS annee,
    EXTRACT(MONTH   FROM d)::INT     AS mois,
    EXTRACT(DAY     FROM d)::INT     AS jour,
    EXTRACT(QUARTER FROM d)::INT     AS trimestre,
    EXTRACT(ISODOW  FROM d)::INT     AS jour_semaine,
    TO_CHAR(d, 'YYYY-MM')            AS annee_mois,
    EXTRACT(ISODOW FROM d) IN (6, 7) AS est_weekend
FROM generate_series(DATE '2020-01-22', DATE '2023-03-09',
                     INTERVAL '1 day') AS d;

ALTER TABLE marts.dim_date ADD PRIMARY KEY (date_jour);

-- ---------- TABLE DE FAITS ----------
DROP TABLE IF EXISTS marts.fait_covid_journalier CASCADE;

CREATE TABLE marts.fait_covid_journalier AS
SELECT
    p.id_pays,
    COALESCE(s.territoire, 'National') AS territoire,
    s.date_observation                 AS date_jour,

    -- Pivot des métriques : même grain, donc colonnes de la même ligne.
    sum(s.valeur_journaliere) FILTER (WHERE s.metrique='confirmed') AS cas_jour,
    sum(s.valeur_journaliere) FILTER (WHERE s.metrique='deaths')    AS deces_jour,
    sum(s.valeur_cumulee)     FILTER (WHERE s.metrique='confirmed') AS cas_cumules,
    sum(s.valeur_cumulee)     FILTER (WHERE s.metrique='deaths')    AS deces_cumules,

    -- Drapeau qualité : on signale l'anomalie, on ne la masque pas.
    bool_or(s.valeur_journaliere < 0) AS a_correction_negative
FROM staging.covid_long AS s
JOIN marts.dim_pays     AS p ON p.nom_pays = s.pays_source
GROUP BY p.id_pays, COALESCE(s.territoire, 'National'), s.date_observation;

-- La clé primaire n'est pas décorative : c'est une garantie d'unicité
-- imposée par la base. Un doublon fera échouer l'insertion.
ALTER TABLE marts.fait_covid_journalier
    ADD PRIMARY KEY (id_pays, territoire, date_jour);

CREATE INDEX idx_fait_date ON marts.fait_covid_journalier (date_jour);

-- ---------- VUE AGRÉGÉE AU NIVEAU PAYS ----------
-- On agrège vers le haut à la lecture. Le détail territorial reste là.
CREATE OR REPLACE VIEW marts.vue_covid_pays_mois AS
SELECT
    p.nom_pays,
    d.annee_mois,
    sum(f.cas_jour)   AS cas_du_mois,
    sum(f.deces_jour) AS deces_du_mois
FROM marts.fait_covid_journalier AS f
JOIN marts.dim_pays AS p USING (id_pays)
JOIN marts.dim_date AS d ON d.date_jour = f.date_jour
GROUP BY p.nom_pays, d.annee_mois;