import json
import os
import shutil
import subprocess
import tempfile
import unittest

from fganalysis_mcp import server


def _rscript_has_fganalysis() -> bool:
    rscript = server.RSCRIPT
    if not shutil.which(rscript):
        return False
    result = subprocess.run(
        [rscript, "-e", "library(fganalysis, quietly=TRUE)"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    return result.returncode == 0


_RSCRIPT_WITH_FGANALYSIS = _rscript_has_fganalysis()


class ServerJsonParsingTests(unittest.TestCase):
    def test_parse_json_from_clean_stdout(self) -> None:
        payload = server._parse_json_from_stdout('{"status": "success", "value": 1}')

        self.assertEqual(payload["status"], "success")
        self.assertEqual(payload["value"], 1)

    def test_parse_json_from_noisy_r_stdout(self) -> None:
        payload = server._parse_json_from_stdout(
            'loading connections\nQuerying lab measurements...\n{"status": "success"}'
        )

        self.assertEqual(payload["status"], "success")

    def test_parse_json_rejects_missing_payload(self) -> None:
        with self.assertRaises(server.WrapperOutputError):
            server._parse_json_from_stdout("loading connections only")


class ServerPathTests(unittest.TestCase):
    def test_normalise_output_path_returns_absolute_path(self) -> None:
        path = server._normalise_output_path("relative-output.tsv")

        self.assertTrue(path.endswith("relative-output.tsv"))
        self.assertTrue(path.startswith("/"))

    def test_json_response_is_valid_json(self) -> None:
        encoded = server._json_response({"status": "success"})

        self.assertEqual(json.loads(encoded)["status"], "success")


@unittest.skipUnless(
    _RSCRIPT_WITH_FGANALYSIS,
    "Rscript with fganalysis package is required for R wrapper tests "
    f"(set RSCRIPT_PATH env var if R is not on PATH; current: {server.RSCRIPT!r})",
)
class OfflineRWrapperTests(unittest.TestCase):
    """Smoke tests that exercise R wrappers which do not need a FinnGen connection."""

    def test_inspect_environment_reports_required_exports(self) -> None:
        payload = json.loads(server.inspect_fganalysis_environment())

        self.assertEqual(payload.get("status"), "success")
        required = payload.get("required_exports_present", {})
        self.assertTrue(required, "expected at least one required export entry")
        self.assertTrue(all(required.values()), required)

    def test_atc_code_relationships_returns_list_fields(self) -> None:
        payload = json.loads(
            server.get_atc_code_relationships(
                ["A10BJ", "C10AA01"], include_hierarchical=False, require_mapping=False
            )
        )

        self.assertEqual(payload.get("status"), "success")
        self.assertIsInstance(payload["expanded_codes"], list)
        self.assertGreaterEqual(len(payload["expanded_codes"]), 2)

    def test_process_variance_files_creates_qnorm_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            variance_path = os.path.join(tmpdir, "L1_variance.tsv")
            with open(variance_path, "w", encoding="utf-8") as handle:
                handle.write("FID\tIID\tL1_variance\n")
                for i, value in enumerate([0.1, 0.2, 0.5, 1.0, 2.0, 3.0, 5.0, 8.0]):
                    handle.write(f"FG{i}\tFG{i}\t{value}\n")

            payload = json.loads(server.process_variance_files(output_dir=tmpdir))

            self.assertEqual(payload.get("status"), "success")
            self.assertEqual(payload.get("n_files_processed"), 1)
            self.assertIsInstance(payload["output_files"], list)
            self.assertEqual(len(payload["output_files"]), 1)


if __name__ == "__main__":
    unittest.main()
