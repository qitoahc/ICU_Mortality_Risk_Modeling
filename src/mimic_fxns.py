#the basics
import numpy as np
import pandas as pd

#sql tools
import psycopg2 as psy
from psycopg2 import sql
import sqlalchemy
from sqlalchemy import create_engine

#model pipeline and evaluation
from sklearn.preprocessing import OneHotEncoder
from sklearn.metrics import plot_confusion_matrix, confusion_matrix, precision_score, recall_score, accuracy_score

#connection and file tools
import sys
import os
import pickle

#gensim
import smart_open
import gensim
from gensim.utils import simple_preprocess
from gensim.parsing.preprocessing import STOPWORDS
import gensim.corpora as corpora
from gensim.models import CoherenceModel

#nltk
from nltk.stem import WordNetLemmatizer, SnowballStemmer
#from nltk.stem.porter import *
import nltk


def connect_details():
    schema = 'mimiciii'
    con_details = {"dbname" : 'mimic', 
               "user" : os.environ['PGSQL_P_USER'], 
               "password" : os.environ['PGSQL_P_PWD'], 
               "host" : 'localhost',
              "options":f'-c search_path={schema}' 
              }
    return con_details

def normal_lab_vital_ranges():
    norm_ranges = {
        'aniongap':[3,10], 
        'albumin':[3.5,5.5], 
        'bilirubin':[.3,1.2], 
        'creatinine':[.7,1.3], 
        'glucose':[100,200], 
        'hematocrit':[36,51],
        'hemoglobin':[12,17], 
        'lactate':[6,16], 
        'platelet':[150,350],
        'sodium':[136,145], 
        'bun':[8,20], 
        'wbc':[4.0,10.0],
        'temperature':[36.0, 37.2],
        'heartrate':[50.0,100.0],
        'systolic_bp':[90.0,120.0],
        'mean_arterial_pressure':[60.0,100.0]}    
    return norm_ranges

def data_processing_column_refs():
    ids = ['subject_id', 'hadm_id', 'icustay_id']
    month_col = ['admit_time_m']
    age_col = ['age_']
    cols_for_encoding = ['admission_type', 'first_careunit', 'insurance', 'relig', 'marital']
    chronic_cols = ['cirrhosis', 'hiv', 'immuno_def', 'hep_fail', 'blood_cncr', 'metastatic_cncr']
    merge_cols = ['subject_id', 'hadm_id']    
    return ids, month_col, age_col, cols_for_encoding, chronic_cols, merge_cols

def connect(connection_details=None):  
    """
    Overview:
        Establishes connection to PostgreSQL database
    Parameters:
        connection_details = dict  
    Returns:
        conn: connection
    """
    conn = None
    if connection_details is None:
        connection_details = connect_details()
    try:
        print('Connecting to PostgreSQL database...')
        conn = psy.connect(**connection_details)
    except (Exception, psy.DatabaseError) as error:
        print(f'Unable to connect to the database: {error}')
        sys.exit(1)
    print('Connection successful')
    return conn

def insert_data(con_details, data_df, table, conn):
    """
    Overview:
        Add's data set from dataframe to table in connected database.  Rollsback if error in loading and prints the error and returns a value for error handling.
    Parameters:
        conn_details: dict
            Connection parameters for establishing sql engine connection
        data_df: dataframe
            Dataset to add to table - assumes schema of dataframe is compatible with schema of target table
        table: str
            name of target table in connected database
        conn: connection
            Active database connection
    Returns:
        int if error, none if no error.
        prints status.
    """
    engine_path = "postgresql+psycopg2://" + con_details['user'] + ":" + con_details['password']  
    engine_path +='@localhost:5432/' +con_details['dbname']
    schema = con_details['options']
    engine = create_engine(engine_path, connect_args={'options': f'{schema}'})
    try:
        data_df.to_sql(table, engine, index=False, if_exists='append')
    except (Exception, psy.DatabaseError) as error:
        print(f'Error: {error}')
        conn.rollback()
        return 1
    conn.commit()
    print(f'Successful updating of {table}')



def data_extraction(filepath, conn):
    '''
    Overview:
        uses file and connection to execute sql query and return results in a dataframe.
    Parameters:
        filepath: str
            Location of desired sql file to execute with the active connection
        conn: connection
            Active database connection
    Returns:
        dataframe contain the query results.
    '''
    extract_q_f = open(filepath)
    extract_q = sql.SQL(extract_q_f.read())
    extract_q_f.close()
    return pd.read_sql(extract_q, conn)

def lab_val_scale(val, rng):
    """
    """
    norm_width = rng[1] - rng[0]
    sign = 1
    if val is None:
        return val
    if val > rng[1]:
        diff = val - rng[1]
    elif val < rng[0]:
        diff = rng[0] - val
        sign = -1
    else:
        diff = 0
    return ((diff / norm_width)**2) * sign

def transform_labs(df,norm_ranges):
    """
    """
    for lab, rng in norm_ranges.items():
        df[lab] = df[lab].apply(lab_val_scale, args=(rng,))

def month_transform(df, month_col):
    """
    """
    shift, squish, stretch = 1, .5, 1.5
    s = squish * np.sin((df[month_col].copy() + shift) * 2*np.pi/(12*stretch))
    c = squish * np.cos((df[month_col].copy() + shift) * 2*np.pi/(12*stretch))
    df['admit_month_transform'] = s*c
    
