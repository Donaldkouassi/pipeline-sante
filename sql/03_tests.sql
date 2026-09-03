-- ====================================================================
-- TESTS DE QUALITÉ — chaque requête doit renvoyer ZÉRO ligne.
--   @severite: erreur        -> le pipeline s'arrête
--   @severite: avertissement -> on journalise et on continue
-- ====================================================================

-- TEST 1 — Unicité du grain.
-- @severite: erreur
SELECT 'unicite_grain' AS test, id_pays, territoire, date_jour, count(*) AS n
FROM marts.fait_covid_journalier
GROUP BY id_pays, territoire, date_jour
HAVING count(*) > 1;

-- TEST 2 — Intégrité référentielle : aucun fait orphelin.
-- @severite: erreur
SELECT 'fait_orphelin' AS test, f.id_pays
FROM marts.fait_covid_journalier f
LEFT JOIN marts.dim_pays p USING (id_pays)
WHERE p.id_pays IS NULL;

-- TEST 3 — Complétude : aucune date manquante sur la période.
-- @severite: erreur
SELECT 'date_manquante' AS test, d.date_jour
FROM marts.dim_date d
LEFT JOIN (SELECT DISTINCT date_jour FROM marts.fait_covid_journalier) f
       ON f.date_jour = d.date_jour
WHERE f.date_jour IS NULL;

-- TEST 4 — Réconciliation avec la source.
-- @severite: erreur
-- La somme de nos incréments doit retomber sur le cumul officiel du
-- dernier jour. C'est LE test qui prouve que le calcul de différence
-- est juste — et la raison pour laquelle on garde la colonne cumulée.
WITH calcule AS (
    SELECT id_pays, territoire, sum(cas_jour) AS somme_increments
    FROM marts.fait_covid_journalier
    GROUP BY id_pays, territoire
),
officiel AS (
    SELECT DISTINCT ON (id_pays, territoire)
           id_pays, territoire, cas_cumules
    FROM marts.fait_covid_journalier
    ORDER BY id_pays, territoire, date_jour DESC
)
SELECT 'reconciliation' AS test, c.id_pays, c.territoire,
       c.somme_increments, o.cas_cumules
FROM calcule c
JOIN officiel o USING (id_pays, territoire)
WHERE c.somme_increments IS DISTINCT FROM o.cas_cumules;

-- TEST 5 — Plage de valeurs plausible.
-- @severite: avertissement
-- Des décès supérieurs aux cas le même jour, c'est suspect mais pas
-- impossible : la Chine a publié 59 895 décès le 15/01/2023 avec 0 cas
-- déclaré (régularisation rétroactive). Artefact de déclaration amont,
-- pas erreur de traitement. On alerte sans bloquer.
SELECT 'deces_superieurs_aux_cas' AS test, id_pays, territoire, date_jour,
       cas_jour, deces_jour
FROM marts.fait_covid_journalier
WHERE deces_jour > cas_jour AND cas_jour >= 0;