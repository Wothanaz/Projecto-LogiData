import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, when, to_timestamp, lit

# --- INICIALIZACIÓN DE GLUE ---
# Estas líneas son obligatorias para que AWS Glue gestione el ciclo de vida del job
args = getResolvedOptions(sys.argv, ['JOB_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# --- CONFIGURACIÓN ---
# Usamos el bucket que definimos en Terraform
BUCKET = "logidata-datalake-jsge"

def process_silver():
    print("Iniciando transformación Bronze a Silver (HU13 - Calidad de Datos)...")

    # --- 1. PROCESAR CLIENTES ---
    # Limpieza: Filtramos zonas válidas según el diccionario de LogiData
    df_clientes = spark.read.option("header", "true").csv(f"s3://{BUCKET}/bronze/clientes.csv")
    df_clientes_clean = df_clientes.select(
        col("id_cliente").cast("string"),
        col("nombre").cast("string"),
        col("zona").cast("string"),
        col("tipo_cliente").cast("string")
    ).filter(col("zona").isin('Norte', 'Sur', 'Oriente', 'Occidente', 'Centro'))
    
    df_clientes_clean.write.mode("overwrite").parquet(f"s3://{BUCKET}/silver/clientes")
    print("Capa Silver: Clientes procesada.")

    # --- 2. PROCESAR CATALOGO ---
    # Limpieza: Validamos que el precio sea positivo (Regla de negocio)
    df_catalogo = spark.read.option("header", "true").csv(f"s3://{BUCKET}/bronze/catalogo.csv")
    df_catalogo_clean = df_catalogo.select(
        col("id_producto").cast("string"),
        col("categoria").cast("string"),
        col("precio").cast("float"),
        col("tipo_entrega").cast("string")
    ).filter(col("precio") > 0)
    
    df_catalogo_clean.write.mode("overwrite").parquet(f"s3://{BUCKET}/silver/catalogo")
    print("Capa Silver: Catálogo procesada.")

    # --- 3. PROCESAR PEDIDOS ---
    # Limpieza: Conversión estricta a tipos datetime y float
    df_pedidos = spark.read.option("header", "true").csv(f"s3://{BUCKET}/bronze/pedidos.csv")
    df_pedidos_clean = df_pedidos.select(
        col("id_pedido").cast("string"),
        col("id_cliente").cast("string"),
        col("id_producto").cast("string"),
        to_timestamp(col("fecha")).alias("fecha"),
        col("monto").cast("float"),
        col("estado").cast("string")
    )
    
    df_pedidos_clean.write.mode("overwrite").parquet(f"s3://{BUCKET}/silver/pedidos")
    print("Capa Silver: Pedidos procesada.")

    # --- 4. PROCESAR ENTREGAS ---
    # Limpieza: Estandarización de tiempos para análisis de puntualidad
    df_entregas = spark.read.option("header", "true").csv(f"s3://{BUCKET}/bronze/entregas.csv")
    df_entregas_clean = df_entregas.select(
        col("id_pedido").cast("string"),
        to_timestamp(col("hora_programada")).alias("hora_programada"),
        to_timestamp(col("hora_real")).alias("hora_real"),
        col("zona").cast("string"),
        col("conductor").cast("string"),
        col("vehiculo").cast("string")
    )
    
    df_entregas_clean.write.mode("overwrite").parquet(f"s3://{BUCKET}/silver/entregas")
    print("Capa Silver: Entregas procesada.")

    print("Pipeline Bronze a Silver completado con éxito respetando el Diccionario de Datos.")

if __name__ == "__main__":
    process_silver()
    # Finaliza el Job de Glue correctamente
    job.commit()