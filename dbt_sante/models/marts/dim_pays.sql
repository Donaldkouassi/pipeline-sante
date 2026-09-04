-- Dimension pays. Clé de substitution générée : indépendante du nom source,
-- donc un renommage amont ne casse pas les historiques.

select
    row_number() over (order by pays_source)  as id_pays,
    pays_source                               as nom_pays,
    count(distinct coalesce(territoire, '~')) as nb_territoires,
    round(avg(latitude),  4)                  as latitude_moyenne,
    round(avg(longitude), 4)                  as longitude_moyenne
from {{ ref('stg_covid') }}
group by pays_source
