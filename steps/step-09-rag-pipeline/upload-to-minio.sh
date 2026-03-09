#!/bin/bash
# Upload a local file to MinIO via a temporary pod.
# Usage: ./upload-to-minio.sh <local-file> <s3-path>
#   e.g. ./upload-to-minio.sh scenario-docs/scenario2-acme/doc.pdf rag-documents/scenario2-acme/doc.pdf

set -euo pipefail

LOCAL_FILE="${1:?Usage: $0 <local-file> <s3-path>}"
S3_PATH="${2:?Usage: $0 <local-file> <s3-path>}"
NAMESPACE="private-ai"
MINIO_NS="minio-storage"

if [ ! -f "$LOCAL_FILE" ]; then
    echo "ERROR: File not found: $LOCAL_FILE"
    exit 1
fi

BUCKET=$(echo "$S3_PATH" | cut -d/ -f1)
OBJECT_KEY=$(echo "$S3_PATH" | cut -d/ -f2-)

MINIO_KEY=$(oc -n "$MINIO_NS" get secret minio-credentials \
    -o jsonpath='{.data.MINIO_ROOT_USER}' | base64 -d 2>/dev/null)
MINIO_SECRET=$(oc -n "$MINIO_NS" get secret minio-credentials \
    -o jsonpath='{.data.MINIO_ROOT_PASSWORD}' | base64 -d 2>/dev/null)

if [ -z "$MINIO_KEY" ] || [ -z "$MINIO_SECRET" ]; then
    echo "ERROR: Could not read MinIO credentials from $MINIO_NS/minio-credentials"
    exit 1
fi

FILENAME=$(basename "$LOCAL_FILE")
ENDPOINT="http://minio.$MINIO_NS.svc:9000"

echo "Uploading $FILENAME -> s3://$S3_PATH"

# Base64-encode file content for transport via env var in small pod
FILE_B64=$(base64 < "$LOCAL_FILE")

oc -n "$MINIO_NS" run "mc-upload-$(date +%s)" \
    --rm -i --restart=Never \
    --image=quay.io/minio/mc \
    --env="HOME=/tmp" \
    --env="AK=$MINIO_KEY" \
    --env="SK=$MINIO_SECRET" \
    --env="ENDPOINT=$ENDPOINT" \
    --env="BUCKET=$BUCKET" \
    --env="OBJECT_KEY=$OBJECT_KEY" \
    --env="FILE_B64=$FILE_B64" \
    -- bash -c '
mkdir -p /tmp/.mc
export MC_CONFIG_DIR=/tmp/.mc
echo "$FILE_B64" | base64 -d > /tmp/upload_file
mc alias set myminio "$ENDPOINT" "$AK" "$SK" --api S3v4 >/dev/null 2>&1
mc mb --ignore-existing myminio/"$BUCKET" >/dev/null 2>&1
mc cp /tmp/upload_file myminio/"$BUCKET"/"$OBJECT_KEY"
echo "OK"
' 2>/dev/null

echo "  Done: s3://$S3_PATH"
