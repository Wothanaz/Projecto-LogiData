import base64
import json
import boto3
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

def handler(event, context):
    table_name = os.environ.get('TABLE_NAME')
    counter_table_name = os.environ.get('COUNTER_TABLE_NAME') # Nueva tabla para el conteo
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    
    table = dynamodb.Table(table_name)
    counter_table = dynamodb.Table(counter_table_name)
    
    for record in event['Records']:
        try:
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            data = json.loads(payload, parse_float=Decimal)
            vehiculo = data['vehiculo']
            evento = data.get('evento')

            # --- LÓGICA DE CONTEO CONSECUTIVO ---
            
            # 1. Obtener el contador actual del vehículo
            response = counter_table.get_item(Key={'vehiculo': vehiculo})
            item = response.get('Item', {'vehiculo': vehiculo, 'consecutivos': 0})
            current_count = int(item['consecutivos'])

            if evento == 'TEMP_CRITICA':
                new_count = current_count + 1
                print(f"⚠️ {vehiculo} - Lectura crítica detectada ({new_count}/5)")
                
                # 2. Si llegamos a 5, enviamos correo
                if new_count == 5:
                    mensaje = f"EMERGENCIA: El vehículo {vehiculo} ha reportado 5 lecturas críticas CONSECUTIVAS."
                    sns.publish(TopicArn=topic_arn, Message=mensaje, Subject=f"🚨 ALERTA PERSISTENTE: {vehiculo}")
                    # Opcional: reiniciar a 0 o dejar que siga subiendo
                    new_count = 0 
            else:
                # 3. Si el evento es 'OK' o cualquier otro, se rompe la racha
                new_count = 0
            
            # 4. Actualizar el contador en DynamoDB
            counter_table.put_item(Item={'vehiculo': vehiculo, 'consecutivos': new_count})

            # --- GUARDAR EN TABLA PRINCIPAL Y CONTINUAR ---
            data['processed_by'] = 'Lambda_JSGE_Consecutivos'
            table.put_item(Item=data)
            
        except Exception as e:
            print(f"Error: {str(e)}")
            
    return {'statusCode': 200}