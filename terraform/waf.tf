resource "aws_wafv2_web_acl" "main" {
  name        = "campus-voting-waf"
  description = "WAF ACL for Campus Voting Application"
  scope       = "REGIONAL" # For ALB, use REGIONAL. 

  default_action {
    allow {} 
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "campusVotingWaf"
    sampled_requests_enabled   = true
  }

  # SQL Injection
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }
}

# associate the WAF with the ALB
resource "aws_wafv2_web_acl_association" "alb_association" {
  resource_arn = aws_lb.voting_alb.arn 
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}