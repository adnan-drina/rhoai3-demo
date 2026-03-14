#!/bin/bash
# Upload a local file to MinIO S3 via port-forward + Python boto3.
# Usage: ./upload-to-minio.sh <local-file> <s3-path>
#   e.g. ./upload-to-minio.sh scenario-docs/acme/doc.pdf rag-documents/acme/doc.pdf

set -euo pipefail

LOCAL_FILE="${1:?Usage: $0 <local-file> <s3-path>}"
S3_PATH="${2:?Usage: $0 <local-file> <s3-path>}"
MINIO_NS="minio-storage"

if [ ! -f "$LOCAL_FILE" ]; then
    echo "ERROR: File not found: $LOCAL_FILE"
    exit 1
fi

BUCKET=$(echo "$S3_PATH" | cut -d/ -f1)
OBJECT_KEY=$(echo "$S3_PATH" | cut -d/ -f2-)
FILENAME=$(basename "$LOCAL_FILE")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MINIO_KEY=$(oc -n "$MINIO_NS" get secret minio-credentials \
    -o jsonpath='{.data.MINIO_ROOT_USER}' | base64 -d 2>/dev/null)
MINIO_SECRET=$(oc -n "$MINIO_NS" get secret minio-credentials \
    -o jsonpath='{.data.MINIO_ROOT_PASSWORD}' | base64 -d 2>/dev/null)

if [ -z "$MINIO_KEY" ] || [ -z "$MINIO_SECRET" ]; then
    echo "ERROR: Could not read MinIO credentials from $MINIO_NS/minio-credentials"
    exit 1
fi

# Ensure port-forward is running (reuse if already active)
if ! lsof -i :19000 &>/dev/null; then
    oc port-forward svc/minio -n "$MINIO_NS" 19000:9000 &>/dev/null &
    PF_PID=$!
    sleep 2
    # Store PID for cleanup by caller
    echo "$PF_PID" > /tmp/.minio-pf-pid
else
    PF_PID=""
fi

VENV_PATH="$REPO_ROOT/.venv-kfp"
if [ ! -d "$VENV_PATH" ]; then
    python3 -m venv "$VENV_PATH"
fi
"$VENV_PATH/bin/pip" install -q boto3 2>/dev/null

echo "Uploading $FILENAME -> s3://$S3_PATH"

"$VENV_PATH/bin/python3" -c "
import boto3
from botocore.config import Config
s3 = boto3.client('s3',
    endpoint_url='http://localhost:19000',
    aws_access_key_id='$MINIO_KEY',
    aws_secret_access_key='$MINIO_SECRET',
    config=Config(signature_version='s3v4'))
try:
    s3.head_bucket(Bucket='$BUCKET')
except:
    s3.create_bucket(Bucket='$BUCKET')
s3.upload_file('$LOCAL_FILE', '$BUCKET', '$OBJECT_KEY')
print('  Done: s3://$S3_PATH')
"
