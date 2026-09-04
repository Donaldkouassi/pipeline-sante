-- Table de faits. Grain : pays x territoire x jour.
-- Les métriques partagent ce grain : elles deviennent des colonnes.

select
    p.id_pays,
    coalesce(s.territoire, 'National') as territoire,
    s.date_observation                 as date_jour,

    sum(s.valeur_journaliere) filter (where s.metrique = 'confirmed') as cas_jour,
    sum(s.valeur_journaliere) filter (where s.metrique = 'deaths')    as deces_jour,
    sum(s.valeur_cumulee)     filter (where s.metrique = 'confirmed') as cas_cumules,
    sum(s.valeur_cumulee)     filter (where s.metrique = 'deaths')    as deces_cumules,

    -- On signale l'anomalie de la source, on ne la masque pas.
    bool_or(s.valeur_journaliere < 0) as a_correction_negative

from {{ ref('stg_covid') }} as s
join {{ ref('dim_pays') }}  as p on p.nom_pays = s.pays_source
group by p.id_pays, coalesce(s.territoire, 'National'), s.date_observation
