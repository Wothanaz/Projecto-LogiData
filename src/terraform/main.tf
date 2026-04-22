#==============================================================================
# 0. CONFIGURACIÓN INICIAL Y DATOS
#==============================================================================
provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

#==============================================================================
# 1. STORAGE (S3 & DynamoDB)
#==============================================================================
resource "aws_s3_bucket" "logidata_lake" {
  bucket        = var.bucket_name
  force_destroy = true
  tags          = { Project = var.project_tag }
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket      = aws_s3_bucket.logidata_lake.id
  eventbridge = true
}

resource "aws_s3_object" "folders" {
  for_each     = toset(["bronze/", "silver/", "gold/", "scripts/", "temp/"])
  bucket       = aws_s3_bucket.logidata_lake.id
  key          = each.value
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

#==============================================================================
# 2. STREAMING (Kinesis & Lambda con ventana de 5 min / 150 reg)
#==============================================================================
resource "aws_kinesis_stream" "sensor_stream" {
  name        = "logidata-sensor-stream-jsge"
  shard_count = 1
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  # Cambiamos la ruta a la carpeta 'streaming'
  source_file = "${path.module}/../streaming/process_sensors.py" 
  output_path = "${path.module}/lambda_function_payload.zip"
}

resource "aws_lambda_function" "process_sensors_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256 # ESTO ES CLAVE
  function_name    = "logidata-sensor-processor-jsge"
  role             = aws_iam_role.lambda_streaming_role.arn
  handler          = "process_sensors.handler"
  runtime          = "python3.9"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.sensors_table.name
    }
  }
}

resource "aws_lambda_event_source_mapping" "kinesis_streaming_automation" {
  event_source_arn  = aws_kinesis_stream.sensor_stream.arn
  function_name     = aws_lambda_function.process_sensors_lambda.arn
  starting_position = "LATEST"

  # REQUERIMIENTO: 150 registros o 5 minutos
  batch_size                         = 150
  maximum_batching_window_in_seconds = 300 
}

#==============================================================================
# 3. ORQUESTACIÓN BATCH (Glue Workflow, Crawler y Job)
#==============================================================================
resource "aws_glue_catalog_database" "logidata_db" {
  name = "logidata_catalog_jsge"
}

resource "aws_glue_workflow" "logidata_workflow" {
  name = "logidata-s3-event-workflow"
}

resource "aws_glue_job" "bronze_to_silver" {
  name         = "logidata-etl-silver-jsge"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.logidata_lake.id}/scripts/bronze_to_silver.py"
    python_version  = "3"
 }

  
  default_arguments = {
    "--bucket_name" = aws_s3_bucket.logidata_lake.id
    "--job-bookmark-option" = "job-bookmark-disable" # Opcional: útil para pruebas
  }
}


#Subir script de bronze_to_silver
resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.logidata_lake.id
  key    = "scripts/bronze_to_silver.py"
  source = "${path.module}/../processing/bronze_to_silver.py"
  etag   = filemd5("${path.module}/../processing/bronze_to_silver.py")
}

resource "aws_glue_crawler" "logidata_bronze_crawler" {
  database_name = aws_glue_catalog_database.logidata_db.name
  name          = "crawler-bronze-logidata"
  role          = aws_iam_role.glue_role.arn
  s3_target {
    path = "s3://${aws_s3_bucket.logidata_lake.bucket}/bronze/"
  }
}

resource "aws_glue_trigger" "batch_automation_trigger" {
  name          = "logidata-s3-event-trigger"
  type          = "EVENT"
  workflow_name = aws_glue_workflow.logidata_workflow.name # <-- Vincular aquí
  enabled       = true

  actions {
    crawler_name = aws_glue_crawler.logidata_bronze_crawler.name
  }
}
resource "aws_glue_trigger" "trigger_job_after_crawler" {
  name          = "logidata-crawler-to-job-trigger"
  type          = "CONDITIONAL"
  workflow_name = aws_glue_workflow.logidata_workflow.name
  enabled       = true

  predicate {
    conditions {
      crawler_name = aws_glue_crawler.logidata_bronze_crawler.name
      crawl_state  = "SUCCEEDED" # Solo si el crawler termina bien
    }
  }

  actions {
    job_name = aws_glue_job.bronze_to_silver.name
  }
}

# Regla de EventBridge para disparar el Workflow
resource "aws_cloudwatch_event_rule" "s3_bronze_specific_trigger" {
  name = "logidata-s3-specific-entities-rule"
  event_pattern = jsonencode({
    "source": ["aws.s3"],
    "detail-type": ["Object Created"],
    "detail": {
      "bucket": { "name": ["${var.bucket_name}"] },
      "object": { "key": [{ "prefix": "bronze/" }] }
    }
  })
}

resource "aws_cloudwatch_event_target" "glue_target" {
  rule      = aws_cloudwatch_event_rule.s3_bronze_specific_trigger.name
  target_id = "TriggerLogiDataWorkflow"
  arn       = "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workflow/${aws_glue_workflow.logidata_workflow.name}"
  role_arn  = aws_iam_role.glue_role.arn
}

#==============================================================================
# 4. NOTIFICACIONES (SNS)
#==============================================================================
resource "aws_sns_topic" "alerts" {
  name = "logidata-alerts-jsge"
}