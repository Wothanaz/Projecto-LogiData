# --- ROL DE GLUE ---
resource "aws_iam_role" "glue_role" {
  name = "LogiData-GlueRole-jsge"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ 
      Action = "sts:AssumeRole", 
      Effect = "Allow", 
      Principal = { Service = "glue.amazonaws.com" } 
    }]
  })
}

# --- POLÍTICA PARA EL DATA CATALOG (Bronze, Silver, Gold) ---
resource "aws_iam_policy" "glue_catalog_policy" {
  name        = "LogiData-GlueCatalogPolicy-jsge"
  description = "Permisos para las capas de datos del proyecto LogiData"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:DeleteTable",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartitions",
          "glue:BatchCreatePartition",
          "glue:BatchGetPartition",
          "glue:StartCrawler"
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/logidata_*",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/logidata_*/*"
        ]
      }
    ]
  })
}

# Adjuntar políticas al Rol
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_catalog_attach" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_catalog_policy.arn
}

resource "aws_iam_role_policy_attachment" "glue_s3" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

#=================================
# --- ROL PARA LAMBDA ---
#=================================
resource "aws_iam_role" "lambda_streaming_role" {
  name = "LogiData-LambdaRole-jsge"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ 
      Action = "sts:AssumeRole", 
      Effect = "Allow", 
      Principal = { Service = "lambda.amazonaws.com" } 
    }]
  })
}

resource "aws_iam_role_policy" "lambda_combined_policy" {
  name = "LogiData-LambdaPolicy-jsge"
  role = aws_iam_role.lambda_streaming_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { 
        Sid    = "KinesisRead"
        Effect = "Allow", 
        Action = [
          "kinesis:GetRecords", 
          "kinesis:GetShardIterator", 
          "kinesis:DescribeStream", 
          "kinesis:ListShards",
          "kinesis:DescribeStreamSummary"
        ], 
        Resource = "*" 
      },
      { 
        Sid    = "DynamoAccess" # Cambiado a Access porque ahora lee y escribe
        Effect = "Allow", 
        Action = [
          "dynamodb:PutItem", 
          "dynamodb:GetItem",    # <--- CRUCIAL para leer el contador de racha
          "dynamodb:UpdateItem", 
          "dynamodb:BatchWriteItem"
        ], 
        Resource = "*" 
      },
      {
        Sid    = "SNSPublish"
        Effect = "Allow",
        Action = ["sns:Publish"],
        Resource = "*"
      },
      { 
        Sid    = "CloudWatchLogs"
        Effect = "Allow", 
        Action = [
          "logs:CreateLogGroup", 
          "logs:CreateLogStream", 
          "logs:PutLogEvents"
        ], 
        Resource = "arn:aws:logs:*:*:*" 
      }
    ]
  })
}
# ==========================================================
# ROL PARA ANALÍTICA Y VISUALIZACIÓN (Athena/QuickSight)
# ==========================================================

resource "aws_iam_role" "data_analyst_role" {
  name = "LogiData-DataAnalyst-Role-jsge"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = ["athena.amazonaws.com", "quicksight.amazonaws.com"] }
    }]
  })
}

resource "aws_iam_role_policy" "analyst_policy" {
  name = "LogiData-Analyst-Policy-jsge"
  role = aws_iam_role.data_analyst_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # 1. Permiso para ver las tablas en el catálogo de Glue
        Effect = "Allow"
        Action = ["glue:GetDatabase", "glue:GetTable", "glue:GetPartitions", "glue:GetTables"]
        Resource = "*"
      },
      {
        # 2. Permiso para leer solo las capas finales del Data Lake (Silver y Gold)
        Effect = "Allow"
        Action = ["s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          "${aws_s3_bucket.logidata_lake.arn}",
          "${aws_s3_bucket.logidata_lake.arn}/silver/*",
          "${aws_s3_bucket.logidata_lake.arn}/gold/*"
        ]
      },
      {
        # 3. Permiso para usar Athena y guardar resultados de consultas
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution"
        ]
        Resource = "*"
      }
    ]
  })
}
# ==========================================================
# ROL PARA FIREHOUSE
# ==========================================================
resource "aws_iam_role" "firehose_role" {
  name = "LogiData-FirehoseRole-jsge"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "firehose_s3_policy" {
  name = "firehose_s3_policy"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = ["s3:AbortMultipartUpload", "s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket", "s3:PutObject"]
        Resource = [
          aws_s3_bucket.logidata_lake.arn,
          "${aws_s3_bucket.logidata_lake.arn}/*"
        ]
      },
      {
        Sid    = "KinesisAccess"
        Effect = "Allow"
        Action = ["kinesis:DescribeStream", "kinesis:GetShardIterator", "kinesis:GetRecords", "kinesis:ListShards"]
        Resource = aws_kinesis_stream.sensor_stream.arn 
      }
    ]
  })
}

#=========================================
#Rol PAra quicksight
#=========================================
# --- 2. Rol de Servicio para QuickSight ---
resource "aws_iam_role" "quicksight_role" {
  name = "${var.project_tag}-QuickSight-Service-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "quicksight.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = var.project_tag
  }
}

# --- 3. Política de Acceso a Datos (S3, Athena, Glue) ---
resource "aws_iam_policy" "quicksight_data_policy" {
  name        = "${var.project_tag}-QuickSight-Data-Policy"
  description = "Permite a QuickSight consultar el Data Lake LogiData"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Lectura del Data Lake (Silver y Gold)
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Effect   = "Allow"
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      },
      # Ejecución en Athena
      {
        Action = [
          "athena:BatchGetQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StartQueryExecution",
          "athena:StopQueryExecution",
          "athena:ListWorkGroups",
          "athena:GetWorkGroup"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      # Consulta al Catálogo de Glue (Metadata)
      {
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      # Permisos para los resultados de Athena
      {
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation"
        ]
        Effect   = "Allow"
        Resource = [
          "arn:aws:s3:::aws-athena-query-results-*"
        ]
      }
    ]
  })
}

# --- 4. Adjuntar Política al Rol ---
resource "aws_iam_role_policy_attachment" "quicksight_attach" {
  role       = aws_iam_role.quicksight_role.name
  policy_arn = aws_iam_policy.quicksight_data_policy.arn
}