with all_pts as (
select c.hadm_id, c.subject_id, c.icustay_id from cohort c
union
select ho.hadm_id, ho.subject_id, ho.icustay_id from hold_out ho
)
select adm.subject_id, adm.hadm_id, icu.icustay_id, icu.intime::date, icu.outtime::date 
	, case
	  when DATE_PART('years',AGE(admittime,dob)) + ROUND((DATE_PART('months', AGE(admittime,dob)) / 12.0)::numeric ,2) >= 90 then 91.4
	  else DATE_PART('years',AGE(admittime,dob)) + ROUND((DATE_PART('months', AGE(admittime,dob)) / 12.0)::numeric ,2) end as age_	
    , case 
	  when gender = 'M' then 1 else 0 end as gender
	, DATE_PART('months',admittime) as admit_time_m
	, admission_type
	, first_careunit
	, insurance 
	, case 
	  when religion = 'CHRISTIAN SCIENTIST' or religion like 'JEHOVA%' then 'RELIGIOUS_NO_MED'
	  when religion = 'NOT SPECIFIED' or religion isnull or religion = 'UNOBTAINABLE' then 'RELIGIOUS_NOT_SPEC'
	  else 'RELIGIOUS' end as relig
	, case
	  when marital_status = 'MARRIED' or marital_status = 'LIFE PARTNER' then 'PARTNERED'
	  when marital_status = 'SINGLE' then 'SINGLE'
	  when marital_status = 'WIDOWED' then 'WIDOWED'
	  else 'OTHER' end as marital
	, readmit_thirty
	, case 
		when diagnosis like '%CIRR%' then 1 else 0 end as cirrhosis
	, case
		when diagnosis like '%HIV%' then 1 else 0 end as hiv
	, case
		when diagnosis like '%IMMUN%' then 1 else 0 end as immuno_def
	, case
		when diagnosis like '%HEPATIC FAILURE%' then 1 else 0 end as hep_fail
	, case
		when diagnosis like '%LEUKEMIA%' or diagnosis like '%LYMPHOMA%' or diagnosis like '%MYELOMA%' then 1 else 0 end as blood_cncr
	, case
		when diagnosis like '%METAS%' then 1 else 0 end as metastatic_cncr
	, case 
	  when DATE_PART('days', dod - dischtime) < 4 then 1
	  else 0 end as death_4_days
from admissions adm
join patients pat
on pat.subject_id = adm.subject_id
join icustays icu 
on icu.hadm_id = adm.hadm_id
join all_pts ap
on adm.subject_id = ap.subject_id and adm.hadm_id = ap.hadm_id and icu.icustay_id = ap.icustay_id
join cohort c
on c.icustay_id = icu.icustay_id 
;





