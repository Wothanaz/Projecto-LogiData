import base64
import json
import boto3
import os
from decimal import Decimal 

# 1. Inicializar el recurso sin asignar la tabla aún para evitar errores de Init
dynamodb = boto3.resource('dynamodb')

def validate_quality(data):
    """
    Validación de Calidad de Datos.
    """
    required_fields = ['vehiculo', 'timestamp', 'temperatura', 'latitud', 'longitud', 'evento']
    
    if not all(field in data for field in required_fields):
        return False, "Faltan campos obligatorios"
    
    if not (-30 <= data['temperatura'] <= 80):
        return False, "Temperatura fuera de rango físico posible"
        
    return True, "OK"

def handler(event, context):
    # 2. Obtener variables dentro del handler para asegurar que existan
    table_name = os.environ.get('TABLE_NAME')
    table = dynamodb.Table(table_name)
    
    print(f"Recibidos {len(event['Records'])} registros de Kinesis.")
    
    for record in event['Records']:
        try:
            # 3. Decodificación
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            data = json.loads(payload, parse_float=Decimal)
            
            # 4. Control de Calidad
            is_valid, reason = validate_quality(data)
            if not is_valid:
                print(f"🚫 Registro descartado: {reason} | Datos: {data}")
                continue 
            
            # 5. Alerta de Temperatura (HU12) - SOLO PRINT, sin SNS
            if data.get('evento') == 'Temperatura_critica':
                print(f"⚠️ ¡ALERTA CRÍTICA DETECTADA! Vehículo: {data['vehiculo']} | Temp: {data['temperatura']}")
            
            # 6. Guardar en DynamoDB
            data['processed_by'] = 'Lambda_Streaming_JSGE'
            table.put_item(Item=data)
            
        except Exception as e:
            print(f"❌ Error procesando registro: {str(e)}")
            
    return {'statusCode': 200, 'body': 'Procesamiento completado'}