provider "aws" {
  region = var.aws_region
}
#=================================
# 1. STORAGE (S3 & DynamoDB)
#=================================
resource "aws_s3_bucket" "logidata_lake" {
  bucket = var.bucket_name
  tags   = { Project = var.project_tag }
  force_destroy = true
}

resource "aws_s3_object" "folders" {
  for_each = toset(["bronze/", "silver/", "gold/", "scripts/", "temp/"])
  bucket   = aws_s3_bucket.logidata_lake.id
  key      = each.value
  content_type = "application/x-directory"
}

resource "aws_dynamodb_table" "sensors_table" {
  name         = var.db_sensors_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "vehiculo"
  range_key    = "timestamp"
  attribute {
    name = "vehiculo"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }
}

#=================================
# 2. STREAMING (Kinesis)
#=================================
resource "aws_kinesis_stream" "sensor_stream" {
  name        = "logidata-sensor-stream-jsge"
  shard_count = 1
}

#=================================
# 3. NOTIFICACIONES (SNS)
#=================================
resource "aws_sns_topic" "alerts" {
  name = "logidata-temperature-alerts-jsge"
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

#===========================================
# 4. LAMBDA (Procesamiento en tiempo real)
#===========================================
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "../streaming/process_sensors.py"
  output_path = "lambda_function_payload.zip"
}

resource "aws_lambda_function" "sensor_processor" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "LogiData_StreamProcessor_jsge"
  role          = aws_iam_role.lambda_streaming_role.arn
  handler       = "process_sensors.handler"
  runtime       = "python3.9"
  environment {
    variables = {
      TABLE_NAME    = aws_dynamodb_table.sensors_table.name
      SNS_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }
}

resource "aws_lambda_event_source_mapping" "kinesis_trigger" {
  event_source_arn  = aws_kinesis_stream.sensor_stream.arn
  function_name     = aws_lambda_function.sensor_processor.arn
  starting_position = "LATEST"
}

#=================================
# 5. BATCH (Glue Job & Crawler)
#=================================
resource "aws_s3_object" "upload_spark_script" {
  bucket = aws_s3_bucket.logidata_lake.id
  key    = "scripts/bronze_to_silver.py"
  source = "../processing/bronze_to_silver.py"
  etag   = filemd5("../processing/bronze_to_silver.py")
}

resource "aws_glue_job" "bronze_to_silver" {
  name     = "logidata-etl-silver-jsge"
  role_arn = aws_iam_role.glue_role.arn
  glue_version = "4.0" # <-- Esto fuerza el uso de Spark 3.3 y Python 3

  command {
    name            = "glueetl" # Este nombre es obligatorio para jobs de Spark
    script_location = "s3://${aws_s3_bucket.logidata_lake.bucket}/scripts/bronze_to_silver.py"
    python_version  = "3" 
      }

  default_arguments = {
    "--job-language"        = "python"
    "--TempDir"             = "s3://${aws_s3_bucket.logidata_lake.bucket}/temp/"
    "--enable-metrics"      = "true"
    "--enable-continuous-cloudwatch-log" = "true" 
  }
}

resource "aws_glue_catalog_database" "logidata_db" {
  name = "logidata_catalog_jsge"
}

resource "aws_glue_crawler" "silver_crawler" {
  database_name = aws_glue_catalog_database.logidata_db.name
  name          = "logidata-silver-crawler-jsge"
  role          = aws_iam_role.glue_role.arn
  s3_target { path = "s3://${aws_s3_bucket.logidata_lake.bucket}/silver/" }
}