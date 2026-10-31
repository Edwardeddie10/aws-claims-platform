import csv
from pathlib import Path

output = Path(__file__).resolve().parents[1] / "data/sample/claims.csv"
output.parent.mkdir(parents=True, exist_ok=True)

claims = [
    ["CLM001", "MEM001", "PRV001", "2026-10-01", "99213", "150.00"],
    ["CLM002", "MEM002", "PRV002", "2026-10-02", "99214", "225.00"],
    ["CLM003", "MEM003", "PRV001", "2026-10-03", "80053", "85.50"],
]

with output.open("w", newline="", encoding="utf-8") as file:
    writer = csv.writer(file)
    writer.writerow([
        "claim_id", "member_id", "provider_id",
        "service_date", "procedure_code", "claim_amount"
    ])
    writer.writerows(claims)

print(f"Created {output} with {len(claims)} synthetic claims.")