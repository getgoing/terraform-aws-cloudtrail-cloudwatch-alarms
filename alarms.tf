data "aws_caller_identity" "current" {
}

data "aws_region" "current" {
}

locals {
  alert_for     = "CloudTrailBreach"
  sns_topic_arn = var.sns_topic_arn == "" ? aws_sns_topic.default.arn : var.sns_topic_arn
  endpoints = distinct(
    compact(concat([local.sns_topic_arn], var.additional_endpoint_arns)),
  )
  region = var.region == "" ? data.aws_region.current.name : var.region

  metric_name = [
    "AuthorizationFailureCount",
    "S3BucketActivityEventCount",
    "NetworkAclEventCount",
    "GatewayEventCount",
    "VpcEventCount",
    "CloudTrailEventCount",
    "ConsoleSignInFailureCount",
    "ConsoleSignInWithoutMfaCount",
    "RootAccountUsageCount",
    "KMSKeyPendingDeletionErrorCount",
    "AWSConfigChangeCount",
    "RouteTableChangesCount",
  ]

  metric_namespace = var.metric_namespace
  metric_value     = "1"

  filter_pattern = [
    "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }",
    "{ ($.eventSource = s3.amazonaws.com) && (($.eventName = PutBucketAcl) || ($.eventName = PutBucketPolicy) || ($.eventName = PutBucketCors) || ($.eventName = PutBucketLifecycle) || ($.eventName = PutBucketReplication) || ($.eventName = DeleteBucketPolicy) || ($.eventName = DeleteBucketCors) || ($.eventName = DeleteBucketLifecycle) || ($.eventName = DeleteBucketReplication)) }",
    "{ ($.eventName = CreateNetworkAcl) || ($.eventName = CreateNetworkAclEntry) || ($.eventName = DeleteNetworkAcl) || ($.eventName = DeleteNetworkAclEntry) || ($.eventName = ReplaceNetworkAclEntry) || ($.eventName = ReplaceNetworkAclAssociation) }",
    "{ ($.eventName = CreateCustomerGateway) || ($.eventName = DeleteCustomerGateway) || ($.eventName = AttachInternetGateway) || ($.eventName = CreateInternetGateway) || ($.eventName = DeleteInternetGateway) || ($.eventName = DetachInternetGateway) }",
    "{ ($.eventName = CreateVpc) || ($.eventName = DeleteVpc) || ($.eventName = ModifyVpcAttribute) || ($.eventName = AcceptVpcPeeringConnection) || ($.eventName = CreateVpcPeeringConnection) || ($.eventName = DeleteVpcPeeringConnection) || ($.eventName = RejectVpcPeeringConnection) || ($.eventName = AttachClassicLinkVpc) || ($.eventName = DetachClassicLinkVpc) || ($.eventName = DisableVpcClassicLink) || ($.eventName = EnableVpcClassicLink) }",
    "{ ($.eventName = CreateTrail) || ($.eventName = UpdateTrail) || ($.eventName = DeleteTrail) || ($.eventName = StartLogging) || ($.eventName = StopLogging) }",
    "{ ($.eventName = ConsoleLogin) && ($.errorMessage = \"Failed authentication\") }",
    "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") }",
    "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }",
    "{($.eventSource = kms.amazonaws.com) && (($.eventName=DisableKey)||($.eventName=ScheduleKeyDeletion))}",
    "{($.eventSource = config.amazonaws.com) && (($.eventName=StopConfigurationRecorder)||($.eventName=DeleteDeliveryChannel)||($.eventName=PutDeliveryChannel)||($.eventName=PutConfigurationRecorder))}",
    "{ ($.eventName = CreateRoute) || ($.eventName = CreateRouteTable) || ($.eventName = ReplaceRoute) || ($.eventName = ReplaceRouteTableAssociation) || ($.eventName = DeleteRouteTable) || ($.eventName = DeleteRoute) || ($.eventName = DisassociateRouteTable) }",
  ]

  alarm_description = [
    "Alarms when an unauthorized API call is made.",
    "Alarms when an API call is made to S3 to put or delete a Bucket, Bucket Policy or Bucket ACL.",
    "Alarms when an API call is made to create, update or delete a Network ACL.",
    "Alarms when an API call is made to create, update or delete a Customer or Internet Gateway.",
    "Alarms when an API call is made to create, update or delete a VPC, VPC peering connection or VPC connection to classic.",
    "Alarms when an API call is made to create, update or delete a .cloudtrail. trail, or to start or stop logging to a trail.",
    "Alarms when an unauthenticated API call is made to sign into the console.",
    "Alarms when a user logs into the console without MFA.",
    "Alarms when a root account usage is detected.",
    "Alarms when a customer created KMS key is pending deletion.",
    "Alarms when AWS Config changes.",
    "Alarms when route table changes are detected.",
  ]
}

resource "aws_cloudwatch_log_metric_filter" "default" {
  count          = length(local.filter_pattern)
  name           = "${local.metric_name[count.index]}-filter"
  pattern        = local.filter_pattern[count.index]
  log_group_name = var.log_group_name

  metric_transformation {
    name      = local.metric_name[count.index]
    namespace = local.metric_namespace
    value     = local.metric_value
  }
}

resource "aws_cloudwatch_metric_alarm" "default" {
  count               = length(local.filter_pattern)
  alarm_name          = "${local.metric_name[count.index]}-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = local.metric_name[count.index]
  namespace           = local.metric_namespace
  period              = "300" // 5 min
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"
  threshold           = local.metric_name[count.index] == "ConsoleSignInFailureCount" ? "3" : "1"
  alarm_description   = local.alarm_description[count.index]
  alarm_actions       = local.endpoints
}
