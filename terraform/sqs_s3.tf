# Generate a random string to ensure the S3 bucket name is globally unique
resource "random_string" "bucket_suffix" {
  length  = 6
  special = false
  upper   = false
}

# ==================== SQS (Queues) ====================

# 1. Dead-Letter Queue (DLQ)
resource "aws_sqs_queue" "voting_dlq" {
  name                      = "campus-voting-dlq"
  message_retention_seconds = 1209600 # 14 days
}

# 2. Main Voting Queue
resource "aws_sqs_queue" "voting_queue" {
  name = "campus-voting-queue"

  visibility_timeout_seconds = 30
  receive_wait_time_seconds  = 20
  message_retention_seconds  = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.voting_dlq.arn
    maxReceiveCount     = 3
  })
}

# 3. Allow the main queue to send messages to the DLQ
resource "aws_sqs_queue_redrive_allow_policy" "voting_dlq_allow" {
  queue_url = aws_sqs_queue.voting_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.voting_queue.arn]
  })
}

# ==================== S3 (Audit Log) ====================

# 4. Create S3 Bucket and enable Object Lock
resource "aws_s3_bucket" "audit_log" {
  bucket = "campus-voting-audit-${random_string.bucket_suffix.result}"
  force_destroy = true
  object_lock_enabled = true
}

# 5. Enable Versioning (mandatory for Object Lock to work)
resource "aws_s3_bucket_versioning" "audit_versioning" {
  bucket = aws_s3_bucket.audit_log.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 6. Configure file protection against deletion and modification (WORM)
resource "aws_s3_bucket_object_lock_configuration" "audit_lock" {
  bucket = aws_s3_bucket.audit_log.id

  rule {
    default_retention {
      mode = "COMPLIANCE" # Strongest protection mode, prevents even the Root User from modifying files
      days = 30           # Keep votes protected for 30 days
    }
  }
}
