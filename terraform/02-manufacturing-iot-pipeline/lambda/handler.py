import base64
import json
import os
import time
from datetime import datetime, timezone

import boto3

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")
sns = boto3.client("sns")

TABLE_NAME = os.environ["TABLE_NAME"]
BUCKET_NAME = os.environ["BUCKET_NAME"]
TOPIC_ARN = os.environ["TOPIC_ARN"]
THRESHOLD = float(os.environ.get("TEMP_THRESHOLD", "80"))

table = dynamodb.Table(TABLE_NAME)


def handler(event, context):
    # Kinesis 레코드를 처리해 DynamoDB(핫)와 S3(콜드)에 저장하고, 온도 임계치 초과 시 SNS로 알림을 발송
    processed = 0

    for record in event.get("Records", []):
        payload = base64.b64decode(record["kinesis"]["data"]).decode("utf-8")
        try:
            data = json.loads(payload)
        except json.JSONDecodeError:
            continue

        device_id = str(data.get("device_id", "unknown"))
        ts = int(data.get("timestamp", time.time()))
        temperature = float(data.get("temperature", 0))

        # Hot: 실시간 조회용 DynamoDB
        table.put_item(
            Item={
                "device_id": device_id,
                "timestamp": ts,
                "temperature": str(temperature),
                "payload": payload,
            }
        )

        # Cold: 원본 적재(S3), 날짜 파티션
        day = datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y/%m/%d")
        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=f"raw/{day}/{device_id}-{ts}.json",
            Body=payload.encode("utf-8"),
        )

        # Alert
        if temperature >= THRESHOLD:
            sns.publish(
                TopicArn=TOPIC_ARN,
                Subject=f"[ALERT] {device_id} 온도 임계치 초과",
                Message=f"device={device_id}, temperature={temperature}℃ (threshold={THRESHOLD}℃)",
            )

        processed += 1

    return {"processed": processed}
