import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F

# --- INICIALIZACIÓN ---
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'bucket_name'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

bucket = args['bucket_name']

# --- 1. CARGA CON RENOMBRADO PREVENTIVO ---
# Renombramos 'year' y 'zona' para que cada tabla tenga nombres ÚNICOS
pedidos = glueContext.create_dynamic_frame.from_catalog(
    database="logidata_silver_db", table_name="pedidos"
).toDF().withColumnRenamed("year", "p_year").withColumnRenamed("month", "p_month").withColumnRenamed("day", "p_day")

entregas = glueContext.create_dynamic_frame.from_catalog(
    database="logidata_silver_db", table_name="entregas"
).toDF().withColumnRenamed("year", "e_year").withColumnRenamed("month", "e_month").withColumnRenamed("day", "e_day") \
        .withColumnRenamed("zona", "e_zona") # <--- SOLUCIÓN PARA ZONA

clientes = glueContext.create_dynamic_frame.from_catalog(
    database="logidata_silver_db", table_name="clientes"
).toDF().withColumnRenamed("zona", "c_zona") # <--- SOLUCIÓN PARA ZONA

catalogo = glueContext.create_dynamic_frame.from_catalog(database="logidata_silver_db", table_name="catalogo").toDF()
sensores = glueContext.create_dynamic_frame.from_catalog(database="logidata_silver_db", table_name="sensores").toDF()

# --- 2. AGREGACIÓN DE SENSORES ---
sensores_agg = sensores.groupBy("s_vehiculo", "s_year", "s_month", "s_day").agg(
    F.avg("temperatura").alias("temp_promedio_dia"),
    F.count(F.when(F.col("evento") == "Alerta", 1)).alias("total_alertas_dia")
)

# --- 3. JOINS SEGUROS ---
# Paso A: Pedidos + Clientes + Catálogo (usamos c_zona para evitar conflictos)
df_step1 = pedidos.join(clientes, "id_cliente").join(catalogo, "id_producto")

# Paso B: Unimos con Entregas (Usamos e_zona para evitar conflictos)
df_batch = df_step1.join(entregas, "id_pedido")

# Paso C: Join con Sensores
df_fact_maestra = df_batch.join(
    sensores_agg,
    (df_batch["vehiculo"] == sensores_agg["s_vehiculo"]) & 
    (df_batch["p_year"] == sensores_agg["s_year"]) & 
    (df_batch["p_month"] == sensores_agg["s_month"]) & 
    (df_batch["p_day"] == sensores_agg["s_day"]),
    "left"
)

# --- 4. SELECCIÓN FINAL (LIMPIEZA DE NOMBRES) ---
# Aquí decidimos que la 'zona' oficial de Gold será la de la entrega (e_zona)
df_final = df_fact_maestra.select(
    "id_pedido", 
    "monto", 
    "conductor", 
    "vehiculo", 
    F.col("e_zona").alias("zona"), 
    "temp_promedio_dia", 
    "total_alertas_dia",
    F.col("p_year").alias("year"),
    F.col("p_month").alias("month"),
    F.col("p_day").alias("day")
)

# --- 5. ESCRITURA ---
path_gold = f"s3://{bucket}/gold/fact_ventas_calidad/"

df_final.write.mode("overwrite") \
    .partitionBy("year", "month", "day") \
    .parquet(path_gold)

# Dimensión de conductores
df_final.select("conductor", "vehiculo", "zona").distinct() \
    .write.mode("overwrite").parquet(f"s3://{bucket}/gold/dim_conductores/")

job.commit()