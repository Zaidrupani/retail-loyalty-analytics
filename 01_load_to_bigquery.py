"""
01_load_to_bigquery.py
Loads the dunnhumby Complete Journey CSVs into BigQuery.

Before running:
  1. pip install google-cloud-bigquery
  2. Sign in once from a terminal:  gcloud auth application-default login
  3. Set PROJECT_ID below to your own BigQuery project ID.
     The CSVs go in the data/ folder next to this script.
  4. Open each CSV's header row in Notepad and check the column order
     matches the schemas below. BigQuery maps columns by POSITION.

causal_data.csv is left out for now (very large, not needed yet).
Sandbox note: tables expire after 60 days. Re-run this script to rebuild.
"""

from pathlib import Path
from google.cloud import bigquery
from google.cloud.exceptions import NotFound

# ---------------------------------------------------------------------
# Settings: change these two
# ---------------------------------------------------------------------
PROJECT_ID = "retail-loyalty"                # from the BigQuery console
DATA_DIR = Path(__file__).resolve().parent / "data"  # the data folder next to this script

DATASET_ID = "complete_journey"
LOCATION = "EU"

F = bigquery.SchemaField

# ---------------------------------------------------------------------
# Table schemas (column order must match each CSV)
# ---------------------------------------------------------------------
TABLES = {
    # Core sales table: one row per product per basket
    "transaction_data": [
        F("household_key", "INT64", mode="REQUIRED"),
        F("basket_id", "INT64", mode="REQUIRED"),
        F("day", "INT64", mode="REQUIRED", description="Day number, not a date"),
        F("product_id", "INT64", mode="REQUIRED"),
        F("quantity", "INT64"),
        # Money columns are loaded as FLOAT64 because the source CSV contains
        # floating-point noise such as 5.551115E-17 (effectively zero), which
        # NUMERIC rejects. They are rounded to 2 dp in the cleaned layer.
        F("sales_value", "FLOAT64", description="Amount the retailer received"),
        F("store_id", "INT64"),
        F("retail_disc", "FLOAT64", description="Loyalty card discount, stored as NEGATIVE"),
        F("trans_time", "INT64", description="HHMM, e.g. 1631"),
        F("week_no", "INT64"),
        F("coupon_disc", "FLOAT64", description="Manufacturer coupon discount, NEGATIVE"),
        F("coupon_match_disc", "FLOAT64", description="Retailer match on coupon, NEGATIVE"),
    ],
    # Household demographics (only a subset of households have a row)
    "hh_demographic": [
        F("age_desc", "STRING"),
        F("marital_status_code", "STRING"),
        F("income_desc", "STRING"),
        F("homeowner_desc", "STRING"),
        F("hh_comp_desc", "STRING"),
        F("household_size_desc", "STRING", description="Includes values like '5+'"),
        F("kid_category_desc", "STRING"),
        F("household_key", "INT64", mode="REQUIRED"),
    ],
    # Product master
    "product": [
        F("product_id", "INT64", mode="REQUIRED"),
        F("manufacturer", "INT64"),
        F("department", "STRING"),
        F("brand", "STRING", description="'National' or 'Private' (own-label)"),
        F("commodity_desc", "STRING"),
        F("sub_commodity_desc", "STRING"),
        F("curr_size_of_product", "STRING"),
    ],
    # Campaigns: which households received which campaign
    "campaign_table": [
        F("description", "STRING", description="TypeA / TypeB / TypeC"),
        F("household_key", "INT64", mode="REQUIRED"),
        F("campaign", "INT64", mode="REQUIRED"),
    ],
    "campaign_desc": [
        F("description", "STRING"),
        F("campaign", "INT64", mode="REQUIRED"),
        F("start_day", "INT64"),
        F("end_day", "INT64"),
    ],
    # Coupons and redemptions
    "coupon": [
        F("coupon_upc", "INT64", mode="REQUIRED"),
        F("product_id", "INT64", mode="REQUIRED"),
        F("campaign", "INT64", mode="REQUIRED"),
    ],
    "coupon_redempt": [
        F("household_key", "INT64", mode="REQUIRED"),
        F("day", "INT64"),
        F("coupon_upc", "INT64", mode="REQUIRED"),
        F("campaign", "INT64", mode="REQUIRED"),
    ],
}


def ensure_dataset(client: bigquery.Client) -> None:
    """Create the dataset if it does not exist yet."""
    dataset_ref = f"{PROJECT_ID}.{DATASET_ID}"
    try:
        client.get_dataset(dataset_ref)
        print(f"Dataset {dataset_ref} already exists")
    except NotFound:
        dataset = bigquery.Dataset(dataset_ref)
        dataset.location = LOCATION
        client.create_dataset(dataset)
        print(f"Created dataset {dataset_ref} in {LOCATION}")


def load_table(client: bigquery.Client, table_name: str, schema: list) -> None:
    """Load one CSV into BigQuery, replacing the table if it exists."""
    csv_path = DATA_DIR / f"{table_name}.csv"
    if not csv_path.exists():
        print(f"SKIPPED {table_name}: {csv_path} not found")
        return

    table_id = f"{PROJECT_ID}.{DATASET_ID}.{table_name}"
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,
        schema=schema,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )

    print(f"Loading {table_name} ...")
    with open(csv_path, "rb") as f:
        job = client.load_table_from_file(f, table_id, job_config=job_config)

    try:
        job.result()  # wait for the load to finish
    except Exception:
        print(f"FAILED {table_name}")
        for err in job.errors or []:
            print("   ", err)
        raise

    table = client.get_table(table_id)
    print(f"  {table_name}: {table.num_rows:,} rows")


def main() -> None:
    client = bigquery.Client(project=PROJECT_ID, location=LOCATION)
    ensure_dataset(client)
    for table_name, schema in TABLES.items():
        load_table(client, table_name, schema)
    print("Done.")


if __name__ == "__main__":
    main()
