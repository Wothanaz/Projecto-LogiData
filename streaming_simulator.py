import boto3
import json
import time
import csv
import os

# Configuración
STREAM_NAME = 'logidata-sensor-stream-jsge'
REGION = 'us-east-1'

# Detectar ruta automática: Carpeta 'data' -> archivo 'sensor_data.csv'
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_FILE = os.path.join(BASE_DIR, 'data', 'sensores.csv') 

# Cliente de Kinesis
kinesis_client = boto3.client('kinesis', region_name=REGION)

def enviar_todo_el_csv():
    try:
        print(f"🚀 Iniciando simulador dinámico...")
        print(f"📂 Cargando archivo: {CSV_FILE}")
        
        with open(CSV_FILE, mode='r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            
            for row in reader:
                # 1. Creamos el payload con todos los campos originales del CSV
                # Usamos una comprensión de diccionario para limpiar espacios en blanco
                payload = {k.strip(): v.strip() for k, v in row.items()}
                
                # 2. Conversiones necesarias para que la Lambda y DynamoDB funcionen
                # (AWS requiere que lat/long/temp sean números para los cálculos)
                if 'temperatura' in payload:
                    payload['temperatura'] = float(payload['temperatura'])
                if 'latitud' in payload:
                    payload['latitud'] = float(payload['latitud'])
                if 'longitud' in payload:
                    payload['longitud'] = float(payload['longitud'])
                
                # 3. Forzamos un timestamp actual para que el flujo se vea vivo en AWS
                payload['timestamp'] = int(time.time())
                
                # 4. Enviar a Kinesis
                # Usamos el campo 'vehiculo' como PartitionKey para mantener el orden
                partition_key = payload.get('vehiculo', 'default_partition')
                
                kinesis_client.put_record(
                    StreamName=STREAM_NAME,
                    Data=json.dumps(payload),
                    PartitionKey=partition_key
                )
                
                print(f"✅ Enviado: {payload}")
                
                # Pausa para simular tiempo real
                time.sleep(0.3)

        print("\n✅ Fin del archivo. Todos los datos han sido enviados.")

    except FileNotFoundError:
        print(f"❌ Error: No se encontró el archivo en {CSV_FILE}")
    except Exception as e:
        print(f"❌ Error inesperado: {e}")

if __name__ == "__main__":
    enviar_todo_el_csv()