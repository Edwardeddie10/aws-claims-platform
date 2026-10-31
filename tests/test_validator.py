
import io
import sys
import unittest
from pathlib import Path

# Import the existing validator from src/lambda
PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "src" / "lambda"))

from validator import validate_claims, REQUIRED_COLUMNS


class TestClaimsValidator(unittest.TestCase):

    def make_csv(self, rows):
        header = ",".join(REQUIRED_COLUMNS)
        return io.StringIO(header + "\n" + rows)

    def test_valid_claim(self):
        file = self.make_csv(
            "C001,M001,P001,2026-10-01,99213,150.00\n"
        )
        result = validate_claims(file)

        self.assertTrue(result["valid"])
        self.assertEqual(result["claim_count"], 1)
        self.assertEqual(result["errors"], [])

    def test_missing_required_column(self):
        file = io.StringIO(
            "claim_id,member_id,provider_id,service_date,claim_amount\n"
            "C001,M001,P001,2026-10-01,150.00\n"
        )
        result = validate_claims(file)

        self.assertFalse(result["valid"])
        self.assertIn("Missing columns", result["errors"][0])

    def test_blank_required_field(self):
        file = self.make_csv(
            "C001,,P001,2026-10-01,99213,150.00\n"
        )
        result = validate_claims(file)

        self.assertFalse(result["valid"])
        self.assertTrue(
            any("member_id is blank" in e for e in result["errors"])
        )

    def test_invalid_service_date(self):
        file = self.make_csv(
            "C001,M001,P001,10/01/2026,99213,150.00\n"
        )
        result = validate_claims(file)

        self.assertFalse(result["valid"])
        self.assertTrue(
            any("service_date must be YYYY-MM-DD" in e
                for e in result["errors"])
        )

    def test_negative_claim_amount(self):
        file = self.make_csv(
            "C001,M001,P001,2026-10-01,99213,-50.00\n"
        )
        result = validate_claims(file)

        self.assertFalse(result["valid"])
        self.assertTrue(
            any("claim_amount must be a positive number" in e
                for e in result["errors"])
        )

    def test_empty_claims_file(self):
        file = self.make_csv("")
        result = validate_claims(file)

        self.assertFalse(result["valid"])
        self.assertEqual(result["claim_count"], 0)
        self.assertIn("File contains no claims.", result["errors"])

    def test_multiple_valid_claims(self):
        file = self.make_csv(
            "C001,M001,P001,2026-10-01,99213,150.00\n"
            "C002,M002,P002,2026-10-02,99214,200.00\n"
        )
        result = validate_claims(file)

        self.assertTrue(result["valid"])
        self.assertEqual(result["claim_count"], 2)


if __name__ == "__main__":
    unittest.main()
