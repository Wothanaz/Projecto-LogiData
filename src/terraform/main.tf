#==============================================================================
# 0. CONFIGURACIÓN INICIAL Y DATOS
#==============================================================================
provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# Capas del Data Catalog (Medallion Architecture)
resource "aws_glue_catalog_database" "bronze_db" {
  name = "logidata_bronze_db"
}

resource "aws_glue_catalog_database" "silver_db" {
  name = "logidata_silver_db"
}

resource "aws_glue_catalog_database" "gold_db" {
  name = "logidata_gold_db"
}

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
# 2. STREAMING INFRASTRUCTURE (Kinesis & Firehose)
#==============================================================================
resource "aws_kinesis_stream" "sensor_stream" {
  name        = "logidata-sensor-stream-jsge"
  shard_count = 1
}

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
    buffering_interval = 120
    compression_format = "GZIP"
  }
}

#==============================================================================
# 3. PROCESAMIENTO STREAMING (Job Sensores & Crawler Silver)
#==============================================================================
# 1. Subir el script de Sensores (Bronze a Silver) a S3
resource "aws_s3_object" "glue_script_sensors_silver" {
  bucket = aws_s3_bucket.logidata_lake.id
  key    = "scripts/sensors_bronze_to_silver.py"
  # Cambiamos la ruta para que apunte a 'processing'
  source = "${path.module}/../processing/sensors_bronze_to_silver.py"
  etag   = filemd5("${path.module}/../processing/sensors_bronze_to_silver.py")
}

# 2. Glue Job para procesar Sensores (Streaming)
resource "aws_glue_job" "job_sensors_silver" {
  name     = "LogiData-Sensors-BronzeToSilver-jsge"
  role_arn = aws_iam_role.glue_role.arn
  glue_version = "4.0"
  worker_type  = "G.1X"
  number_of_workers = 2

  command {
    name            = "gluestreaming" # Indica que es un trabajo de streaming
    script_location = "s3://${aws_s3_bucket.logidata_lake.bucket}/${aws_s3_object.glue_script_sensors_silver.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"        = "python"
    "--job-bookmark-option" = "job-bookmark-enable"
    "--bucket_name"         = aws_s3_bucket.logidata_lake.id
  }
}

# 1. Tabla para los contadores consecutivos (Estado de la racha de 5 eventos)
resource "aws_dynamodb_table" "sensor_counter" {
  name           = "LogiData-SensorCounter-jsge"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "vehiculo"

  attribute {
    name = "vehiculo"
    type = "S"
  }
}

# 2. Tópico SNS para las alertas por correo
resource "aws_sns_topic" "alertas_temp" {
  name = "logidata-alertas-temperatura"
}

resource "aws_sns_topic_subscription" "email_alertas" {
  topic_arn = aws_sns_topic.alertas_temp.arn
  protocol  = "email"
  endpoint  = "jsgutierreze@gmail.com"
}

# 3. Empaquetar el código de la Lambda (asegúrate que la ruta al .py sea correcta)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../streaming/process_sensors.py"
  output_path = "${path.module}/process_sensors.zip"
}

# 4. Función Lambda para procesamiento y alertas
resource "aws_lambda_function" "process_sensors" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "LogiData-ProcessSensors-jsge"
  role             = aws_iam_role.lambda_streaming_role.arn
  handler          = "process_sensors.handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      TABLE_NAME         = aws_dynamodb_table.sensors_table.name # Tabla principal definida en tu main.tf 
      COUNTER_TABLE_NAME = aws_dynamodb_table.sensor_counter.name
      SNS_TOPIC_ARN      = aws_sns_topic.alertas_temp.arn
    }
  }
}

# 5. Trigger: Conectar Kinesis con la Lambda
resource "aws_lambda_event_source_mapping" "kinesis_trigger" {
  event_source_arn  = aws_kinesis_stream.sensor_stream.arn # Stream definido en tu main.tf 
  function_name     = aws_lambda_function.process_sensors.arn
  starting_position = "LATEST"
  batch_size        = 100
}

# Crawler para la carpeta de Sensores en Silver
resource "aws_glue_crawler" "sensors_silver_crawler" {
  database_name = aws_glue_catalog_database.silver_db.name
  name          = "logidata-sensors-silver-crawler-jsge"
  role          = aws_iam_role.glue_role.arn # El rol de Glue que ya tienes

  s3_target {
    # Apuntamos específicamente a la subcarpeta de sensores dentro de silver
    path = "s3://${aws_s3_bucket.logidata_lake.bucket}/silver/sensores/"
  }

  # Configuración para que cree la tabla correctamente
  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })

  tags = {
    Project = "LogiData"
    Layer   = "Silver"
  }
}
#==============================================================================
# 4. ORQUESTACIÓN BATCH (Workflow, Crawler Bronze y Job)
#==============================================================================

