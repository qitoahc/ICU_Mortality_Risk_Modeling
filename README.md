# Predictive Modeling of ICU Mortality

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/intheroom.PNG)

# Table of Contents
1. [Intro and Motivation](#intro-and-motivation)
2. [Data Sourcing and Storage](#data-sourcing-and-storage)
3. [Featurization and Analysis](#featurization-and-analysis)
4. [Model Development and Implementation](#model-development-and-implementation)   
   
## **Intro and Motivation**: 
As someone who has worked in Healthcare for years, I've seen first hand the complexities involved with delivering coordinated, timely, and personalized care to patients in need.  Whether it's the legion of constantly rotating clincal teams and handoffs, competing demands for clinical focus, technology dedicated to billing over patient care, or even the incomprehensible complexities of the networks and products offered to consumers...the industry has no end of complications.  I've also seen a fair share of data science related initiatives fail to deliver value because of chasms between the industry expertise and technical teams.  Standing out amongst all of this is the growing opportunity for applying data science directly to the processes of patient care.  Many healthcare organizations have moved past their multi-year electronic medical record (EMR) implementations, implemented foundational data architectures, and are actively engaging in reimbursement models that incentivize optimizing the management of total costs of care (vs. legacy models where more care equals more money).  Two particular trends of interest are that of the growing focus on end-of-life (including but not limited to palliative) care and penalties for readmissions and/or poor patient outcomes.  

For these reasons, I chose to develop a project to build out a predicive model for Intensive Care Unit (ICU) patient mortality that could be applied operationally to improve visibility of patient status dynamically, based on EMR data.  As it relates to provider organizations and patients, having this kind of information visible and regularly updated would add value in that it would help clinical teams focus their limited resources on the patients most in need where intervention is possible, or help with more timely engagement of families and caregivers in end of life planning.

There is additional opportunity possible here to displace existing models as most that I found in literature appear to be anchored around data captured at the time of admission and/or implemented through proprietary systems requiring concerted effort to implement and sustain at the patient level.

## **Data Sourcing and Storage**:
The data used in this project was sourced from the MIMIC project, which is an openly available dataset administered by the MIT Lab for Computational Physiology associated with ~60,000 intensive care unit admissions. Project site can be found at https://physionet.org/content/mimiciii/1.4/

"MIMIC-III is a large, freely-available database comprising deidentified health-related data associated with over forty thousand patients who stayed in critical care units of the Beth Israel Deaconess Medical Center between 2001 and 2012. The database includes information such as demographics, vital sign measurements made at the bedside (~1 data point per hour), laboratory test results, procedures, medications, caregiver notes, imaging reports, and mortality (including post-hospital discharge).

MIMIC supports a diverse range of analytic studies spanning epidemiology, clinical decision-rule improvement, and electronic tool development. It is notable for three factors: it is freely available to researchers worldwide; it encompasses a diverse and very large population of ICU patients; and it contains highly granular data, including vital signs, laboratory results, and medications." [1] 

For this project, the data was downloaded and the provided scripts were used to construct a locally hosted instance of the data in a PostgreSQL Database.  This is an expansive data set, with complications added through the efforts to maintain HIPAA compliance and adequately de-identify the data. It was also required to complete an online training related to 'Data or Specimens Only Research' in order to gain access to the data.  For these purposes, sample data will not be posted here and the reader is recommended to follow the link above to the main MIMIC site for further details. 

Some of the complications present that were critical to this project were the following:
1. Patients over 89 years of age at the time of admission had their date of birth changed to 200 years before their first admission date
2. Dates of service were modified to be in the future and spread over ~100 year range (vs the actual 10 years of data present), while 'seasonality' was preserved
3. Chart event data (labs, biometrics, etc.) only present for ICU portion of admissions
4. Large gaps in lab data across a patient's admission

## **Featurization and Analysis**:
Once everything was cleaned and loaded initial exploratory analysis was performed in PostgreSQL to assess and confirm the presence of the age adjustments, future-dated and spread admission dates, and explore length of stay distributions.  Additionally, based on a review of existing literature, exclusions were defined as:
1. patients younger than 20
2. hospital admissions with no ICU admissions
3. short stays (ICU length of stay <= 4 hours)
4. Burn and transplant patients (identified through parsing of admitting diagnosis field, historically excluded due to unique dynamics of these patients)
5. Admissions with dates of death prior to the admission date (these appear to be tied to organ transplant cases and reflect the donor admission)

The SQL query used for managing the exclusions can be found within the data prep pipeline code ![here](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/src/data_prep_pipeline.py) 

Next, a cohort and hold-out table was created in the database and the admission records were processed through python to exclude those admissions meeting exclusion criteria, splitting the remaining data into training and hold-out sets, and then updating the appropriate database tables with the necessary patient, admission, and icu stay id's for future reference.  Because of the large volume of data and desire to have adequate testing data, a 60/40 split was set between train/test and hold-out.  All future exploratory analysis, featurization development, model development, and model evaluation was completed using the train/test set of data to ensure no leakage or unncessary bias crept into the development.  The code for creating the split and populating the tables is here ![here](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/src/data_prep_pipeline.py) and it leverages helper functions from ![here](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/src/mimic_fxns.py).  It also bears mentioning that for the purposes of this project and it's outcomes (mortality prediction 'in real time' during an admission) the data reflecting billing and coding details were ignored as they would not be present in an EMR for a given patient during their admission.

Based on discussions with a clinical leader from a prominent NW academic medical center, the target timeframe for the project was set at predicting mortality rates within 4 days from a given time snapshot.  This timeframe was established as it was deemed to be both relevant from a care pathway and intervention perspective,  as well as being a longer time horizon than existing 'manual' clinical assessment would be accurate within.  Operationally, this also would enable the model to be fit such that its predictions would not be limited to the date of discharge as the terminal, but upto 3 days post-discharge.  This scope adds value as it increases the relevance of the predictions for discharge planning in addition to the value points discussed previously.

The following graph was used to assess that there was sufficient data present to support the use of the 4 day in advance timeframe.  

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/icu_hosp_los.png)


The next step taken was to transform the calculated ages to decades.  This was done after replacing the ages >200 years old with the median value of 91.4 that is published regarding the data prior to de-identification process.  The mortality rates (in-hosptial and within 4 days of discharge) by age decade were compared in the graph below, which shows there does appear to be a relationship between mortality and age and that this treatment can adequately handle the modified ages for people over 89. 

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/mortality_rate_by_age_in_decades.png)

The next data element that was explored was that of the date of admission.  As stated above, because of the modifications made to the dates, only hte month of the year was leverageable.  The graph below shows the mortality rates by admission month.

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/mortality_rate_by_month.png)

The below graph shows some iterations of trig functions for the use of transforming the date information, with the product of sin and cos being the transformation that was used.

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/trig_transform_candidates_month.png)

