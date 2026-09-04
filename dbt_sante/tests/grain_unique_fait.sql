-- Unicité du grain : pays x territoire x jour.
-- dbt ne crée pas de clé primaire — la garantie passe par ce test.
select id_pays, territoire, date_jour, count(*) as n
from {{ ref('fait_covid_journalier') }}
group by id_pays, territoire, date_jour
having count(*) > 1
