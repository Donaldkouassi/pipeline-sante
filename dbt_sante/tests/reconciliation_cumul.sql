-- LE test qui prouve que le calcul d'incréments est juste :
-- la somme de nos incréments doit retomber sur le cumul officiel
-- du dernier jour, pour chaque série.
with calcule as (
    select id_pays, territoire, sum(cas_jour) as somme_increments
    from {{ ref('fait_covid_journalier') }}
    group by id_pays, territoire
),

officiel as (
    select distinct on (id_pays, territoire)
           id_pays, territoire, cas_cumules
    from {{ ref('fait_covid_journalier') }}
    order by id_pays, territoire, date_jour desc
)

select c.id_pays, c.territoire, c.somme_increments, o.cas_cumules
from calcule c
join officiel o using (id_pays, territoire)
where c.somme_increments is distinct from o.cas_cumules
