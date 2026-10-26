"""Prefect flow: download NHTSA files -> load raw -> dbt run -> dbt test."""
import os
import subprocess
import sys
import zipfile
from pathlib import Path

import requests
from dotenv import load_dotenv
from prefect import flow, task, get_run_logger

from load_raw import main as load_raw_main

ROOT = Path(__file__).resolve().parent.parent
BULK = ROOT / "data" / "bulk"
DBT_DIR = ROOT / "transform"

BASE_URL = "https://static.nhtsa.gov/odi/ffdd"
FILES = [
    "cmpl/COMPLAINTS_RECEIVED_2020-2024.zip",
    "cmpl/COMPLAINTS_RECEIVED_2025-2026.zip",
    "rcl/FLAT_RCL_POST_2010.zip",
    "inv/FLAT_INV.zip",
    "cmpl/CMPL.txt",
    "rcl/RCL.txt",
    "inv/INV.txt",
]


@task(retries=3, retry_delay_seconds=60)
def download_file(rel_path: str) -> str:
    logger = get_run_logger()
    BULK.mkdir(parents=True, exist_ok=True)
    dest = BULK / Path(rel_path).name
    with requests.get(f"{BASE_URL}/{rel_path}", stream=True, timeout=120) as r:
        r.raise_for_status()
        with open(dest, "wb") as f:
            for chunk in r.iter_content(chunk_size=1 << 20):
                f.write(chunk)
    if dest.suffix == ".zip":
        with zipfile.ZipFile(dest) as z:
            z.extractall(BULK)
        dest.unlink()
    logger.info(f"downloaded {dest.name}")
    return dest.name


@task
def load_raw() -> None:
    if load_raw_main() != 0:
        raise RuntimeError("raw load failed reconciliation: row counts don't match source files")


def run_dbt(command: str) -> None:
    logger = get_run_logger()
    result = subprocess.run(
        ["dbt", command], cwd=DBT_DIR, env=os.environ.copy(), capture_output=True, text=True
    )
    for line in result.stdout.splitlines()[-15:]:
        logger.info(line)
    if result.returncode != 0:
        raise RuntimeError(f"dbt {command} failed")


@task(retries=1, retry_delay_seconds=30)
def dbt_run() -> None:
    run_dbt("run")


@task
def dbt_test() -> None:
    run_dbt("test")


@flow(name="vehicle-safety-pipeline", log_prints=True)
def pipeline(download: bool = True) -> None:
    load_dotenv(ROOT / ".env")
    if download:
        for rel_path in FILES:
            download_file(rel_path)
    load_raw()
    dbt_run()
    dbt_test()


if __name__ == "__main__":
    pipeline(download="--no-download" not in sys.argv)