resource "aws_glue_workflow" "logidata_workflow" {
  name = "logidata-s3-event-workflow"
}

resource "aws_glue_crawler" "logidata_bronze_crawler" {
  database_name = aws_glue_catalog_database.bronze_db.name
  name          = "logidata-batch-bronze-crawler"
  role          = aws_iam_role.glue_role.arn
  s3_target {
    path = "s3://${aws_s3_bucket.logidata_lake.bucket}/bronze/batch/"
  }
}
resource "aws_s3_object" "glue_script_batch" {
  bucket = aws_s3_bucket.logidata_lake.id
  key    = "scripts/bronze_to_silver.py"
  source = "${path.module}/../processing/bronze_to_silver.py"
  etag   = filemd5("${path.module}/../processing/bronze_to_silver.py")
}

resource "aws_glue_job" "job_batch" {
  name     = "LogiData-Batch-BronzeToSilver-jsge"
  role_arn = aws_iam_role.glue_role.arn
  glue_version = "4.0"

  command {
    script_location = "s3://${aws_s3_bucket.logidata_lake.bucket}/scripts/bronze_to_silver.py"
    python_version  = "3"
  }
  
  default_arguments = {
    "--bucket_name"         = aws_s3_bucket.logidata_lake.id
    "--job-bookmark-option" = "job-bookmark-disable"
  }
}

# Trigger: Evento S3 -> Iniciar Crawler Bronze
resource "aws_glue_trigger" "batch_automation_trigger" {
  name          = "logidata-s3-event-trigger"
  type          = "EVENT"
  workflow_name = aws_glue_workflow.logidata_workflow.name
  enabled       = true

  actions {
    crawler_name = aws_glue_crawler.logidata_bronze_crawler.name
  }
}

# Trigger: Crawler Bronze exitoso -> Iniciar Job Batch
resource "aws_glue_trigger" "trigger_job_after_crawler" {
  name          = "logidata-crawler-to-job-trigger"
  type          = "CONDITIONAL"
  workflow_name = aws_glue_workflow.logidata_workflow.name
  enabled       = true

  predicate {
    conditions {
      crawler_name = aws_glue_crawler.logidata_bronze_crawler.name
      crawl_state  = "SUCCEEDED"
    }
  }

  actions {
    job_name = aws_glue_job.job_batch.name
  }
}
resource "aws_glue_crawler" "batch_silver_crawler" {
  database_name = aws_glue_catalog_database.silver_db.name
  name          = "logidata-batch-silver-crawler"
  role          = aws_iam_role.glue_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.logidata_lake.bucket}/silver/batch/"
  }
}
resource "aws_glue_trigger" "trigger_crawler_batch_after_job" {
  name          = "logidata-batch-job-to-crawler-trigger"
  type          = "CONDITIONAL"
  workflow_name = aws_glue_workflow.logidata_workflow.name
  enabled       = true

  predicate {
    conditions {
      job_name = aws_glue_job.job_batch.name
      state    = "SUCCEEDED"
    }
  }

  actions {    
    crawler_name = aws_glue_crawler.batch_silver_crawler.name 
  }
}


#==============================================================================
# 5. CAPA GOLD (Analítica y Almacén de Datos)
#==============================================================================

# 1. Subir el script de transformación a S3
resource "aws_s3_object" "glue_script_gold" {
  bucket = aws_s3_bucket.logidata_lake.id
  key    = "scripts/silver_to_gold.py"
  source = "${path.module}/../processing/silver_to_gold.py" # Asegúrate de que el archivo se llame así
  etag   = filemd5("${path.module}/../processing/silver_to_gold.py")
}

# 2. Glue Job Gold: Procesa todas las tablas de Silver y las une
resource "aws_glue_job" "job_gold" {
  name     = "LogiData-Gold-Processing-jsge"
  role_arn = aws_iam_role.glue_role.arn
  glue_version = "4.0"

  command {
    script_location = "s3://${aws_s3_bucket.logidata_lake.bucket}/${aws_s3_object.glue_script_gold.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"        = "python"
    "--job-bookmark-option" = "job-bookmark-disable"
    "--bucket_name"         = aws_s3_bucket.logidata_lake.id
  }
}

resource "aws_glue_crawler" "gold_crawler" {
  database_name = aws_glue_catalog_database.gold_db.name
  name          = "logidata-gold-crawler"
  role          = aws_iam_role.glue_role.arn

  s3_target {
    # Apunta a la raíz de Gold
    path = "s3://${aws_s3_bucket.logidata_lake.bucket}/gold/"
  }

  # Configuración corregida
  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
    Grouping = {
      TableLevelConfiguration = 2 # Esto le dice al crawler que cree tablas basadas en el segundo nivel de profundidad (las carpetas)
    }
  })
}