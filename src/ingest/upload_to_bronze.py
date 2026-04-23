import boto3
import os

# Configuración
BUCKET_NAME = "logidata-datalake-jsge"
# Apuntamos a la carpeta raíz 'data' desde la ubicación del script
LOCAL_DATA_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../data/"))
# Archivos que NO queremos subir
IGNORE_FILES = ["diccionario_datos.csv", "sensores.csv"]

def upload_to_bronze():
    # Inicializar cliente de S3
    s3 = boto3.client('s3')
    
    print(f"--- Iniciando Carga Automática Organizada a {BUCKET_NAME} ---")
    
    # Listar todos los archivos en la carpeta /data/
    try:
        files = [f for f in os.listdir(LOCAL_DATA_PATH) if f.endswith('.csv')]
    except FileNotFoundError:
        print(f"❌ Error: No se encontró la carpeta en {LOCAL_DATA_PATH}")
        return

    for file_name in files:
        # Lógica de exclusión
        if file_name in IGNORE_FILES:
            print(f"🚫 Saltando {file_name} (Lista negra)...")
            continue
            
        # Creamos el nombre de la "subcarpeta" basada en el nombre del archivo (sin .csv)
        # Ejemplo: 'ventas.csv' -> subcarpeta 'ventas'
        table_folder = os.path.splitext(file_name)[0]
        
        local_file_path = os.path.join(LOCAL_DATA_PATH, file_name)
        
        # NUEVA ESTRUCTURA: bronze/batch/nombre_tabla/archivo.csv
        s3_key = f"bronze/batch/{table_folder}/{file_name}"
        
        try:
            print(f"📤 Subiendo {file_name} -> {s3_key}...")
            s3.upload_file(local_file_path, BUCKET_NAME, s3_key)
            print(f"✅ {file_name} cargado con éxito en su carpeta correspondiente.")
        except Exception as e:
            print(f"❌ Error al subir {file_name}: {e}")

if __name__ == "__main__":
    upload_to_bronze()