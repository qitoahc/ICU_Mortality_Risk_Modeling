	with ranked_admits as (
		SELECT adm.subject_id, adm.hadm_id
			, adm.admittime 
			, adm.dischtime 
			, RANK() OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime DESC) AS adm_id_order
		FROM admissions adm
		INNER JOIN patients pat ON adm.subject_id = pat.subject_id
		)
	update admissions
	set readmit_thirty = case when DATE_PART('days',ra.dischtime - ra2.admittime) <=30 then 1 else 0 end
	from ranked_admits ra
		left join ranked_admits ra2 on ra.subject_id = ra2.subject_id and ra2.adm_id_order = ra.adm_id_order + 1
	where admissions.hadm_id = ra.hadm_id;