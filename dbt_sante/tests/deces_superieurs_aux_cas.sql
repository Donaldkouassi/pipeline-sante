{{ config(severity='warn') }}

-- Anomalie de DÉCLARATION, pas de traitement : la Chine a publié 59 895 décès
-- le 15/01/2023 avec 0 cas déclaré. On alerte sans bloquer la pipeline.
-- Un test qui bloque à tort finit désactivé par l'équipe.
select id_pays, territoire, date_jour, cas_jour, deces_jour
from {{ ref('fait_covid_journalier') }}
where deces_jour > cas_jour and cas_jour >= 0
