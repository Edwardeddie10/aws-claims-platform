import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql.functions import col, trim, to_date
from pyspark.sql.types import DecimalType

args = getResolvedOptions(
    sys.argv,
    ["JOB_NAME", "INPUT_PATH", "OUTPUT_PATH"],
)

glue_context = GlueContext(SparkContext.getOrCreate())
spark = glue_context.spark_session

job = Job(glue_context)
job.init(args["JOB_NAME"], args)

# Read validated CSV files. Keep identifiers as strings.
claims = (
    spark.read
    .option("header", "true")
    .option("inferSchema", "false")
    .csv(args["INPUT_PATH"])
)

claims = claims.select(
    trim(col("claim_id")).alias("claim_id"),
    trim(col("member_id")).alias("member_id"),
    trim(col("provider_id")).alias("provider_id"),
    to_date(trim(col("service_date")), "yyyy-MM-dd").alias("service_date"),
    trim(col("procedure_code")).alias("procedure_code"),
    trim(col("claim_amount")).cast(DecimalType(18, 2)).alias("claim_amount"),
)

# Rebuild the curated dataset on each run for this lab.
claims.write.mode("overwrite").parquet(args["OUTPUT_PATH"])

job.commit()