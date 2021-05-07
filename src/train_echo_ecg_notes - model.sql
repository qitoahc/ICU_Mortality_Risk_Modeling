WITH ldt as (select ie.subject_id, ie.hadm_id, ie.icustay_id 
	, case
		when pat.dod is not null and extract(epoch from (pat.dod - ie.intime))/86400 >= 4 and extract(epoch from (pat.dod - ie.outtime))/86400 <= 4 then (pat.dod - interval '4 DAYS')
		when pat.dod is not null and extract(epoch from (ie.outtime - ie.intime))/86400 >= 4 and extract(epoch from (pat.dod - ie.outtime))/86400 > 4 then (ie.outtime - interval '4 DAYS') 
		when pat.dod is not null and extract(epoch from (pat.dod - ie.intime))/86400 < 4 then ie.intime 
		when pat.dod is null and extract(epoch from (ie.outtime - ie.intime))/86400 >=4 then (ie.outtime - interval '4 DAYS')
		else ie.intime end as labdate
from icustays ie
inner join patients pat on pat.subject_id = ie.subject_id
),
pvt AS (SELECT ie.subject_id, ie.hadm_id, ie.icustay_id, ne.charttime, ie.intime 
  -- here we assign labels to NOTE Categories
  -- this also fuses together multiple Note Categories containing data of a roughly similar nature
  , CASE
        when ne.category = 'ECHO' then 'ECHO_ECG'
        when ne.category = 'ECG' then 'ECHO_ECG'
      ELSE null
      END AS label
  , ne."text" as txt 
  FROM icustays ie
  JOIN ldt 
  	on ldt.subject_id = ie.subject_id
  	and ldt.hadm_id = ie.hadm_id 
  	and ldt.icustay_id = ie.icustay_id 
  LEFT JOIN noteevents ne
    ON ne.subject_id = ie.subject_id 
    AND ne.hadm_id = ie.hadm_id
    AND ne.chartdate between (ldt.labdate - interval '12' hour) AND (ldt.labdate + interval '12' hour)
    AND ne.category IN
    (
      'ECG', --ECG read notes
      'ECHO' --ECHO read notes
    )
    AND ne.iserror isnull 
    LEFT JOIN admissions ad
    ON ie.subject_id = ad.subject_id
    AND ie.hadm_id = ad.hadm_id
    inner join cohort co on co.hadm_id = ie.hadm_id and co.icustay_id = ie.icustay_id
)
SELECT pvt.subject_id, pvt.hadm_id, pvt.icustay_id
  , case when pvt.label = 'ECHO_ECG' then pvt.txt else null end as ECHO_ECG
FROM pvt
ORDER BY pvt.subject_id, pvt.hadm_id, pvt.icustay_id;