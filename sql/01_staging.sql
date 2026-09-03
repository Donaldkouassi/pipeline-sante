-- ====================================================================
-- COUCHE STAGING : rendre la donnée exploitable.
-- Grain de sortie : pays x territoire x date x métrique (le plus fin)
-- ====================================================================

DROP TABLE IF EXISTS staging.covid_long CASCADE;

CREATE TABLE staging.covid_long AS
WITH depivote AS (
    -- jsonb_each_text transforme chaque paire clé/valeur du JSON en ligne.
    -- C'est notre "unpivot" : 1147 colonnes deviennent 1147 lignes.
    SELECT
        l.metrique,
        l.charge_utile ->> 'Country/Region'             AS pays_source,
        NULLIF(l.charge_utile ->> 'Province/State', '') AS territoire,
        NULLIF(l.charge_utile ->> 'Lat',  '')::NUMERIC  AS latitude,
        NULLIF(l.charge_utile ->> 'Long', '')::NUMERIC  AS longitude,
        paire.key                                       AS cle_date,
        paire.value                                     AS valeur_texte
    FROM raw.covid_landing AS l
    CROSS JOIN LATERAL jsonb_each_text(l.charge_utile) AS paire(key, value)
    WHERE l.date_ingestion = %(date_ingestion)s
      -- Une regex, pas une liste en dur : si la source ajoute une colonne
      -- de date demain, ça marche encore.
      AND paire.key ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2}$'
),
type AS (
    SELECT
        metrique, pays_source, territoire, latitude, longitude,
        TO_DATE(cle_date, 'MM/DD/YY')       AS date_observation,
        NULLIF(valeur_texte, '')::BIGINT    AS valeur_cumulee
    FROM depivote
)
SELECT
    metrique, pays_source, territoire, latitude, longitude,
    date_observation,
    valeur_cumulee,
    -- Incrément du jour = cumul d'aujourd'hui - cumul de la veille,
    -- calculé SÉPARÉMENT pour chaque série.
    valeur_cumulee - LAG(valeur_cumulee, 1, 0::BIGINT) OVER (
        PARTITION BY metrique, pays_source, COALESCE(territoire, '~')
        ORDER BY date_observation
    ) AS valeur_journaliere
FROM type;

CREATE INDEX idx_stg_serie
    ON staging.covid_long (metrique, pays_source, date_observation);