def hot_coding(df, data_cols):
    """
    """
    enc = OneHotEncoder(sparse=False)
    hot_codes = enc.fit_transform(df[data_cols])
    hot_names = enc.get_feature_names()
    df[hot_names] = hot_codes

def age_bands(df, age_col, band_width):
    """
    """
    df['age_deci'] = (df[age_col] / band_width).astype('int')

def lemmatize_stemming(text, stemmer):
    '''
    '''
    return stemmer.stem(WordNetLemmatizer().lemmatize(text, pos='v'))

def preprocess(text):
    '''
    '''
    stemmer = SnowballStemmer('english')
    result = []
    for token in gensim.utils.simple_preprocess(text):
        if token not in gensim.parsing.preprocessing.STOPWORDS and len(token) > 3:
            result.append(lemmatize_stemming(token, stemmer))
    return result

def echoecg_topics(eenotes_df):
    
    if eenotes_df.shape[0] == 1 and eenotes_df['echo_ecg'].isnull().values.any():
        ecgecho_topics = eenotes_df.copy()
        ecgecho_topics['top1'] = -1
        ecgecho_topics['top2'] = -1
        ecgecho_topics.drop('echo_ecg', axis=1, inplace=True)
        return ecgecho_topics
    #lem, stem and create lists of tokens for each chart record, creating DF of these for each row provided.
    processed_docs = eenotes_df['echo_ecg'].map(preprocess)
    #create dictionary of essentially word IDs
    id2word = gensim.corpora.Dictionary(processed_docs)

    #create corpus
    texts = processed_docs

    #Term Document Frequency - in theory it's a list pertaining to each row of the main DF of notes, said list being the list of each row, with each row bing a list a token ids and frequenc ycounts.
    bow_corpus = [id2word.doc2bow(text) for text in texts]

    pickle_f = 'lda_echo_ecg_model'
    if os.getcwd()[-3:] != 'src':
        pickle_f = './src/' + pickle_f

    fname = pickle_f + '.pickle' 
    with open(fname, 'rb') as f:
        lda_base = pickle.load(f)
    
    mapping = lda_base.get_document_topics(bow_corpus)
    map_csr = gensim.matutils.corpus2csc(mapping)
    map_np = map_csr.T.toarray()
    map_df = pd.DataFrame(map_np)
    #print(map_df)
    toptopics = np.argsort(map_df).iloc[:,-2:].rename(columns={list(map_df.columns)[-2]:'top2', list(map_df.columns)[-1]:'top1'})
    #print(toptopics)
    ecgecho_topics = eenotes_df.merge(toptopics,how='inner',left_index=True, right_index=True)
    ecgecho_topics.drop('echo_ecg', axis=1, inplace=True)
    return ecgecho_topics


def data_processing(labs_df, norm_ranges, admit_df, month_col, cols_for_encoding, age_col, chronic_cols, merge_cols, id_cols, vitals_df, echoecg_notes_df):
    """
    """
    if vitals_df.empty == False:
        labs_df = labs_df.merge(vitals_df, how='left', on=merge_cols, suffixes=[None,"_y"])
    transform_labs(labs_df, norm_ranges)
    month_transform(admit_df, month_col)
    hot_coding(admit_df, cols_for_encoding)
    age_bands(admit_df, age_col, 10)
    echoecg_topics_df = echoecg_topics(echoecg_notes_df)
    admit_df['chronic'] = admit_df[chronic_cols].sum(axis=1)
    print('post chronic', admit_df.shape)
    admit_df = admit_df.merge(labs_df, how='left', on=merge_cols, suffixes=[None,"_y"])
    print(labs_df.shape, 'post labs', admit_df.shape)
    admit_df = admit_df.merge(echoecg_topics_df,how='left', on=merge_cols)
    print(echoecg_topics_df.shape, 'post echo', admit_df.shape)
    admit_df.loc[:,['top2', 'top1']] = admit_df.loc[:,['top2', 'top1']].fillna(-1)

    y = admit_df.pop('death_4_days')
    X = admit_df.copy()
    X.drop(cols_for_encoding, axis=1, inplace=True)
    X.drop(month_col, axis=1, inplace=True)
    X.drop(age_col, axis=1, inplace=True)
    if len(id_cols) > 0:
        X.drop(id_cols, axis=1, inplace=True)
    X.drop(chronic_cols, axis = 1, inplace=True)
    return X, y

def print_results(model, X, y, score, precision, recall):
    """
    Function for printing out details of confusion matrix analysis for a given model.
    Parameters:
    model: model that has been fit with data and has basic functionalaity aligned with SKLearn.
    X: 2d array - data points as x, features for data points as columns
    Y: 1d array - labels for data points in X
    score, precision, recall: float - provided metrics for printing.
    """
    print(model)
    print(f'Score is {score}')
    print(f'Precision is {precision} and recall is {recall}')
    plot_confusion_matrix(model, X, y)

def produce_results(model, X, y, pprint = True):
    """
    creates confusion matrix and calcluates score, precision, recall
    if pprint is true, also prints colored confusion matrix and string summaries
    """
    yhat = model.predict(X)
    #cm = confusion_matrix(y, yhat)
    precision = precision_score(y, yhat)
    recall = recall_score(y, yhat)
    score = model.score(X,y)
    
    if pprint == True:
        print_results(model, X, y,score, precision, recall)
    return score, precision, recall



if __name__ == '__main__':
    pass