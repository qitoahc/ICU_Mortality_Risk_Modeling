#gensim
import smart_open
import gensim
from gensim.utils import simple_preprocess
from gensim.parsing.preprocessing import STOPWORDS
import gensim.corpora as corpora
from gensim.models import CoherenceModel

#nltk
from nltk.stem import WordNetLemmatizer, SnowballStemmer
import nltk

from mimic_fxns import connect, data_extraction

import pickle

def lemmatize_stemming(text):
    stemmer = SnowballStemmer('english')
    return stemmer.stem(WordNetLemmatizer().lemmatize(text, pos='v'))

def preprocess(text):
    result = []
    for token in gensim.utils.simple_preprocess(text):
        if token not in gensim.parsing.preprocessing.STOPWORDS and len(token) > 3:
            result.append(lemmatize_stemming(token))
    return result


def build_lda_model(cn='default', notetype='echo_ecg', topic_n=10, make_pickl=False, pickle_f='lda_echo_ecg_model'):
    """
        LDA model pipeline for echo/ecg notes
        Parameters:
            cn: dict
                Connection details necessary for connecting to data source.  Default value leverages existing defaults contained in connection helper function.
            notetype: string
                String indicating the type of note to build model for. This is used to select the appropriate file name of the desired note extraction query to run in building the model
            topic_n: int
                Integer specifying the number of latent topics to create from the corpus.
            make_pickl: bool
                Flag for indicating if a pickle file should be made from the fit model.
        Returns:
            lda_model: obj
                Returns the fit lda model object
            pickel: file
                Outputs the fit model as a pickel file if make_pickl = True
    """
    if cn == 'default':
        conn = connect()
    if notetype == 'echo_ecg':
        notepath = 'train_echo_ecg_notes.sql'
        notecol = 'echo_ecg'

    notes = data_extraction(notepath, conn)
    notes.dropna(axis=0, inplace=True)
    docs = notes[['subject_id', 'hadm_id', notecol]].groupby(['subject_id','hadm_id']).sum()
    docs.reset_index(inplace=True)
    #stemmer = SnowballStemmer('english')
    processed_docs = docs[notecol].map(preprocess)
    #create dictionary
    id2word = gensim.corpora.Dictionary(processed_docs)
    #create corpus
    texts = processed_docs
    #Term Document Frequency
    bow_corpus = [id2word.doc2bow(text) for text in texts]
    lda_model = gensim.models.LdaMulticore(bow_corpus, num_topics=topic_n, id2word=id2word, passes=2, workers=4)
   
    if make_pickl == True:
        fname = pickle_f+'.pickle' 
        print(fname)
        open(fname,'x')
        with open(fname, 'wb') as f:
            pickle.dump(lda_model, f, pickle.HIGHEST_PROTOCOL)

    return lda_model


if __name__ == '__main__':
    build_lda_model(make_pickl=True, pickle_f='lda_echo_ecg_model')