import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, when, dayofmonth, month, year, current_timestamp, to_timestamp

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

def clean_and_load(entity_name, df_raw):
    print(f"--- Procesando Entidad: {entity_name} ---")
    df_audit = df_raw.withColumn("processed_at", AHORA)

    if entity_name == "clientes":
        zonas_validas = ['Norte', 'Sur', 'Oriente', 'Occidente', 'Centro']
        df_clean = df_audit.select(
            col("id_cliente").cast("string"),
            col("nombre").cast("string"),
            col("zona").cast("string"),
            col("tipo_cliente").cast("string"),
            "processed_at"
        ).filter(col("id_cliente").isNotNull() & col("zona").isin(zonas_validas))
        partition_cols = None

    elif entity_name == "catalogo":
        df_clean = df_audit.select(
            col("id_producto").cast("string"),
            col("categoria").cast("string"),
            col("precio").cast("float"),
            col("tipo_entrega").cast("string"),
            "processed_at"
        ).filter((col("id_producto").isNotNull()) & (col("precio") > 0))
        partition_cols = None

    elif entity_name == "pedidos":
        df_base = df_audit.select(
            col("id_pedido").cast("string"),
            col("id_cliente").cast("string"),
            col("id_producto").cast("string"),
            to_timestamp(col("fecha"), FMT).alias("fecha_ts"),
            col("monto").cast("float"),
            col("estado").cast("string"),
            "processed_at"
        ).filter((col("id_pedido").isNotNull()) & (col("monto") > 0))
        
        df_clean = df_base.withColumn("year", year("fecha_ts")) \
                          .withColumn("month", month("fecha_ts")) \
                          .withColumn("day", dayofmonth("fecha_ts"))
        partition_cols = ["year", "month", "day"]

    elif entity_name == "entregas":
        df_base = df_audit.select(
            col("id_pedido").cast("string"),
            to_timestamp(col("hora_programada"), FMT).alias("hora_prog_ts"),
            to_timestamp(col("hora_real"), FMT).alias("hora_real_ts"),
            col("conductor").cast("string"),
            col("vehiculo").cast("string"),
            "processed_at"
        ).filter(col("id_pedido").isNotNull() & col("vehiculo").isNotNull())
        
        df_clean = df_base.withColumn("year", year("hora_prog_ts")) \
                          .withColumn("month", month("hora_prog_ts")) \
                          .withColumn("day", dayofmonth("hora_prog_ts"))
        partition_cols = ["year", "month", "day"]

    # Escritura
    silver_path = f"s3://{BUCKET}/silver/{entity_name}"
    writer = df_clean.write.mode("overwrite").format("parquet")
    if partition_cols:
        writer = writer.partitionBy(*partition_cols)
    
    print(f"DEBUG: Guardando {df_clean.count()} registros en {silver_path}")
    writer.save(silver_path)

# --- EJECUCIÓN ---
entidades = ["clientes", "catalogo", "pedidos", "entregas"]
for entidad in entidades:
    try:
        # CAMBIO CLAVE: Apuntamos al archivo .csv directamente según tu imagen de S3
        path_bronze = f"s3://{BUCKET}/bronze/{entidad}.csv" 
        
        df_raw = spark.read.option("header", "true").option("inferSchema", "true").csv(path_bronze)
        print(f"DEBUG: {entidad} - Registros leídos: {df_raw.count()}")
        clean_and_load(entidad, df_raw)
    except Exception as e:
        print(f"❌ Error en {entidad}: {str(e)}")

job.commit()