#!/bin/bash
# =============================================================================
# Upload training photos and test images to MinIO for the pipeline.
#
# The pipeline's prepare_dataset component reads from:
#   s3://face-training-photos/adnan/     (selfie photos)
#   s3://face-training-photos/test-images/ (test images for evaluation)
#
# Usage: ./upload-training-data.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

PHOTOS_DIR="$REPO_ROOT/steps/step-11-face-recognition/notebooks/my_photos"
IMAGES_DIR="$REPO_ROOT/steps/step-11-face-recognition/notebooks/images"
NAMESPACE="private-ai"

check_oc_logged_in

log_step "Uploading training data to MinIO..."

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

export PHOTOS_DIR IMAGES_DIR

"$VENV_PATH/bin/python3" << 'PYEOF'
import os, boto3
from pathlib import Path
from botocore.config import Config

PHOTOS_DIR = Path(os.environ["PHOTOS_DIR"])
IMAGES_DIR = Path(os.environ["IMAGES_DIR"])

s3 = boto3.client("s3",
    endpoint_url="http://localhost:9000",
    aws_access_key_id="rhoai-access-key",
    aws_secret_access_key="rhoai-secret-key-12345",
    config=Config(signature_version="s3v4"))

BUCKET = "face-training-photos"

# Ensure bucket exists
try:
    s3.head_bucket(Bucket=BUCKET)
except Exception:
    s3.create_bucket(Bucket=BUCKET)
    print(f"Created bucket: {BUCKET}")

# Upload selfie photos
photos = sorted(PHOTOS_DIR.glob("*.jpeg")) + sorted(PHOTOS_DIR.glob("*.jpg")) + sorted(PHOTOS_DIR.glob("*.png"))
print(f"Uploading {len(photos)} training photos -> s3://{BUCKET}/adnan/")
for p in photos:
    s3.upload_file(str(p), BUCKET, f"adnan/{p.name}")
print(f"  Done: {len(photos)} photos")

# Upload test images
images = sorted(IMAGES_DIR.glob("*.jpg"))
print(f"Uploading {len(images)} test images -> s3://{BUCKET}/test-images/")
for img in images:
    s3.upload_file(str(img), BUCKET, f"test-images/{img.name}")
print(f"  Done: {len(images)} images")

print(f"\nAll data uploaded to s3://{BUCKET}/")
PYEOF

log_success "Training data uploaded to MinIO"
