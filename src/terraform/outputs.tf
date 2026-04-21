# --- Datos del Data Lake ---
output "s3_bucket_id" {
  description = "ID del Bucket del Data Lake"
  value       = aws_s3_bucket.logidata_lake.id
}

# --- Datos de Streaming  ---
output "kinesis_stream_arn" {
  description = "ARN del Stream de Kinesis para configurar el simulador"
  value       = aws_kinesis_stream.sensor_stream.arn
}

output "kinesis_stream_name" {
  description = "Nombre del Stream de Kinesis"
  value       = aws_kinesis_stream.sensor_stream.name
}

# --- Datos de Base de Datos ---
output "dynamodb_table_name" {
  description = "Nombre de la tabla de DynamoDB para sensores"
  value       = aws_dynamodb_table.sensors_table.name
}

# --- Datos de Procesamiento ---
output "glue_job_name" {
  description = "Nombre del Job de Glue ETL"
  value       = aws_glue_job.bronze_to_silver.name
}

output "lambda_function_name" {
  description = "Nombre de la función Lambda procesadora"
  value       = aws_lambda_function.sensor_processor.function_name
}

# --- Datos de Notificaciones ---
output "sns_topic_arn" {
  description = "ARN del tópico de SNS para alertas de temperatura"
  value       = aws_sns_topic.alerts.arn
}

# --- Datos de Analítica ---
output "glue_catalog_database" {
  description = "Base de datos en el catálogo de Glue"
  value       = aws_glue_catalog_database.logidata_db.name
}