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
pvt AS (SELECT ie.subject_id, ie.hadm_id, ie.icustay_id, le.charttime, ie.intime 
  -- here we assign labels to ITEMIDs
  -- this also fuses together multiple ITEMIDs containing the same data
  , CASE
        when le.itemid = 50868 then 'ANION GAP'
        when le.itemid = 50862 then 'ALBUMIN'
        when le.itemid = 50885 then 'BILIRUBIN'
        when le.itemid = 50912 then 'CREATININE'
        when itemid = 50809 then 'GLUCOSE'
        when itemid = 50931 then 'GLUCOSE'
        when itemid = 50810 then 'HEMATOCRIT'
        when itemid = 51221 then 'HEMATOCRIT'
        when itemid = 50811 then 'HEMOGLOBIN'
        when itemid = 51222 then 'HEMOGLOBIN'
        when itemid = 50813 then 'LACTATE'
        when itemid = 51265 then 'PLATELET'
        when itemid = 50824 then 'SODIUM'
        when itemid = 50983 then 'SODIUM'
        when itemid = 51006 then 'BUN'
        when itemid = 51300 then 'WBC'
        when itemid = 51301 then 'WBC'
      ELSE null
      END AS label
  , -- add in some sanity checks on the values
    -- the where clause below requires all valuenum to be > 0, 
    -- so these are only upper limit checks
    CASE
      when le.itemid = 50862 and le.valuenum >    10 then null -- g/dL 'ALBUMIN'
      when le.itemid = 50868 and le.valuenum > 10000 then null -- mEq/L 'ANION GAP'
      when le.itemid = 50885 and le.valuenum >   150 then null -- mg/dL 'BILIRUBIN'
      when le.itemid = 50912 and le.valuenum >   150 then null -- mg/dL 'CREATININE'
      when le.itemid = 50809 and le.valuenum > 10000 then null -- mg/dL 'GLUCOSE'
      when le.itemid = 50931 and le.valuenum > 10000 then null -- mg/dL 'GLUCOSE'
      when le.itemid = 50810 and le.valuenum >   100 then null -- % 'HEMATOCRIT'
      when le.itemid = 51221 and le.valuenum >   100 then null -- % 'HEMATOCRIT'
      when le.itemid = 50811 and le.valuenum >    50 then null -- g/dL 'HEMOGLOBIN'
      when le.itemid = 51222 and le.valuenum >    50 then null -- g/dL 'HEMOGLOBIN'
      when le.itemid = 50813 and le.valuenum >    50 then null -- mmol/L 'LACTATE'
      when le.itemid = 51265 and le.valuenum > 10000 then null -- K/uL 'PLATELET'
      when le.itemid = 50824 and le.valuenum >   200 then null -- mEq/L == mmol/L 'SODIUM'
      when le.itemid = 50983 and le.valuenum >   200 then null -- mEq/L == mmol/L 'SODIUM'
      when le.itemid = 51006 and le.valuenum >   300 then null -- 'BUN'
      when le.itemid = 51300 and le.valuenum >  1000 then null -- 'WBC'
      when le.itemid = 51301 and le.valuenum >  1000 then null -- 'WBC'
    ELSE le.valuenum
    END AS valuenum
  FROM icustays ie
  JOIN ldt 
  	on ldt.subject_id = ie.subject_id
  	and ldt.hadm_id = ie.hadm_id 
  	and ldt.icustay_id = ie.icustay_id 
  LEFT JOIN labevents le
    ON le.subject_id = ie.subject_id 
    AND le.hadm_id = ie.hadm_id
    AND le.charttime between (ldt.labdate - interval '12' hour) AND (ldt.labdate + interval '12' hour)
    AND le.itemid IN
    (
      -- comment is: LABEL | CATEGORY | FLUID | NUMBER OF ROWS IN LABEVENTS
      50868, -- ANION GAP | CHEMISTRY | BLOOD | 769895
      50862, -- ALBUMIN | CHEMISTRY | BLOOD | 146697
      50885, -- BILIRUBIN, TOTAL | CHEMISTRY | BLOOD | 238277
      50912, -- CREATININE | CHEMISTRY | BLOOD | 797476
      50931, -- GLUCOSE | CHEMISTRY | BLOOD | 748981
      50809, -- GLUCOSE | BLOOD GAS | BLOOD | 196734
      51221, -- HEMATOCRIT | HEMATOLOGY | BLOOD | 881846
      50810, -- HEMATOCRIT, CALCULATED | BLOOD GAS | BLOOD | 89715
      51222, -- HEMOGLOBIN | HEMATOLOGY | BLOOD | 752523
      50811, -- HEMOGLOBIN | BLOOD GAS | BLOOD | 89712
      50813, -- LACTATE | BLOOD GAS | BLOOD | 187124
      51265, -- PLATELET COUNT | HEMATOLOGY | BLOOD | 778444
      50983, -- SODIUM | CHEMISTRY | BLOOD | 808489
      50824, -- SODIUM, WHOLE BLOOD | BLOOD GAS | BLOOD | 71503
      51006, -- UREA NITROGEN | CHEMISTRY | BLOOD | 791925
      51301, -- WHITE BLOOD CELLS | HEMATOLOGY | BLOOD | 753301
      51300  -- WBC COUNT | HEMATOLOGY | BLOOD | 2371
    )
    AND le.valuenum IS NOT null 
    AND le.valuenum > 0 -- lab values cannot be 0 and cannot be negative
    LEFT JOIN admissions ad
    ON ie.subject_id = ad.subject_id
    AND ie.hadm_id = ad.hadm_id
    inner join cohort co on co.hadm_id = ie.hadm_id and co.icustay_id = ie.icustay_id
),
day_avg AS (
select pvt.subject_id, pvt.hadm_id, pvt.label, ROUND(AVG(pvt.valuenum)::numeric,2) as valuenum
from pvt
group by pvt.subject_id, pvt.hadm_id, pvt.label
)
SELECT da.subject_id, da.hadm_id
  , max(case when label = 'ANION GAP' then valuenum else null end) as ANIONGAP
  , max(case when label = 'ALBUMIN' then valuenum else null end) as ALBUMIN
  , max(case when label = 'BILIRUBIN' then valuenum else null end) as BILIRUBIN
  , max(case when label = 'CREATININE' then valuenum else null end) as CREATININE
  , max(case when label = 'GLUCOSE' then valuenum else null end) as GLUCOSE
  , max(case when label = 'HEMATOCRIT' then valuenum else null end) as HEMATOCRIT
  , max(case when label = 'HEMOGLOBIN' then valuenum else null end) as HEMOGLOBIN
  , max(case when label = 'LACTATE' then valuenum else null end) as LACTATE
  , max(case when label = 'PLATELET' then valuenum else null end) as PLATELET
  , max(case when label = 'SODIUM' then valuenum else null end) as SODIUM
  , max(case when label = 'BUN' then valuenum else null end) as BUN
  , max(case when label = 'WBC' then valuenum else null end) as WBC
FROM day_avg da
group by da.subject_id, da.hadm_id
ORDER BY da.subject_id, da.hadm_id;