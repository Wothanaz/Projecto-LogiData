import boto3
import json
import time
import random
from datetime import datetime

# Configuración
STREAM_NAME = 'logidata-sensor-stream-jsge'
REGION = 'us-east-1'

# Cliente de Kinesis
kinesis_client = boto3.client('kinesis', region_name=REGION)

def enviar_datos(id_vehiculo, temperatura):
    payload = {
        'vehiculo': id_vehiculo,
        'timestamp': int(time.time()),
        'temperatura': temperatura,
        'latitud': random.uniform(-12.0, -12.1),
        'longitud': random.uniform(-77.0, -77.1),
        'estado': 'En ruta'
    }
    
    print(f"Enviando: {payload}")
    
    response = kinesis_client.put_record(
        StreamName=STREAM_NAME,
        Data=json.dumps(payload),
        PartitionKey=id_vehiculo
    )
    return response

# Simulador en bucle
try:
    print(f"--- Simulador LogiData Iniciado (Stream: {STREAM_NAME}) ---")
    while True:
        # Camión 1: Temperatura Normal
        enviar_datos('CAMION-001', random.uniform(15.0, 18.0))
        
        # Camión 2: ¡ALERTA DE TEMPERATURA! (Para probar el SNS)
        enviar_datos('CAMION-002', random.uniform(22.0, 26.0))
        
        time.sleep(5) # Envía datos cada 5 segundos
except KeyboardInterrupt:
    print("\nSimulador detenido por el usuario.")