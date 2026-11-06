import boto3
import json
import os
import time
import psycopg2
from psycopg2 import sql
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')

QUEUE_URL = os.getenv('SQS_QUEUE_URL')
S3_BUCKET = os.getenv('S3_BUCKET_NAME')
AWS_REGION = os.getenv('AWS_DEFAULT_REGION', 'us-east-1')

DB_HOST = os.getenv('DB_HOST', 'db')
DB_USER = os.getenv('DB_USER', 'postgres')
DB_PASS = os.getenv('DB_PASS', 'postgres')
DB_NAME = os.getenv('DB_NAME', 'postgres')

sqs = boto3.client('sqs', region_name=AWS_REGION)
s3 = boto3.client('s3', region_name=AWS_REGION)

def init_db():
    """Initialization of the database and creation of the votes table if it doesn't exist."""
    conn = psycopg2.connect(host=DB_HOST, user=DB_USER, password=DB_PASS, dbname=DB_NAME)
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS votes (
            voter_id VARCHAR(255) PRIMARY KEY,
            vote VARCHAR(50) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    cur.close()
    conn.close()
    logging.info("Database initialized successfully.")

def process_messages():
    while True:
        try:
            response = sqs.receive_message(
                QueueUrl=QUEUE_URL,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=20 
            )

            if 'Messages' in response:
                for message in response['Messages']:
                    receipt_handle = message['ReceiptHandle']
                    body = json.loads(message['Body'])
                    voter_id = body.get('voter_id')
                    vote = body.get('vote')

                    logging.info(f"Processing vote for {voter_id}: {vote}")

                    try:
                        
                        conn = psycopg2.connect(host=DB_HOST, user=DB_USER, password=DB_PASS, dbname=DB_NAME)
                        cur = conn.cursor()
                        cur.execute("INSERT INTO votes (voter_id, vote) VALUES (%s, %s)", (voter_id, vote))
                        conn.commit()
                        
                        
                        audit_data = json.dumps({"voter_id": voter_id, "vote": vote, "status": "ACCEPTED"})
                        s3.put_object(Bucket=S3_BUCKET, Key=f"audit/accepted/{voter_id}.json", Body=audit_data)
                        logging.info(f"Vote for {voter_id} saved and audited.")

                    except psycopg2.errors.UniqueViolation:
                        
                        logging.warning(f"Duplicate vote detected for {voter_id}. Rejecting.")
                        
                        audit_data = json.dumps({"voter_id": voter_id, "vote": vote, "status": "REJECTED_DUPLICATE"})
                        s3.put_object(Bucket=S3_BUCKET, Key=f"audit/rejected/{voter_id}.json", Body=audit_data)

                    finally:
                        if conn:
                            cur.close()
                            conn.close()

                    sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt_handle)

        except Exception as e:
            logging.error(f"Error processing messages: {e}")
            time.sleep(5) 
if __name__ == '__main__':
    logging.info("Worker started. Waiting for database to be ready...")
    time.sleep(5) 
    init_db()
    logging.info("Starting message polling...")
    process_messages()