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
pvt AS (SELECT ie.subject_id, ie.hadm_id, ie.icustay_id, ce.charttime, ie.intime 
  -- here we assign labels to ITEMIDs
  -- this also fuses together multiple ITEMIDs containing the same data
  , CASE
        when ce.itemid = 223761 then 'TEMP'
        when ce.itemid = 678 then 'TEMP'
        when ce.itemid = 223762 then 'TEMP'
        when ce.itemid = 676 then 'TEMP'
        when ce.itemid = 211 then 'HR'
        when ce.itemid = 220045 then 'HR'
        when ce.itemid = 220179 then 'SYSBP'
        when ce.itemid = 220052 then 'MAP'
    ELSE null
    END AS label
  , -- add in some sanity checks on the values
    -- the where clause below requires all valuenum to be > 0, 
    -- so these are only upper limit checks
    CASE
      when ce.itemid = 223761 and ce.valuenum >=    120 then null -- deg F 'TEMP'
      when ce.itemid = 678 and ce.valuenum >= 120 then null -- deg F 'TEMP'
      when ce.itemid = 223762 and ce.valuenum >=   50 then null -- deg C 'TEMP'
      when ce.itemid = 676 and ce.valuenum >=   50 then null -- deg C 'TEMP'
      when ce.itemid in (223761, 678) then (valuenum - 32) / 1.8 -- convert F to C
  	  when ce.itemid = 211 and ce.valuenum > 500 then null -- 'HR'
	  when ce.itemid = 220045 and ce.valuenum > 500 then null -- 'HR'
	  when ce.itemid = 220179 and ce.valuenum > 500 then null -- 'Systolic BP'
	  when ce.itemid = 220052 and ce.valuenum > 500 then null -- 'MAP'      
    ELSE ce.valuenum
    END AS valuenum
  FROM icustays ie
  JOIN ldt 
  	on ldt.subject_id = ie.subject_id
  	and ldt.hadm_id = ie.hadm_id 
  	and ldt.icustay_id = ie.icustay_id 
  LEFT JOIN chartevents ce
    ON ce.subject_id = ie.subject_id 
    AND ce.hadm_id = ie.hadm_id
    AND ce.charttime between (ldt.labdate - interval '12' hour) AND (ldt.labdate + interval '12' hour)
    AND ce.itemid IN
    (
      223761, -- Temperature F
      678, -- Temperature F
      223762, -- Temperature C
      676, -- Temperature C
      211, -- HR, bpm
      220045, -- HR, bpm
      220179, -- Systolic BP, mmHg
      220052 -- Mean Arterial Pressure, mmHg
    )
    AND ce.valuenum IS NOT null 
    AND ce.valuenum > 0
    LEFT JOIN admissions ad
    ON ie.subject_id = ad.subject_id
    AND ie.hadm_id = ad.hadm_id
    inner join hold_out ho on ho.hadm_id = ie.hadm_id and ho.icustay_id = ie.icustay_id  
),
day_max AS (
select pvt.subject_id, pvt.hadm_id, pvt.label, ROUND(MAX(pvt.valuenum)::numeric,2) as valuenum
from pvt
group by pvt.subject_id, pvt.hadm_id, pvt.label
)
SELECT dm.subject_id, dm.hadm_id
  , max(case when label = 'TEMP' then valuenum else null end) as temperature
  , max(case when label = 'HR' then valuenum else null end) as heartrate
  , max(case when label = 'SYSBP' then valuenum else null end) as systolic_bp
  , max(case when label = 'MAP' then valuenum else null end) as mean_arterial_pressure
FROM day_max dm
group by dm.subject_id, dm.hadm_id
ORDER BY dm.subject_id, dm.hadm_id;