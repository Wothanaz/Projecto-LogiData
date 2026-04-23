import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, from_unixtime, to_timestamp, year, month, dayofmonth, current_timestamp

# --- INICIALIZACIÓN ---
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'bucket_name'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

BUCKET = args['bucket_name']

# 1. LECTURA DE BRONZE (JSON generado por Firehose)
path_bronze = f"s3://{BUCKET}/bronze/sensores/"
df_raw = spark.read.json(path_bronze)

# 2. TRANSFORMACIÓN Y RENOMBRADO PREVENTIVO
# Agregamos el prefijo 's_' para que en la capa Gold no choque con la tabla de Pedidos
eventos_validos = ["OK", "TEMP_CRITICA", "Alerta"]

df_silver = df_raw.select(
    col("vehiculo").cast("string").alias("s_vehiculo"), 
    col("evento").cast("string"),
    col("temperatura").cast("float"),
    col("latitud").cast("double"),
    col("longitud").cast("double"),
    # Convertimos el timestamp de segundos a formato Timestamp
    to_timestamp(from_unixtime(col("timestamp"))).alias("evento_ts"),
    current_timestamp().alias("processed_at")
).filter(
    (col("s_vehiculo").isNotNull()) & 
    (col("evento").isin(eventos_validos))
)

# 3. CREACIÓN DE COLUMNAS DE TIEMPO PARA PARTICIONADO
# También usamos el prefijo 's_' aquí
df_final = df_silver.withColumn("s_year", year(col("evento_ts"))) \
                    .withColumn("s_month", month(col("evento_ts"))) \
                    .withColumn("s_day", dayofmonth(col("evento_ts")))

# 4. ESCRITURA EN SILVER (Formato Parquet)
# Al usar partitionBy con s_year, s_month, s_day, el Crawler creará estas columnas en el catálogo
silver_path = f"s3://{BUCKET}/silver/sensores/"

df_final.write.mode("overwrite") \
    .partitionBy("s_year", "s_month", "s_day") \
    .format("parquet") \
    .save(silver_path)

job.commit()