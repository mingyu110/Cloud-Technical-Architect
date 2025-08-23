import os
from flask import Flask, Response, request
from collections import defaultdict
from surprise import dump

# Path where SageMaker mounts data in our container
prefix = '/opt/ml/'
model_path = os.path.join(prefix, 'model', 'recommender_system')


class ScoringService(object):
    model = None

    @classmethod
    def get_model(cls):
        """Get the model for this instance if not already loaded."""
        if cls.model == None:
            print('Loading model ...')
            _, cls.model = dump.load(model_path)
        return cls.model

    @classmethod
    def predict(cls, user_id, movie_id):
        """For the inputs, do the prediction and return it."""
        model = cls.get_model()
        print('Predicting rating ...')
        prediction = model.predict(uid=user_id, iid=movie_id)
        rating = str(round(prediction.est, 1))
        print(f'Predicted rating from user {user_id} for movie {movie_id}: {rating}')
        return rating


# The flask app for serving predictions
app = Flask(__name__)


@app.route('/ping', methods=['GET'])
def ping():
    """Determine if the container is working and healthy. In this sample container, we declare
    it healthy if we can load the model successfully."""
    health = ScoringService.get_model() is not None
    status = 200 if health else 404
    return Response(response='\n', status=status, mimetype='application/json')

@app.route('/invocations', methods=['POST'])
def recommend():
    """Determine the prediction for the given user and movie."""
    content = request.json
    user_id = content['userId']
    movie_id = content['movieId']
    response = ScoringService.predict(user_id, movie_id)
    return Response(response=response, status=200, mimetype="application/json")
