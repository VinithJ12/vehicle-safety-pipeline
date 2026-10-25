"""Load raw NHTSA flat files into Postgres (raw schema), with reconciliation checks."""
import os
import re
import sys
import time
from pathlib import Path

import duckdb
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
BULK = ROOT / "data" / "bulk"

DATASETS = {
    "complaints": {
        "dictionary": "CMPL.txt",
        "files": ["COMPLAINTS_RECEIVED_2020-2024.txt", "COMPLAINTS_RECEIVED_2025-2026.txt"],
    },
    "recalls": {"dictionary": "RCL.txt", "files": ["FLAT_RCL_POST_2010.txt"]},
    "investigations": {"dictionary": "INV.txt", "files": ["FLAT_INV.txt"]},
}

FIELD_LINE = re.compile(r"^\s*(\d+)\s+([A-Z][A-Z0-9_]*)\s")


def parse_dictionary(path: Path) -> list[str]:
    """Pull field names out of an NHTSA data dictionary, in order."""
    fields = []
    for line in path.read_text(errors="replace").splitlines():
        match = FIELD_LINE.match(line)
        if match:
            fields.append((int(match.group(1)), match.group(2).lower()))
    numbers = [n for n, _ in fields]
    if numbers != list(range(1, len(numbers) + 1)):
        raise ValueError(f"{path.name}: field numbers aren't 1..N in order: {numbers}")
    return [name for _, name in fields]


def count_columns(path: Path) -> int:
    with open(path, "rb") as f:
        first = f.readline().decode("utf-8", errors="replace").rstrip("\r\n")
    return len(first.split("\t"))


def count_lines(path: Path) -> int:
    with open(path, "rb") as f:
        return sum(1 for _ in f)


def main() -> int:
    load_dotenv(ROOT / ".env")
    pg_conn = (
        f"host=localhost port={os.environ['POSTGRES_PORT']} "
        f"dbname={os.environ['POSTGRES_DB']} "
        f"user={os.environ['POSTGRES_USER']} "
        f"password={os.environ['POSTGRES_PASSWORD']}"
    )

    con = duckdb.connect()
    con.execute("INSTALL postgres; LOAD postgres;")
    con.execute(f"ATTACH '{pg_conn}' AS pg (TYPE postgres)")
    con.execute("CALL postgres_execute('pg', 'CREATE SCHEMA IF NOT EXISTS raw')")

    all_ok = True
    for table, spec in DATASETS.items():
        start = time.time()
        cols = parse_dictionary(BULK / spec["dictionary"])
        paths = [BULK / f for f in spec["files"]]

        for p in paths:
            n = count_columns(p)
            if n != len(cols):
                raise ValueError(f"{p.name} has {n} columns but {spec['dictionary']} lists {len(cols)}")

        expected = sum(count_lines(p) for p in paths)
        file_list = [str(p) for p in paths]

        con.execute(f"DROP TABLE IF EXISTS pg.raw.{table}")
        con.execute(f"""
            CREATE TABLE pg.raw.{table} AS
            SELECT * EXCLUDE (filename),
                   filename          AS _source_file,
                   current_timestamp AS _loaded_at
            FROM read_csv({file_list},
                          delim = '\t', header = false, quote = '', escape = '',
                          all_varchar = true, names = {cols}, filename = true)
        """)

        actual = con.sql(f"SELECT COUNT(*) FROM pg.raw.{table}").fetchall()[0][0]
        ok = actual == expected
        all_ok = all_ok and ok
        status = "OK" if ok else "MISMATCH"
        print(f"[{status}] raw.{table}: {actual:,} rows loaded / {expected:,} lines in files "
              f"({len(cols)} cols, {time.time() - start:.1f}s)")

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())