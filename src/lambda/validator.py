import csv
from datetime import date
from decimal import Decimal, InvalidOperation
from pathlib import Path
import sys

REQUIRED_COLUMNS = [
    "claim_id",
    "member_id",
    "provider_id",
    "service_date",
    "procedure_code",
    "claim_amount",
]


def validate_claims(file):
    reader = csv.DictReader(file)
    errors = []
    count = 0

    missing = set(REQUIRED_COLUMNS) - set(reader.fieldnames or [])
    if missing:
        return {
            "valid": False,
            "claim_count": 0,
            "errors": [f"Missing columns: {', '.join(sorted(missing))}"],
        }

    for row_number, row in enumerate(reader, start=2):
        count += 1

        for column in REQUIRED_COLUMNS:
            if not (row.get(column) or "").strip():
                errors.append(f"Row {row_number}: {column} is blank.")

        service_date = (row.get("service_date") or "").strip()
        try:
            parsed = date.fromisoformat(service_date)
            if parsed.isoformat() != service_date:
                raise ValueError
        except ValueError:
            errors.append(
                f"Row {row_number}: service_date must be YYYY-MM-DD."
            )

        try:
            amount = Decimal((row.get("claim_amount") or "").strip())
            if not amount.is_finite() or amount <= 0:
                raise InvalidOperation
        except InvalidOperation:
            errors.append(
                f"Row {row_number}: claim_amount must be a positive number."
            )

    if count == 0:
        errors.append("File contains no claims.")

    return {
        "valid": not errors,
        "claim_count": count,
        "errors": errors,
    }


if __name__ == "__main__":
    import json

    path = Path(sys.argv[1])
    with path.open(newline="", encoding="utf-8-sig") as file:
        result = validate_claims(file)

    print(json.dumps(result, indent=2))
    sys.exit(0 if result["valid"] else 1)