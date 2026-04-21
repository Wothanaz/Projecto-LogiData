variable "aws_region" {
  description = "Región de AWS donde se desplegará la infraestructura"
  type        = string
  default     = "us-east-1" # Puedes cambiarla por tu región preferida
}

variable "bucket_name" {
  description = "Nombre único del bucket para el Data Lake"
  type        = string
  default     = "logidata-datalake-jsge"
}

variable "db_sensors_name" {
  description = "Nombre de la tabla DynamoDB"
  type        = string
  default     = "LogiData_Sensors"
}

variable "project_tag" {
  description = "Etiqueta para identificar recursos del proyecto"
  type        = string
  default     = "LogiData"
}

variable "notification_email" {
  description = "Correo para alertas de SNS"
  type        = string
  default     = "tu-correo@ejemplo.com" # CAMBIA ESTO
}