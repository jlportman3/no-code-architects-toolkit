#!/bin/bash
set -e

ENV_FILE=.env

# Create .env if not present
if [ ! -f "$ENV_FILE" ]; then
    echo "Creating $ENV_FILE from sample"
    cp .env.sample "$ENV_FILE"
fi

# Ensure API key
API_KEY=$(grep '^API_KEY=' "$ENV_FILE" | cut -d'=' -f2)
if [ -z "$API_KEY" ] || [ "$API_KEY" = "your_api_key" ]; then
    API_KEY=$(python3 generate_api_key.py)
    sed -i "s/^API_KEY=.*/API_KEY=$API_KEY/" "$ENV_FILE"
fi

echo "Using API_KEY=$API_KEY"

# Load environment variables
set -o allexport
source "$ENV_FILE"
set +o allexport

# Build and start services

docker compose build

docker compose up -d

# Wait for MinIO to be ready
until curl -s "http://localhost:9000/minio/health/ready" >/dev/null; do
    echo "Waiting for MinIO..."
    sleep 2
done

echo "MinIO is ready"

# Create bucket via boto3 inside ncat container
cat <<'PY' | docker compose exec -T ncat python -
import boto3, os, botocore
endpoint=os.environ['S3_ENDPOINT_URL']
access=os.environ['S3_ACCESS_KEY']
secret=os.environ['S3_SECRET_KEY']
region=os.environ.get('S3_REGION','us-east-1')
bucket=os.environ['S3_BUCKET_NAME']
s3=boto3.client('s3',endpoint_url=endpoint,aws_access_key_id=access,aws_secret_access_key=secret,region_name=region)
try:
    s3.head_bucket(Bucket=bucket)
    print('Bucket already exists')
except botocore.exceptions.ClientError:
    s3.create_bucket(Bucket=bucket)
    print('Bucket created')
PY

# Wait for NCAT to be ready
until curl -s "http://localhost:8081" >/dev/null; do
    echo "Waiting for NCAT..."
    sleep 2
done

echo "NCAT is ready"

# Health check
curl -H "x-api-key: $API_KEY" http://localhost:8081/v1/toolkit/test
