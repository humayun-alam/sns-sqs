provider "aws" {
  region = "us-east-2"
  profile = "home"
}

data "aws_caller_identity" "current" {
}

data "aws_region" "current" {
}

# KMS key h SNS topic
resource "aws_kms_key" "humayun-master-key" {
  multi_region = true
  policy       = <<EOF
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
  tags = {
    TYPE              = var.environment
    ENVIRONMENT       = var.environment
    NAMESPACE         = "h-test"
    PROJECT-PORTFOLIO = "acp"
  }
}

# Alias to key for the encryption of sns and other resources subscribed to that topic.
resource "aws_kms_alias" "humayun_master_key_alias" {
  name          = "alias/humayun-master-key"
  target_key_id = aws_kms_key.humayun-master-key.key_id
}

#Resource for SQS
resource "aws_sqs_queue" "humayun-ses-sqs" {
  name                      = "humayun-ses-sqs"
  message_retention_seconds = 1209600
  fifo_queue                = false
  kms_master_key_id         = "alias/humayun-master-key"
  #  kms_data_key_reuse_period_seconds = 300
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "SQSPermissions",
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::946334840080:root"
        },
        "Action": "SQS:*",
        "Resource": "arn:aws:sqs:us-east-2:946334840080:humayun-ses-sqs",
        "Condition": {
          "ArnEquals": {
            "aws:SourceArn": "arn:aws:sqs:us-east-2:946334840080:humayun-ses-sqs"
          }
        }
      },
      {
        "Sid": "SNSSubscriptionPermissions",
        "Effect": "Allow",
        "Principal": {
          "Service": "sns.amazonaws.com"
        },
        "Action": [
          "sqs:SendMessageBatch",
          "sqs:SendMessage"
        ],
        "Resource": "arn:aws:sqs:us-east-2:946334840080:humayun-ses-sqs",
        "Condition": {
          "ArnLike": {
            "aws:SourceArn": "arn:aws:sns:us-east-1:946334840080:humayun-ses-sns-test"
          }
        }
      }
    ]
  }
  POLICY

  tags = {
    TYPE              = "test"
    ENVIRONMENT       = var.environment
    NAMESPACE         = "test"
    PROJECT-SERVICE   = "acp"
    KubernetesCluster = "acp-test"
    COST-CODE         = "00000"
  }

}

resource "aws_iam_user" "humayun_ses_sqs_user" {
  name = "humayun-ses-sqs-user"
  path = "/"
}

resource "aws_iam_user_policy" "sqs_user_policy" {
  name = "humayun-ses-sqs-userSQSPolicy"
  user = aws_iam_user.humayun_ses_sqs_user.name
  policy = data.aws_iam_policy_document.sqs_policy_document.json
}

data "aws_iam_policy_document" "sqs_policy_document" {
  policy_id = "humayun-ses-sqs-userSQSPolicy"

  statement {
    sid    = "IAMSQSPermissions"
    effect = "Allow"

    resources = [
      aws_sqs_queue.humayun-ses-sqs.arn,
    ]

    actions = concat([
      "sqs:AddPermission",
      "sqs:ChangeMessageVisibility*",
      "sqs:DeleteMessage*",
      "sqs:Get*",
      "sqs:List*",
      "sqs:PurgeQueue",
      "sqs:ReceiveMessage",
      "sqs:RemovePermission",
      "sqs:Send*",
    ], var.enable_set_attributes ? ["sqs:SetQueueAttributes"] : [])
  }

  # this is a deny policy so that it overrides the other policies
  dynamic "statement" {
    for_each = length(var.cidr_blocks) != 0 ? [1] : []

    content {
      sid    = "IAMSQSIPRestriction"
      effect = "Deny"

      resources = [
        aws_sqs_queue.humayun-ses-sqs.arn,
      ]

      actions = [
        "SQS:*"
      ]

      condition {
        test     = "NotIpAddress"
        variable = "aws:SourceIp"
        values   = var.cidr_blocks
      }
    }
  }
}

resource "aws_sqs_queue_policy" "sqs_policy" {
  queue_url = aws_sqs_queue.humayun-ses-sqs.id
  policy = data.aws_iam_policy_document.sqs_policy_document.json
}

data "aws_iam_policy_document" "sqs_default_policy_document" {
#  count   = length(var.kms_alias) == 0 && length(var.redrive_arn) == 0 && length(var.policy) != 0 ? 1 : 0
  version = "2012-10-17"
  statement {
    sid    = "SQS Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions = [
      "SQS:*"
    ]
    resources = [aws_sqs_queue.humayun-ses-sqs.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sqs_queue.humayun-ses-sqs.arn]
    }
  }
}

data "aws_iam_policy_document" "access_key_policy_document" {

  statement {
    sid    = "ManageOwnIAMKeys"
    effect = "Allow"

    actions = [
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:GetAccessKeyLastUsed",
      "iam:GetUser",
      "iam:ListAccessKeys",
      "iam:UpdateAccessKey"
    ]

    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${aws_iam_user.humayun_ses_sqs_user.name}"
    ]
  }
}

resource "aws_iam_policy" "access_keys_policy" {

  name_prefix = "${aws_iam_user.humayun_ses_sqs_user.name}-AccessKeyPolicy"
  policy      = data.aws_iam_policy_document.access_key_policy_document.json
}

resource "aws_iam_user_policy_attachment" "attach_access_key_policy" {

  user       = aws_iam_user.humayun_ses_sqs_user.name
  policy_arn = aws_iam_policy.access_keys_policy.arn
}