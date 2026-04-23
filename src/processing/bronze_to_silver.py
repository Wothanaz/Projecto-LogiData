import sys
import boto3
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, dayofmonth, month, year, current_timestamp, to_timestamp

# --- INICIALIZACIÓN ---
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'bucket_name'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

BUCKET = args['bucket_name']
AHORA = current_timestamp()
FMT = "yyyy-MM-dd HH:mm:ss"

BRONZE_PREFIX = "bronze/batch/"
SILVER_BASE_PATH = f"s3://{BUCKET}/silver/batch"

def clean_and_load(entity_name, df_raw):
    print(f"🚀 Procesando Entidad: {entity_name}")
    
    cols = df_raw.columns
    # Rescate de columnas si vienen como col0
    if "col0" in cols or "_c0" in cols:
        print(f"⚠️ Mapeando columnas manualmente para {entity_name}")
        if entity_name == "clientes":
            df_raw = df_raw.toDF("id_cliente", "nombre", "zona", "tipo_cliente")
        elif entity_name == "pedidos":
            df_raw = df_raw.toDF("id_pedido", "id_cliente", "id_producto", "fecha", "monto")
        elif entity_name == "catalogo":
            df_raw = df_raw.toDF("id_producto", "categoria", "precio", "tipo_entrega")
        elif entity_name == "entregas":
            df_raw = df_raw.toDF("id_pedido", "hora_programada", "hora_real", "zona", "conductor", "vehiculo")

    df_audit = df_raw.withColumn("processed_at", AHORA)
    partition_cols = None

    if entity_name == "clientes":
        df_clean = df_audit.select("id_cliente", "nombre", "zona", "tipo_cliente", "processed_at")
    
    elif entity_name == "catalogo":
        df_clean = df_audit.select("id_producto", "categoria", "precio", "tipo_entrega", "processed_at")

    elif entity_name == "pedidos":
        df_base = df_audit.select(
            col("id_pedido"), col("id_cliente"), col("id_producto"), 
            to_timestamp(col("fecha"), FMT).alias("fecha_ts"),
            col("monto").cast("float"), "processed_at"
        )
        df_clean = df_base.withColumn("year", year("fecha_ts")) \
                          .withColumn("month", month("fecha_ts")) \
                          .withColumn("day", dayofmonth("fecha_ts"))
        partition_cols = ["year", "month", "day"]

    elif entity_name == "entregas":
        df_base = df_audit.select(
            col("id_pedido"), 
            to_timestamp(col("hora_programada"), FMT).alias("hora_prog_ts"),
            to_timestamp(col("hora_real"), FMT).alias("hora_real_ts"),
            "zona", "conductor", "vehiculo", "processed_at"
        )
        df_clean = df_base.withColumn("year", year("hora_prog_ts")) \
                          .withColumn("month", month("hora_prog_ts")) \
                          .withColumn("day", dayofmonth("hora_prog_ts"))
        partition_cols = ["year", "month", "day"]
    else:
        df_clean = df_audit

    # ESCRITURA
    # Quitamos el slash final en la variable path para evitar rutas extrañas
    path = f"{SILVER_BASE_PATH}/{entity_name}"
    print(f"💾 Guardando {entity_name} en: {path}")
    
    writer = df_clean.write.mode("overwrite").format("parquet")
    if partition_cols:
        writer = writer.partitionBy(*partition_cols)
    writer.save(path)

# --- EJECUCIÓN ---
s3_client = boto3.client('s3')
paginator = s3_client.get_paginator('list_objects_v2')
# El prefix ya debe incluir el slash al final
pages = paginator.paginate(Bucket=BUCKET, Prefix=BRONZE_PREFIX, Delimiter='/')

found_data = False
for page in pages:
    if 'CommonPrefixes' in page:
        for prefix in page['CommonPrefixes']:
            folder = prefix.get('Prefix')
            entidad = folder.split('/')[-2]
            found_data = True
            
            try:
                # CORRECCIÓN DE RUTA S3
                path_s3 = f"s3://{BUCKET}/{folder.lstrip('/')}"
                print(f"📖 Leyendo de: {path_s3}")
                
                df = spark.read.option("header","true").csv(path_s3)
                if df.count() > 0:
                    clean_and_load(entidad, df)
                else:
                    print(f"❓ La carpeta {entidad} no contiene datos.")
            except Exception as e:
                print(f"❌ Error procesando {entidad}: {e}")

if not found_data:
    print(f"🛑 No se encontraron carpetas en {BRONZE_PREFIX}. Revisa la estructura en S3.")

job.commit()