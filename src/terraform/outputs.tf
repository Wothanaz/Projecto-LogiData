# 1. Bucket S3
output "s3_bucket_id" {
  value = aws_s3_bucket.logidata_lake.id
}

# 2. Kinesis Stream
output "kinesis_stream_name" {
  value = aws_kinesis_stream.sensor_stream.name
}

# 3. Lambda (El procesador de sensores real)
output "lambda_function_name" {
  value = aws_lambda_function.process_sensors.function_name
}

# 4. DynamoDB (Tabla de datos y tabla de contadores)
output "dynamodb_table_sensors" {
  value = aws_dynamodb_table.sensors_table.name
}

output "dynamodb_table_counter" {
  value = aws_dynamodb_table.sensor_counter.name
}

# 5. SNS Topic (Alertas)
output "sns_topic_arn" {
  value = aws_sns_topic.alertas_temp.arn
}

# 6. Glue Job (Solo el de Gold, que es el que tienes declarado)
output "job_gold_name" {
  value = aws_glue_job.job_gold.name
}

# 7. Crawlers
output "crawler_gold_name" {
  value = aws_glue_crawler.gold_crawler.name
}

output "crawler_sensors_silver_name" {
  value = aws_glue_crawler.sensors_silver_crawler.name
}



output "crawler_sensors_silver" {
  value = aws_glue_crawler.sensors_silver_crawler.name
}

# --- ORQUESTACIÓN ---
output "workflow_name" {
  value = aws_glue_workflow.logidata_workflow.name
}

