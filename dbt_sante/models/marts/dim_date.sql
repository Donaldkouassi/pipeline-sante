-- Dimension date construite depuis les bornes réelles des données,
-- et non codées en dur : la table s'adapte si la période change.

with bornes as (
    select min(date_observation) as debut, max(date_observation) as fin
    from {{ ref('stg_covid') }}
),

calendrier as (
    select generate_series(debut, fin, interval '1 day')::date as date_jour
    from bornes
)

select
    date_jour,
    extract(year    from date_jour)::int   as annee,
    extract(month   from date_jour)::int   as mois,
    extract(day     from date_jour)::int   as jour,
    extract(quarter from date_jour)::int   as trimestre,
    extract(isodow  from date_jour)::int   as jour_semaine,
    to_char(date_jour, 'YYYY-MM')          as annee_mois,
    extract(isodow from date_jour) in (6, 7) as est_weekend
from calendrier
