import boto3
import os

# Configuración
BUCKET_NAME = "logidata-datalake-jsge"
# Apuntamos a la carpeta raíz 'data' desde la ubicación del script
LOCAL_DATA_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../data/"))
# Archivo que NO queremos subir
IGNORE_FILE = "diccionario_datos.csv"

def upload_to_bronze():
    # Inicializar cliente de S3
    s3 = boto3.client('s3')
    
    print(f"--- Iniciando Carga Automática a {BUCKET_NAME} ---")
    
    # Listar todos los archivos en la carpeta /data/
    try:
        files = [f for f in os.listdir(LOCAL_DATA_PATH) if f.endswith('.csv')]
    except FileNotFoundError:
        print(f"❌ Error: No se encontró la carpeta en {LOCAL_DATA_PATH}")
        return

    for file_name in files:
        # Lógica de exclusión
        if file_name == IGNORE_FILE:
            print(f"🚫 Saltando {file_name} (Lista negra)...")
            continue
            
        local_file_path = os.path.join(LOCAL_DATA_PATH, file_name)
        s3_key = f"bronze/{file_name}"
        
        try:
            print(f"📤 Subiendo {file_name} -> {s3_key}...")
            s3.upload_file(local_file_path, BUCKET_NAME, s3_key)
            print(f"✅ {file_name} cargado con éxito.")
        except Exception as e:
            print(f"❌ Error al subir {file_name}: {e}")

if __name__ == "__main__":
    upload_to_bronze()