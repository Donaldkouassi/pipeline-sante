-- Dépivotage, typage, et passage du cumul à l'incrément quotidien.
-- Grain : pays x territoire x date x métrique (le plus fin disponible).

with depivote as (

    select
        l.metrique,
        l.charge_utile ->> 'Country/Region'             as pays_source,
        nullif(l.charge_utile ->> 'Province/State', '') as territoire,
        nullif(l.charge_utile ->> 'Lat',  '')::numeric  as latitude,
        nullif(l.charge_utile ->> 'Long', '')::numeric  as longitude,
        paire.key                                       as cle_date,
        paire.value                                     as valeur_texte
    from {{ source('raw', 'covid_landing') }} as l
    cross join lateral jsonb_each_text(l.charge_utile) as paire(key, value)
    where l.date_ingestion = '{{ var("date_ingestion") }}'::date
      and paire.key ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2}$'

),

type as (

    select
        metrique,
        pays_source,
        territoire,
        latitude,
        longitude,
        to_date(cle_date, 'MM/DD/YY')    as date_observation,
        nullif(valeur_texte, '')::bigint as valeur_cumulee
    from depivote

)

select
    metrique,
    pays_source,
    territoire,
    latitude,
    longitude,
    date_observation,
    valeur_cumulee,
    valeur_cumulee - lag(valeur_cumulee, 1, 0::bigint) over (
        partition by metrique, pays_source, coalesce(territoire, '~')
        order by date_observation
    ) as valeur_journaliere
from type
