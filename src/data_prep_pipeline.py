from mimic_fxns import connect, insert_data, get_exclusions
import numpy as np
import psycopg2 as psy
from psycopg2 import sql
from sklearn.model_selection import train_test_split
   
def get_exclusions(conn):
    """
    Overview: 
        Returns dataframe of all admissions with indicator columns for the various model exclusions (based on clinical clinical indications and/or data gaps.)
    Parameters:
        conn: 
            active connection to EMR database
    Returns:
        dataframe of all admissions with indicators for exclusion criteria
    """
    query = sql.SQL("""
    select adm.subject_id, adm.hadm_id, icustay_id
    , case 
	  when deathtime < admittime then 1
	  else 0 end as excl_death_prior
	, case 
		when icustay_id is null then 1
	  else 0 end as excl_no_icu
 	, case 
	  when los <= (4.0/24) then 1
	  else 0 end as excl_4hr_stay
    , case
		when date_part('years', AGE(intime,dob)) < 20 then 1
		else 0 end as excl_age
	, case 
    	when adm.diagnosis like '%TRANSPLANT%' then 1
	    else 0 end as excl_transplant
    , case 
    	when adm.diagnosis like '%BURN%' then 1
    	else 0 end as excl_burns
	from admissions adm
	left join icustays icu on adm.hadm_id = icu.hadm_id
	left join patients pat on adm.subject_id = pat.subject_id
    """)
    return pd.read_sql(query, conn)


if __name__ == '__main__':
    conn = connect()
    # Following code pulls out all ICU admissions that do not meet any of the exclusion criteria, splits the data into a train/test and hold-out data set.  Tables in the PostgreSQL DB are then populated with the appropriate identifiers for the admissions allocated to each of the two pools (hold-out vs. test/train)
    admits_excl = get_exclusions(conn)
    cohort = admits_excl.loc[admits_excl[['excl_death_prior','excl_no_icu', 'excl_4hr_stay', 'excl_age', 'excl_transplant', 'excl_burns']].any(axis=1) == False, ['hadm_id', 'subject_id', 'icustay_id']]
    c_train, c_hold_out = train_test_split(cohort, test_size = .4, random_state=18, shuffle=True)
    insert_data(con_details, c_train, 'cohort', conn)
    insert_data(con_details, c_hold_out, 'hold_out', conn)