import io
import json
from urllib.parse import unquote_plus

import boto3

from validator import validate_claims

s3 = boto3.client("s3")
glue = boto3.client("glue")

GLUE_JOB_NAME = "claims-platform-dev-transform"


def lambda_handler(event, context):
    results = []

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = unquote_plus(record["s3"]["object"]["key"])

        if not key.startswith("incoming/") or not key.endswith(".csv"):
            continue

        response = s3.get_object(Bucket=bucket, Key=key)

        try:
            content = response["Body"].read().decode("utf-8-sig")
        finally:
            response["Body"].close()

        with io.StringIO(content, newline="") as file:
            result = validate_claims(file)

        destination = "validated" if result["valid"] else "quarantine"
        destination_key = f"{destination}/{key.removeprefix('incoming/')}"

        s3.copy_object(
            Bucket=bucket,
            Key=destination_key,
            CopySource={"Bucket": bucket, "Key": key},
        )

        summary = {
            "bucket": bucket,
            "key": key,
            "destination_key": destination_key,
            **result,
        }

        if result["valid"]:
            run = glue.start_job_run(
                JobName=GLUE_JOB_NAME,
                JobRunQueuingEnabled=True,
            )
            summary["glue_job_run_id"] = run["JobRunId"]

        print(json.dumps(summary))
        results.append(summary)

    return {"results": results}