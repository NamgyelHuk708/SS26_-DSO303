#!/bin/bash
# Uploads a transcript to S3 using ONLY the instance's IAM role — no access
# keys are read, stored, or referenced anywhere in this script.
set -euo pipefail

STUDENT_ID="${1:-}"
FILE_PATH="${2:-}"

if [ -z "$STUDENT_ID" ] || [ -z "$FILE_PATH" ]; then
  echo "Usage: $0 <student-id> <file-path>" >&2
  exit 1
fi

if [ ! -f "$FILE_PATH" ]; then
  echo "Error: file not found: $FILE_PATH" >&2
  exit 1
fi

FILENAME=$(basename "$FILE_PATH")
BUCKET="${USMS_BUCKET_NAME:-usms-student-data}"
KEY="transcripts/${STUDENT_ID}/${FILENAME}"

echo "Uploading $FILE_PATH -> s3://${BUCKET}/${KEY} (via instance profile, no keys)"
aws s3 cp "$FILE_PATH" "s3://${BUCKET}/${KEY}"
echo "Upload complete."
