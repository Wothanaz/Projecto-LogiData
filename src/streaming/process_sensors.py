import base64
import json
import boto3
import os
from decimal import Decimal # <--- 1. Importación necesaria para DynamoDB

# Inicializar clientes fuera del handler para reutilizar conexiones
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

# Variables de entorno configuradas en Terraform
TABLE_NAME = os.environ.get('TABLE_NAME')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')

table = dynamodb.Table(TABLE_NAME)

def validate_quality(data):
    """
    HU13: Validación de Calidad de Datos.
    """
    required_fields = ['vehiculo', 'timestamp', 'temperatura', 'latitud', 'longitud']
    
    # 1. Verificar existencia de campos
    if not all(field in data for field in required_fields):
        return False, "Faltan campos obligatorios"
    
    # 2. Validar rangos lógicos de temperatura
    if not (-30 <= data['temperatura'] <= 50):
        return False, "Temperatura fuera de rango físico posible"
        
    return True, "OK"

def handler(event, context):
    print(f"Recibidos {len(event['Records'])} registros de Kinesis.")
    
    for record in event['Records']:
        try:
            # 1. Decodificar el dato de Kinesis
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            
            # 2. El truco: parse_float=Decimal convierte los floats automáticamente
            # Esto soluciona el error: "Float types are not supported"
            data = json.loads(payload, parse_float=Decimal)
            
            # 3. Control de Calidad (HU13)
            is_valid, reason = validate_quality(data)
            
            if not is_valid:
                print(f"🚫 Registro descartado: {reason} | Datos: {data}")
                continue 
            
            # 4. Alerta de Temperatura (HU12)
            if data['temperatura'] > 8.0:
                print(f"⚠️ ¡ALERTA DE TEMPERATURA! Vehículo: {data['vehiculo']} Temp: {data['temperatura']}")
                sns.publish(
                    TopicArn=SNS_TOPIC_ARN,
                    Message=f"🚨 ALERTA LOGIDATA:\n\nEl vehículo {data['vehiculo']} registra una temperatura crítica de {data['temperatura']}°C.\nTimestamp: {data['timestamp']}\nUbicación: {data['latitud']}, {data['longitud']}",
                    Subject="⚠️ Crítico: Alerta de Cadena de Frío"
                )
            
            # 5. Guardar en DynamoDB
            data['processed_by'] = 'Lambda_Streaming_JSGE'
            table.put_item(Item=data)
            
        except Exception as e:
            # Ahora este print nos mostrará si hay algún otro detalle
            print(f"❌ Error procesando registro: {str(e)}")
            
    return {'statusCode': 200, 'body': 'Procesamiento completado'}