Lab values were the next data element to consider.  What was found in the literature seemed to indicate that most of the existing work on models like this, have a 'stepwise' value mapping assigned to each lab that attempts to 'weight' the data is extreme over the data that is in the normal values.  In order to improve the scalability of this model with the end goal of 'operationalization, a simple algorithm was developed to add a 2nd-order fit to each of the lab categories such that the further from normal a given lab result is, the greater weight it gets while each label is tailored to its own normal range.  An example plot of this kind of transformation applied over a range of lab values is below.  The ranges used for 'normal' ranges came from the American College of Physicians and is available ![here](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/reference/ACP%20normal-lab-values.pdf)

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/lab_transform.PNG)

Additional featurization and/or transformations that were used were:
1. Creation of a re-admission flag on admissions that represented a readmission to the hospital within 30 days of a prior readmission
   a. ![Readmit Flag SQL](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/src/readmission_flag_creation.sql)
2. One-Hot Encoding of Marital Status, Regigion, and Insurance coverage
3. Chronic condition flags - identified via parsing admitting diagnosis description field to capture conditions outlined in the literature [2]
   a.  Encoding for each: AIDS, cirrhosis, hepatic failure, immunosupression, lymphoma, leukemia or myeloma, metastatic tumor
   b.  Aggregate chronic condition field with value for the number of chronic conditions flagged
   
## **Model Development and Implementation**:
Ultimately the Logistic Regression model was developed first by building up the feature set used and then adjusting the regularization hyperparameter to land at the final version of the model.  The initial baseline model started with the following features: admission month, gender, admit type (elective, urgent, etc.), first care unit (Critical Care Unit, Intensive Care Unit, etc.), and readmission within 30 days.  Features were then added and the model re-evaluated.  The iterative development was done leveraging 6-fold cross-validation on a 75% split of the test/train data set pulled out at the beginning.  Because of the two-fold use of the model there is critical importance to maximizing the true positives identified while also minimizing the amount of false positives.  Because of this, ROC curves and 'Area Under The Curve' (AUC) were used in the evaluation.  The iterative process and resulting ROC curves are shown below:

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/development_evaluation_iterations.PNG)

After the final version of the model had been developed, it was then trained on the full test/train data set (60% of total data) and evaluated against the accurate labels.  The hold-out data was now brought in and used with the fit model to evaluate it's performance.  As the graph below shows, there's a very similar performance level of the model between the hold-out and train data sets.

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/roc_testtrain_holdout.png)

Given that the performance was acceptable on the hold-out data, the final step was to then demonstrate the operational application of the model.
bulk_member sql are the queries used to pull full member data


by taking a small sample of patients and running the model on each day of their admission to evaluate how the mortality risk evolved and ultimately see where it succeeded or failed.  The graph below shows this application, with the final data point for each member representing the actual correct label.   The circles around the last data points are for emphasis and color coded related to accuracy of prediction.

![alt text](https://public.tableau.com/profile/jesse.southworth#!/vizhome/ICUMortalityDashboard_16195670538950/ICUDashboard)


## **Credits and Resources**:
1. MIMIC-III, a freely accessible critical care database. Johnson AEW, Pollard TJ, Shen L, Lehman L, Feng M, Ghassemi M, Moody B, Szolovits P, Celi LA, and Mark RG. Scientific Data (2016). DOI: 10.1038/sdata.2016.35. Available from: http://www.nature.com/articles/sdata201635
2.  Acute Physiology and Chronic Health Evaluation (APACHE).  Jack E. Zimmerman, MD, FCCM; Andrew A. Kramer, PhD; Douglas S. McNair, MD, PhD;
Fern M. Malila, RN, MS.  Critical Care Medicine (2006) Vol. 34, No. 5.

