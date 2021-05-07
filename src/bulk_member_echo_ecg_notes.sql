with pvt AS (SELECT ie.subject_id, ie.hadm_id, ie.icustay_id, ne.chartdate::date as chartdate, ie.intime 
  -- here we assign labels to NOTE Categories
  -- this also fuses together multiple Note Categories containing data of a roughly similar nature
  , CASE
        when ne.category = 'ECHO' then 'ECHO_ECG'
        when ne.category = 'ECG' then 'ECHO_ECG'
      ELSE null
      END AS label
  , ne."text" as txt 
  FROM icustays ie
	LEFT JOIN admissions ad
    ON ie.subject_id = ad.subject_id
    AND ie.hadm_id = ad.hadm_id
  	LEFT JOIN noteevents ne
    ON ne.subject_id = ie.subject_id 
    AND ne.hadm_id = ie.hadm_id
    AND ne.chartdate between ie.intime and ie.outtime 
    AND ne.category IN
    (
      'ECG', --ECG read notes
      'ECHO' --ECHO read notes
    )
    AND ne.iserror isnull
)
SELECT pvt.subject_id, pvt.hadm_id, pvt.icustay_id, pvt.chartdate
  , case when pvt.label = 'ECHO_ECG' then pvt.txt else null end as ECHO_ECG
FROM pvt
ORDER BY pvt.subject_id, pvt.hadm_id, chartdate;