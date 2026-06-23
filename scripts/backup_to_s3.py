#!/usr/bin/env python3
"""
backup_to_s3.py — Hourly MySQL dump → S3 (encrypted at rest by bucket policy)
CCS6344 Assignment 2 — Bonus: Data Protection via S3 versioned backups

Run via cron on EC2:
  0 * * * * source /opt/minilib/.env && python3 /opt/minilib/scripts/backup_to_s3.py

Uses LabRole IAM permissions — no access key needed (instance profile handles auth).
"""

import os
import subprocess
import datetime
import boto3
from botocore.exceptions import ClientError

# Config from environment variables (set by CloudFormation UserData)
DB_HOST   = os.environ['DB_HOST']
DB_NAME   = os.environ['DB_NAME']
DB_USER   = os.environ.get('BACKUP_DB_USER', 'lib_admin')
DB_PASS   = os.environ['DB_PASSWORD']
BUCKET    = os.environ['BACKUP_BUCKET']
REGION    = os.environ.get('AWS_DEFAULT_REGION', 'us-east-1')

def create_backup():
    timestamp  = datetime.datetime.utcnow().strftime('%Y%m%d_%H%M%S')
    filename   = f'minilib_backup_{timestamp}.sql.gz'
    local_path = f'/tmp/{filename}'
    s3_key     = f'db-backups/{filename}'

    # mysqldump + gzip in a single pipeline
    dump_cmd = (
        f'mysqldump --host={DB_HOST} --user={DB_USER} '
        f'--password={DB_PASS} --ssl-mode=REQUIRED '
        f'--single-transaction --routines --triggers {DB_NAME}'
    )

    print(f'[{timestamp}] Starting backup of {DB_NAME}...')

    with open(local_path, 'wb') as f:
        dump  = subprocess.Popen(dump_cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        gzip  = subprocess.Popen(['gzip', '-9'], stdin=dump.stdout, stdout=f)
        dump.stdout.close()
        gzip.communicate()

    if dump.returncode and dump.returncode != 0:
        print(f'mysqldump failed: {dump.stderr.read().decode()}')
        return False

    size_mb = os.path.getsize(local_path) / 1024 / 1024
    print(f'Backup created: {local_path} ({size_mb:.2f} MB)')

    # Upload to S3 — bucket has SSE-AES256 enforced by bucket policy
    s3 = boto3.client('s3', region_name=REGION)
    try:
        s3.upload_file(
            local_path, BUCKET, s3_key,
            ExtraArgs={
                'ServerSideEncryption': 'AES256',
                'StorageClass': 'STANDARD_IA',   # cheaper for infrequent-access backups
            }
        )
        print(f'Uploaded to s3://{BUCKET}/{s3_key}')
    except ClientError as e:
        print(f'S3 upload failed: {e}')
        return False
    finally:
        os.remove(local_path)    # clean up temp file

    return True


if __name__ == '__main__':
    success = create_backup()
    exit(0 if success else 1)
