# Deploying a recommender system on the cloud - Sourcecode

This directory contains the code of the algorithm and API configuration files.

### Libraries
- __Scikit-Surprise__: Used to train the recommender model and to make predictions of the ratings.
- __Flask__: Used to build the REST API method for generating a predicted rating given a user and a movie id.
- __Nginx__: Used as a front-end reverse proxy
- __Gunicorn__: Application server to communicate with the Flask application.

### Code files
- __lambda_function.py__: Code for the handler function of AWS Lambda.
- __nginx.conf__: Configuration of the reverse proxy.
- __predictor.py__: Flask application with the API methods for predicting movie ratings with the loaded model.
- __serve__: Scoring service shell. Generally there is no need to modify it.
- __train__: Algorithm for training the recommender model after loading the ratings dataset.
- __wsgi.py__: Wrapper for Gunicorn to find the app.
