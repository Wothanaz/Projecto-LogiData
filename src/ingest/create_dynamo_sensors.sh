aws dynamodb create-table \
    --table-name LogiData_Sensors \
    --attribute-definitions \
        AttributeName=vehiculo,AttributeType=S \
        AttributeName=timestamp,AttributeType=N \
    --key-schema \
        AttributeName=vehiculo,KeyType=HASH \
        AttributeName=timestamp,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST