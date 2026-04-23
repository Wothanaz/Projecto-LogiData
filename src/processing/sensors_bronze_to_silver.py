import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, from_unixtime, to_timestamp, year, month, dayofmonth, current_timestamp

# --- INICIALIZACIÓN ---
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'bucket_name'])
bucket = args['bucket_name']
print(f"Trabajando con el bucket: {bucket}")
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

BUCKET = args['bucket_name']

# 1. LECTURA DE BRONZE (JSON generado por Firehose)
path_bronze = f"s3://{BUCKET}/bronze/sensores/"
df_raw = spark.read.json(path_bronze)

# 2. TRANSFORMACIÓN Y REGLAS DE CALIDAD
eventos_validos = ["OK", "TEMP_CRITICA"]

df_silver = df_raw.select(
    col("vehiculo").cast("string"),    
    col("evento").cast("string"),
    col("temperatura").cast("float"),
    col("latitud").cast("double"),
    col("longitud").cast("double"),
    # Convertimos el timestamp de segundos (simulador) a Timestamp de Spark
    to_timestamp(from_unixtime(col("timestamp"))).alias("evento_ts"),
    current_timestamp().alias("processed_at")
).filter(
    (col("vehiculo").isNotNull()) & 
    (col("evento").isin(eventos_validos))
)

# 3. PARTICIONAMIENTO POR TIEMPO
df_final = df_silver.withColumn("year", year(col("evento_ts"))) \
                    .withColumn("month", month(col("evento_ts"))) \
                    .withColumn("day", dayofmonth(col("evento_ts")))

# 4. ESCRITURA EN SILVER (Formato Parquet optimizado)
silver_path = f"s3://{BUCKET}/silver/sensores"
df_final.write.mode("overwrite") \
    .partitionBy("year", "month", "day") \
    .format("parquet") \
    .save(silver_path)

job.commit()