#=================================
# --- ROL PARA GLUE ---
#=================================
resource "aws_iam_role" "glue_role" {
  name = "LogiData-GlueRole-jsge"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "glue.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_full_s3" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

#=================================
# --- ROL PARA LAMBDA ---
#=================================
resource "aws_iam_role" "lambda_streaming_role" {
  name = "LogiData-LambdaRole-jsge"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "LogiData-LambdaPolicy-jsge"
  role = aws_iam_role.lambda_streaming_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Action = ["kinesis:GetRecords", "kinesis:GetShardIterator", "kinesis:DescribeStream", "kinesis:ListShards"], Effect = "Allow", Resource = "*" },
      { Action = ["dynamodb:PutItem", "dynamodb:UpdateItem"], Effect = "Allow", Resource = "*" },
      { Action = ["sns:Publish"], Effect = "Allow", Resource = "*" },
      { Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Effect = "Allow", Resource = "arn:aws:logs:*:*:*" }
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