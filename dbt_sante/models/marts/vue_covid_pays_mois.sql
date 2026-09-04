{{ config(materialized='view') }}

-- Agrégation au niveau pays, faite À LA LECTURE.
-- Le détail territorial reste disponible dans la table de faits.

select
    p.nom_pays,
    d.annee_mois,
    sum(f.cas_jour)   as cas_du_mois,
    sum(f.deces_jour) as deces_du_mois
from {{ ref('fait_covid_journalier') }} as f
join {{ ref('dim_pays') }} as p using (id_pays)
join {{ ref('dim_date') }} as d on d.date_jour = f.date_jour
group by p.nom_pays, d.annee_mois
