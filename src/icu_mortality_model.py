import pandas as pd
import numpy as np
# import psycopg2 as psy
# from psycopg2 import sql
# from sqlalchemy import create_engine
import os
# import datetime

# from sklearn.model_selection import train_test_split, KFold, cross_val_score
# from sklearn.metrics import (plot_confusion_matrix, confusion_matrix, precision_score, recall_score, accuracy_score, plot_roc_curve, auc)
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier

from mimic_fxns import (connect, data_extraction, transform_labs, hot_coding, age_bands, month_transform, data_processing, normal_lab_vital_ranges, data_processing_column_refs)
import pickle


def build_x_y(labsql='train_lab_values.sql', patientsql='v_two_data_set_extraction.sql',vitalsql='train_chart_events.sql', echoecgsql='train_echo_ecg_notes.sql'):
    """
        Data transformation and clean-up to create model training and evaluation data sets - feature data and target data.
        Parameters:
            labsql: string
                file name of the desired lab value extraction query to run in building the model
            patientsql: string
                file name of the desired patient and admission-level data extraction query to run in building the model
            vitalsql: string
                file name of the desired vitals data extraction query to run in building the model
            echoecgsql: string
                file name of the desired echo and ecg chart notes data extraction query to run in building the model
        Returns:
            X: dataframe
                Data sets post-clean-up and featurization
            y: dataframe
                Target labels indicating actual mortality.
    """
    conn = connect()

    normal_ranges = normal_lab_vital_ranges()

    id_cols, month_col, age_col, encoding_cols, chronic_cols, merge_cols = data_processing_column_refs()

    labpath = labsql
    labs = data_extraction(labpath, conn)
    print('Lab data loaded...')

    patientpath = patientsql
    admits = data_extraction(patientpath, conn)
    print('Patient admitting data loaded...')

    vitalspath = vitalsql
    vitals = data_extraction(vitalspath, conn)
    print('Vitals data loaded...')

    echoecgpath = echoecgsql
    echoecg_notes = data_extraction(echoecgpath, conn)
    echoecg_notes.dropna(axis=0, inplace=True)
    groupcols = id_cols + ['echo_ecg']
    echoecg_docs = echoecg_notes[groupcols].groupby(id_cols).sum()
    echoecg_docs.reset_index(inplace=True)
    
    print('Echo and ECG data loaded...')
    print('Preparing data for model fitting and/or evaluation...')

    X,y = data_processing(labs, normal_ranges, admits, month_col, encoding_cols, age_col, chronic_cols, merge_cols, id_cols, vitals, echoecg_docs)

    print('Data preparation complete.') 
    return X, y


def build_icu_model(model_type='rf', labsql='train_lab_values.sql', patientsql='v_two_data_set_extraction.sql',vitalsql='train_chart_events.sql', echoecgsql='train_echo_ecg_notes.sql', make_pickl=False, pickle_f='icu_model'):
    """
        ICU Mortality risk prediction model pipeline and trained model file creation.
        Parameters:
            Model_type: string
                Indicator for which of the developed models to create and train.
            labsql: string
                file name of the desired lab value extraction query to run in building the model
            patientsql: string
                file name of the desired patient and admission-level data extraction query to run in building the model
            vitalsql: string
                file name of the desired vitals data extraction query to run in building the model
            echoecgsql: string
                file name of the desired echo and ecg chart notes data extraction query to run in building the model
            make_pickl: bool
                Flag for indicating if a pickle file should be made from the fit model.
            pickle_f: string
                File name for the trained model pickle file
        Returns:
            cm: obj
                Returns the fit class-model object
            pickel: file
                Outputs the fit model as a pickel file if make_pickl = True
    """
    X, y = build_x_y(labsql, patientsql, vitalsql, echoecgsql)
    print('Fitting model...')

    if model_type == 'lr':
        cm = LogisticRegression(solver='liblinear', max_iter=1500)
        cm.fit(X, y)
    elif model_type == 'rf':
        cm = RandomForestClassifier(max_depth=9, n_estimators=250, criterion='gini',  class_weight=None,                         max_features = 'auto', random_state=18,n_jobs=-1)
        cm.fit(X,y)
    else:
        print ('No valid model selected.  Program ending.')
        return None

    print('Model complete.')

    if make_pickl == True:
        fname = pickle_f + '_' + model_type + '.pickle' 
        open(fname,'x')
        with open(fname, 'wb') as f:
            pickle.dump(cm, f, pickle.HIGHEST_PROTOCOL)

    return cm


if __name__ == '__main__':
    build_icu_model(make_pickl=True)