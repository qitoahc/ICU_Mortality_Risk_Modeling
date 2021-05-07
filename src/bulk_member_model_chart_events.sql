WITH pvt AS (SELECT ie.subject_id, ie.hadm_id, ie.icustay_id, ce.charttime::date as chartdate, ie.intime 
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
  LEFT JOIN admissions ad
    ON ie.subject_id = ad.subject_id
    AND ie.hadm_id = ad.hadm_id
  LEFT JOIN chartevents ce
    ON ce.subject_id = ie.subject_id 
    AND ce.hadm_id = ie.hadm_id
    and ce.icustay_id = ie.icustay_id 
    AND ce.charttime between ie.intime AND ie.outtime 
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
),
day_max AS (
select pvt.subject_id, pvt.hadm_id, pvt.icustay_id, pvt.label, pvt.chartdate, ROUND(MAX(pvt.valuenum)::numeric,2) as valuenum
from pvt
group by pvt.subject_id, pvt.hadm_id, pvt.icustay_id, pvt.label, pvt.chartdate
)
SELECT dm.subject_id, dm.hadm_id, dm.icustay_id, dm.chartdate
  , max(case when label = 'TEMP' then valuenum else null end) as temperature
  , max(case when label = 'HR' then valuenum else null end) as heartrate
  , max(case when label = 'SYSBP' then valuenum else null end) as systolic_bp
  , max(case when label = 'MAP' then valuenum else null end) as mean_arterial_pressure
FROM day_max dm
group by dm.subject_id, dm.hadm_id, dm.icustay_id, dm.chartdate
ORDER BY dm.subject_id, dm.hadm_id;