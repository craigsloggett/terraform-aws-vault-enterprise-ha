resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "vault_snapshots" {
  bucket = "${var.project_name}-vault-snapshots-${random_id.bucket_suffix.hex}"

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-snapshots" })
}

resource "aws_s3_bucket_versioning" "vault_snapshots" {
  bucket = aws_s3_bucket.vault_snapshots.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vault_snapshots" {
  bucket = aws_s3_bucket.vault_snapshots.id

  # Uses the default AWS-managed aws/s3 KMS key.
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "vault_snapshots" {
  bucket = aws_s3_bucket.vault_snapshots.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
