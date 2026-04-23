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
# 2. STREAMING 
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
  maximum_batching_window_in_seconds = 60 
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

resource "aws_glue_job" "job_batch" {
  name     = "LogiData-Batch-Processing-jsge"
  role_arn = aws_iam_role.glue_role.arn
  glue_version = "4.0"

  command {
    script_location = "s3://${aws_s3_bucket.logidata_lake.bucket}/${aws_s3_object.glue_script_batch.key}"
    python_version  = "3"
  }
  
  default_arguments = {
    "--bucket_name" = aws_s3_bucket.logidata_lake.id
    "--job-bookmark-option" = "job-bookmark-disable" # Opcional: útil para pruebas
  }
}


#Subir script de bronze_to_silver batch
resource "aws_s3_object" "glue_script_batch" {
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
    job_name = aws_glue_job.job_batch.name
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

#============================================
# ORQUESTACIÓN STREAM (Firehouse)
#==============================================

# Subir script de bronze_to_silver sensores
resource "aws_s3_object" "glue_script_sensores" {
  bucket = aws_s3_bucket.logidata_lake.id
  key    = "scripts/sensors_bronze_to_silver.py" 
  source = "${path.module}/../processing/sensors_bronze_to_silver.py" 
  etag   = filemd5("${path.module}/../processing/sensors_bronze_to_silver.py") 
}
resource "aws_glue_job" "job_sensores" {
  name     = "LogiData-Sensors-Processing-jsge"
  role_arn = aws_iam_role.glue_role.arn
  glue_version = "4.0"
  command {
    script_location = "s3://${aws_s3_bucket.logidata_lake.bucket}/${aws_s3_object.glue_script_sensores.key}"
    python_version  = "3"
  }


    default_arguments = {
    "--job-language"        = "python"
    "--job-bookmark-option" = "job-bookmark-disable"
    "--bucket_name"         = aws_s3_bucket.logidata_lake.id 
  }
  # ------------------------
}

# --- CONFIGURACIÓN DE FIREHOSE (En main.tf) ---
resource "aws_kinesis_firehose_delivery_stream" "sensores_bronze" {
  name        = "firehose-sensores-to-bronze"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.sensor_stream.arn
    role_arn           = aws_iam_role.firehose_role.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.logidata_lake.arn

    prefix              = "bronze/sensores/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "errors/sensores/!{firehose:error-output-type}/"

    buffering_size     = 64
    buffering_interval = 120 # Tus 2 minutos de buffer

    compression_format = "GZIP"
  }
}

# --- ÚNICA CONFIGURACIÓN DE CICLO DE VIDA ---
resource "aws_s3_bucket_lifecycle_configuration" "data_lake_lifecycle" {
  bucket = aws_s3_bucket.logidata_lake.id

  # REGLA 1: Para los datos de sensores en streaming (Capa Bronze)
  rule {
    id     = "archive-bronze-sensors"
    status = "Enabled"

    filter {
      prefix = "bronze/sensores/"
    }

    # Mover a almacenamiento barato tras 30 días
    transition {
      days          = 30
      storage_class = "GLACIER_IR"
    }

    # Borrar permanentemente tras 90 días
    expiration {
      days = 90
    }
  }

  # REGLA 2: Si tenías otra regla antes (por ejemplo, para pedidos), agrégala aquí abajo
  # rule {
  #   id     = "otra-regla"
  #   status = "Enabled"
  #   ...
  # }
}
#DATACATALOG Y CRAWLER
# 1. Base de datos en el Data Catalog (si no la tienes creada)
resource "aws_glue_catalog_database" "bronze_db" {
  name = "logidata_bronze_db"
}

# 2. El Crawler para los Sensores
resource "aws_glue_crawler" "sensors_crawler" {
  database_name = aws_glue_catalog_database.bronze_db.name
  name          = "logidata-sensors-bronze-crawler"
  role          = aws_iam_role.glue_role.arn # El mismo rol de Glue que tiene permisos de S3

  s3_target {
    # Apunta a la carpeta base de sensores
    path = "s3://${var.bucket_name}/bronze/sensores/"
  }

  # Configuración para que detecte las particiones de tiempo automáticamente
  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })

  description = "Crawler para descubrir datos de streaming de sensores en Bronze"
}

#==============================================================================
# 4. NOTIFICACIONES (SNS)
#==============================================================================
resource "aws_sns_topic" "alerts" {
  name = "logidata-alerts-jsge"
}