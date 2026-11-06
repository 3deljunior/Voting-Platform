from flask import Flask, render_template, request, make_response
import boto3
import os
import socket
import random
import json
import logging

option_a = os.getenv('OPTION_A', "Candidate A")
option_b = os.getenv('OPTION_B', "Candidate B")
hostname = socket.gethostname()

QUEUE_URL = os.getenv('SQS_QUEUE_URL')
AWS_REGION = os.getenv('AWS_DEFAULT_REGION', 'us-east-1')

app = Flask(__name__)

gunicorn_error_logger = logging.getLogger('gunicorn.error')
app.logger.handlers.extend(gunicorn_error_logger.handlers)
app.logger.setLevel(logging.INFO)

sqs_client = boto3.client('sqs', region_name=AWS_REGION)

@app.route("/", methods=['POST','GET'])
def hello():
    voter_id = request.cookies.get('voter_id')
    if not voter_id:
        voter_id = hex(random.getrandbits(64))[2:-1]

    vote = None

    if request.method == 'POST':
        vote = request.form['vote']
        app.logger.info('Received vote for %s from voter %s', vote, voter_id)
        
        data = json.dumps({'voter_id': voter_id, 'vote': vote})
        
        if QUEUE_URL:
            try:
                sqs_client.send_message(
                    QueueUrl=QUEUE_URL,
                    MessageBody=data
                )
                app.logger.info('Vote successfully sent to SQS')
            except Exception as e:
                app.logger.error('Error sending message to SQS: %s', str(e))
        else:
            app.logger.error('SQS_QUEUE_URL is not set!')

    resp = make_response(render_template(
        'index.html',
        option_a=option_a,
        option_b=option_b,
        hostname=hostname,
        vote=vote,
    ))
    resp.set_cookie('voter_id', voter_id)
    return resp

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=80, debug=True, threaded=True)
