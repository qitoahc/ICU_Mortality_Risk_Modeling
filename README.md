# ICU Mortality Risk Prediction: Model Development and Application

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/intheroom.PNG)

# Table of Contents
1. [Intro and Motivation](#intro-and-motivation)
2. [Data Sourcing and Storage](#data-sourcing-and-storage)
3. [Featurization and Analysis](#featurization-and-analysis)
4. [Model Development](#model-development)
5. [Operational Proof of Concept](#operational-proof-of-concept)   
   
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

Next, a cohort and hold-out table was created in the database and the admission records were processed through python to exclude those admissions meeting exclusion criteria, splitting the remaining data into training and hold-out test sets, and then updating the appropriate database tables with the necessary patient, admission, and icu stay id's for future reference.  Because of the large volume of data and desire to have adequate testing data, a 60/40 split was set between train and hold-out test.  All future exploratory analysis, featurization development, model development, and model evaluation was completed using the train set of admissions to ensure no leakage or unncessary bias crept into the development.  The code for creating the split and populating the tables is here ![here](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/src/data_prep_pipeline.py) and it leverages helper functions from ![here](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/src/mimic_fxns.py).  It also bears mentioning that for the purposes of this project and it's outcomes (mortality prediction 'in real time' during an admission) the data reflecting billing and coding details were ignored as they would not be present in an EMR for a given patient during their admission.

Based on discussions with a clinical leader from a prominent NW academic medical center, the target timeframe for the project was set at predicting mortality rates within 4 days from a given time snapshot.  This timeframe was established as it was deemed to be both relevant from a care pathway and intervention perspective,  as well as being a longer time horizon than existing 'manual' clinical assessment would be accurate within.  Operationally, this also would enable the model to be fit such that its predictions would not be limited to the date of discharge as the terminal, but upto 3 days post-discharge.  This scope adds value as it increases the relevance of the predictions for discharge planning in addition to the value points discussed previously.

The following graph was used to assess that there was sufficient data present to support the use of the "4 days in advance" timeframe.  

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/icu_hosp_los.png)


The next step taken was to transform the calculated ages to decades.  This was done after replacing the ages >200 years old with the median value of 91.4 that is published regarding the data prior to de-identification process.  The mortality rates (in-hosptial and within 4 days of discharge) by age decade were compared in the graph below, which shows there does appear to be a relationship between mortality and age and that this treatment can adequately handle the modified ages for people over 89. 

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/mortality_rate_by_age_in_decades.png)

The next data element that was explored was that of the date of admission.  As stated above, because of the modifications made to the dates, only the month of the year was leverageable.  The graph below shows the mortality rates by admission month.

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/mortality_rate_by_month.png)

Given the observed variation by month, a trigonemtric transformation of the month was used for model development.  Ultimately a product of sin and cos gave a good approximate fit to the patterns observed.


Lab values and vital signs were the next data elements to consider.  What was found in the literature seemed to indicate that most of the existing work on models like this, have a 'stepwise' value mapping assigned to each lab that attempts to 'weight' data that reflects abnormal lab values relative to normal ranges.  In order to improve the scalability of this model with the end goal of 'operationalization', a simple algorithm was developed to add a 2nd-order fit to each of the categories such that the further from normal a given lab result is, the greater weight it gets.  Values within normal ranges would get no weight.  An example plot of this kind of transformation applied over a range of values is below.  The 'normal' ranges used in developing the model came from the American College of Physicians and is available ![here](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/reference/ACP%20normal-lab-values.pdf)

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/lab_transform.PNG)

The lab values that were considered in the scope of this project (based on literature research and consultation with a clinician) were: aniongap, albumin, bilirubin, creatinine, glucose, hematocrit, hemoglobin, lactate, platelet counts, sodium, blood-urea-nitrogen, and white blood cell count.  The vital signs used were: temperature, heartrate, systolic blood pressure, and mean arterial pressure.  Since vitals could be obtained as frequently as hourly and multiple lab results could exist on a single day, there was a need to get a 'daily' representative value.  In consulting with the previously mentioned physician, took the approach of taking the maximum value for a given day.  This approach was established because of the use case needing to understand the true clinical risk that a patient has, rather than the efficacy of symptom/disease management in response to an abnormal lab or vital measurement.  Ultimately by applying the risk model to daily data, the operational use would enable any sustained symptom/disease management to show up in future day risk predictions beyond the 'max' spike day.

The next substantial feature developed was related to echocardiogram (ECHO) and electrocardiogram (ECG) notes.  These notes were selected out of the larger pool of medical record chart notes as they had a clear category label and reflected a 'narrowed' scope of possible text to process.   ECHO and ECG notes were featurized using a Latent Dirichlet Allocation (LDA) topic model, which establishes topics from across the entire corpus of notes which can then be used to categorize each individual note.  The categorization to topics was then used as the features for model development.  This process leveraged a standard language processing pipeline process and the GenSim library to tokenize the corpus of notes, train and fit a LDA model, and then store the fit model for use in processing note data within the larger ICU mortality risk prediction model.  The inclusion of additional chart notes was left outside of the scope of this phase of this project.

Additional featurization and/or transformations that were used were:
1. Creation of a re-admission flag on admissions that represented a readmission to the hospital within 30 days of a prior readmission
   * ![Readmit Flag SQL](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/src/readmission_flag_creation.sql)
2. One-Hot Encoding of Marital Status, Religion, and Insurance coverage
3. Chronic condition flags - identified by parsing admitting diagnosis description field to capture conditions outlined in the literature [2]
   *  Encoding for each: AIDS, cirrhosis, hepatic failure, immunosupression, lymphoma, leukemia or myeloma, metastatic tumor
   *  Aggregate chronic condition field with value for the number of chronic conditions flagged
   
## **Model Development**:
The model development process that was followed can be seen in the flowchart below - including the initial data setup, extraction, featurization, training, and evaluation steps.    

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/model_development_pipeline.PNG)

