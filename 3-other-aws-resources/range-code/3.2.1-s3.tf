############################################################################################
# KMS Keys
############################################################################################
# Create KMS key for encyrpting bucket
resource "aws_kms_key" "bucket_key" {
  description             = "This key is used to encrypt bucket objects"
  enable_key_rotation     = true # Enables auto key rotation
  deletion_window_in_days = 7 # 7-30 days
}

resource "aws_kms_alias" "bucket_key_alias" {
  name          = "alias/bucket-key"
  target_key_id = aws_kms_key.bucket_key.key_id
}


############################################################################################
# S3 BUCKETS
############################################################################################
# Log bucket
resource "aws_s3_bucket" "log_bucket" {
  bucket = "${local.name_prefix}-log-bucket-${random_string.uid.result}" # bucket name

  force_destroy = true # only use during testing
}

# Bucket Ownership
resource "aws_s3_bucket_ownership_controls" "log_bucket_owner" {
  bucket = aws_s3_bucket.log_bucket.id # Bucket to associate to
  
  rule {
    object_ownership = "BucketOwnerEnforced" # Defines bucket/object ownership
  }
}

# S3 Public Access Block
# This should be default configuration for all buckets - required for security
resource "aws_s3_bucket_public_access_block" "log_bucket_block_public_access" {
  bucket = aws_s3_bucket.log_bucket.id # Bucket to associate to

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enables KMS encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "log_bucket_encryption" {
  bucket = aws_s3_bucket.log_bucket.id # Bucket to associate to

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.bucket_key.arn # KMS key association  
      sse_algorithm     = "aws:kms" # Server-side encryption algorithm
    }

    bucket_key_enabled = true # When KMS encryption is used to encrypt new objects in this bucket, the bucket key reduces encryption costs by lowering calls to AWS KMS
  }
}

# Enables bucket versioning
resource "aws_s3_bucket_versioning" "log_bucket_versioning" {
  bucket = aws_s3_bucket.log_bucket.id # Bucket to associate to
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Enables bucket access logging
resource "aws_s3_bucket_logging" "log_bucket_logging" {
  bucket = aws_s3_bucket.log_bucket.id # Bucket to associate to

  target_bucket = aws_s3_bucket.log_bucket.id # Target bucket where yoy are sending logs to -- should be global log bucket for production
  target_prefix = "access-logs/" # Send logs to folder with the target prefix
}

# Force SSL to access bucket
resource "aws_s3_bucket_policy" "log_force_ssl_bucket_policy" {
  bucket = aws_s3_bucket.log_bucket.id # Bucket to associate to
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ForceSSLOnlyAccess"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        "${aws_s3_bucket.log_bucket.arn}/*",
        "${aws_s3_bucket.log_bucket.arn}"
      ],
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })
}

# Enables and sets bucket data lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "log_bucket_config" {
  bucket = aws_s3_bucket.log_bucket.id # Bucket to associate to

  rule {
    id = "logs"

    status = "Enabled" # Enabled or Disabled

    abort_incomplete_multipart_upload {
      days_after_initiation = 1 # number
    }

    expiration {
      days = 365 # integer > 0
    }

    transition {
      days          = 30 # integer >= 0
      storage_class = "STANDARD_IA" # string/enum, one of GLACIER, STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, DEEP_ARCHIVE, GLACIER_IR.
    }

    transition {
      days          = 60 # integer >= 0
      storage_class = "GLACIER" # string/enum, one of GLACIER, STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, DEEP_ARCHIVE, GLACIER_IR.
    }

    noncurrent_version_expiration {
      newer_noncurrent_versions = 3 # integer > 0
      noncurrent_days           = 60 # integer >= 0
    }

    noncurrent_version_transition {
      newer_noncurrent_versions = 3 # integer >= 0
      noncurrent_days           = 30 # integer >= 0
      storage_class             = "GLACIER" # string/enum, one of GLACIER, STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, DEEP_ARCHIVE, GLACIER_IR.
    }
  }
}

