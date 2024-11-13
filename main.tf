provider "aws" {
  region = "us-east-1"
  profile = "home"
}

resource "aws_kms_replica_key" "humayun_replica_key" {
  description     = "Multi-Region replica key"
  primary_key_arn = "arn:aws:kms:us-east-2:946334840080:key/mrk-60c40402c2a24181bfac91768e656248"
  policy          = <<EOF
  {
      "Version": "2012-10-17",
      "Statement": [
          {
              "Effect": "Allow",
              "Principal": {
                  "AWS": "*"
              },
              "Action": "kms:*",
              "Resource":"*"
          }

      ]
  }

EOF
}

resource "aws_kms_alias" "humayun_replica_key_alias" {
  name          = "alias/humayun_replica-key"
  target_key_id = aws_kms_replica_key.humayun_replica_key.key_id
}

#SNS topic
resource "aws_sns_topic" "humayun_ses_sns_test" {
  name              = "humayun-ses-sns-test"
  kms_master_key_id = aws_kms_replica_key.humayun_replica_key.key_id

  tags = {
    TYPE        = var.environment
    ENVIRONMENT = var.environment
  }
}

resource "aws_sns_topic_subscription" "humayun_ses_sqs_target" {
  topic_arn              = aws_sns_topic.humayun_ses_sns_test.arn
  protocol               = "sqs"
  endpoint               = "arn:aws:sqs:us-east-2:946334840080:humayun-ses-sqs"
  endpoint_auto_confirms = "true"
  raw_message_delivery   = "true"

  depends_on = [
    aws_sns_topic.humayun_ses_sns_test
  ]
}