The first model developed was a logistic regression model.  This was built up iteratively, starting with the admission/demographics features then adding in labs, vitals, and finally the chart notes.  Because of the two-fold use of the model there is critical importance to maximizing the true positives identified while also minimizing the amount of false positives.  Because of this, ROC curves and 'Area Under The Curve' (AUC) were used in the evaluation.  The iterative process and resulting ROC curves can be found [here](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/development_evaluation_iterations.PNG).  The final performance of the logistic regression model can be seen below:

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/final_logreg_model_performance.png)

Next a random forest model was developed with the same feature set.  Hyperparameter tuning was done leveraging grid search functionality within SKLearn.  The final model performance as well as the 10 most important features by fraction of samples affected are shown below:

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/random_forest_final_model_performance.PNG)

In looking into more details behind each model developed, it seemed that the logistic regression model tended to err towards false positives (as in someone had a high mortality risk when in fact they survived) while the random forest model erred towards false negatives.  Attempts were made to leverage both models together in an ensemble approach (using logistic regression as an input to random forest, aggregating predicted probabilities, and adjusting probability thresholds) but no significant performance improvement was achieved leading to a decision to stick with the random forest model as the final model for the benefit of simplicity and interpretability. 

## **Operational Proof of Concept**:
With a final model developed, the next step was to create a pipeline for creating daily data across all admissions to enable proof-of-concept reporting to demonstrate the operational applicability of EMR data and a predictive mortality risk model.  The pipeline flow, including the key transformation of carrying forward 'last available' data to ensure daily data was present, is represented in the diagram below:

![alt text](https://github.com/qitoahc/ICU_Mortality_Risk_Modeling/blob/master/images/dashboard_creation_pipeline.PNG)

After creating the daily data set, an extract representing a full ICU ward of 77 patients was created and then loaded to Tableau for dashboard creation.  The dashboard is meant to show how biometric and risk data could be compiled into an interactive dashboard enabling someone to see the status of the entire ICU at one view while enabling drill down by risk or specific patient to get daily trending data.  The dashboard proof of concept can be found on Tableau's Public site at this link: [Proof of concept dashboard](https://public.tableau.com/profile/jesse.southworth#!/vizhome/ICUMortalityDashboard_16195670538950/ICUDashboard)


## **Credits and Resources**:
1. MIMIC-III, a freely accessible critical care database. Johnson AEW, Pollard TJ, Shen L, Lehman L, Feng M, Ghassemi M, Moody B, Szolovits P, Celi LA, and Mark RG. Scientific Data (2016). DOI: 10.1038/sdata.2016.35. Available from: http://www.nature.com/articles/sdata201635
2.  Acute Physiology and Chronic Health Evaluation (APACHE).  Jack E. Zimmerman, MD, FCCM; Andrew A. Kramer, PhD; Douglas S. McNair, MD, PhD;
Fern M. Malila, RN, MS.  Critical Care Medicine (2006) Vol. 34, No. 5.

