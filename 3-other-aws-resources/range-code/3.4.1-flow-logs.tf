############################################################################################
# NETWORK
############################################################################################
# Create VPC Flow Log
resource "aws_flow_log" "flow_logs" {
  log_destination      = aws_s3_bucket.log_bucket.arn # Log destination
  log_destination_type = "s3" # Log destination type
  traffic_type         = "ALL" # Type of traffic to filter
  vpc_id               = aws_vpc.vpc.id # VPC to associate flow logs with

  tags = {
    Name = "${local.name_prefix}-flow-logs"
  }

  depends_on = [aws_s3_bucket.log_bucket]
}