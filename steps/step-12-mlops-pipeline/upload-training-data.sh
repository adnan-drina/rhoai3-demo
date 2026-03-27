#!/bin/bash
# =============================================================================
# Upload training photos, unknown faces, and test images to MinIO.
#
# The pipeline's prepare_dataset component reads from:
#   s3://face-training-photos/adnan/     (selfie photos — class 0)
#   s3://face-training-photos/unknown/   (colleague photos — class 1)
#   s3://face-training-photos/test-images/ (test images for evaluation)
#
# Usage: ./upload-training-data.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

PHOTOS_DIR="$REPO_ROOT/steps/step-11-face-recognition/notebooks/my_photos"
UNKNOWN_DIR="$REPO_ROOT/steps/step-11-face-recognition/notebooks/unknown_face"
IMAGES_DIR="$REPO_ROOT/steps/step-11-face-recognition/notebooks/images"
NAMESPACE="private-ai"

check_oc_logged_in

log_step "Uploading training data to MinIO..."

# Read MinIO credentials from cluster secret
export MINIO_ACCESS_KEY=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
export MINIO_SECRET_KEY=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

# Port-forward MinIO
oc port-forward -n minio-storage svc/minio 9000:9000 &>/dev/null &
PF_PID=$!
sleep 3

cleanup() { kill $PF_PID 2>/dev/null || true; }
trap cleanup EXIT

VENV_PATH="$REPO_ROOT/.venv-kfp"
if [ ! -d "$VENV_PATH" ]; then
    python3 -m venv "$VENV_PATH"
    "$VENV_PATH/bin/pip" install -q --upgrade pip boto3
else
    "$VENV_PATH/bin/pip" install -q boto3 2>/dev/null
fi

export PHOTOS_DIR UNKNOWN_DIR IMAGES_DIR

"$VENV_PATH/bin/python3" << 'PYEOF'
import os, boto3
from pathlib import Path
from botocore.config import Config

PHOTOS_DIR = Path(os.environ["PHOTOS_DIR"])
UNKNOWN_DIR = Path(os.environ["UNKNOWN_DIR"])
IMAGES_DIR = Path(os.environ["IMAGES_DIR"])

s3 = boto3.client("s3",
    endpoint_url="http://localhost:9000",
    aws_access_key_id=os.environ["MINIO_ACCESS_KEY"],
    aws_secret_access_key=os.environ["MINIO_SECRET_KEY"],
    config=Config(signature_version="s3v4"))

BUCKET = "face-training-photos"

try:
    s3.head_bucket(Bucket=BUCKET)
except Exception:
    s3.create_bucket(Bucket=BUCKET)
    print(f"Created bucket: {BUCKET}")

def upload_dir(local_dir, s3_prefix):
    files = sorted(local_dir.glob("*.jpeg")) + sorted(local_dir.glob("*.jpg")) + sorted(local_dir.glob("*.png"))
    for f in files:
        s3.upload_file(str(f), BUCKET, f"{s3_prefix}/{f.name}")
    return len(files)

n = upload_dir(PHOTOS_DIR, "adnan")
print(f"Uploaded {n} selfie photos -> s3://{BUCKET}/adnan/")

if UNKNOWN_DIR.exists():
    n = upload_dir(UNKNOWN_DIR, "unknown")
    print(f"Uploaded {n} unknown photos -> s3://{BUCKET}/unknown/")
else:
    print("No unknown_face directory — pipeline will fall back to LFW")

n = upload_dir(IMAGES_DIR, "test-images")
print(f"Uploaded {n} test images -> s3://{BUCKET}/test-images/")

print(f"\nAll data uploaded to s3://{BUCKET}/")
PYEOF

log_success "Training data uploaded to MinIO"
