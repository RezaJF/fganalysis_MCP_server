import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

from fganalysis_mcp import server


COMMON_R = pathlib.Path(__file__).resolve().parents[1] / "r_wrappers" / "common.R"


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


@unittest.skipUnless(
    shutil.which(server.RSCRIPT),
    f"Rscript is required for call_supported tests (current: {server.RSCRIPT!r})",
)
class CallSupportedTests(unittest.TestCase):
    """Regression tests for the call_supported() formals-guard helper.

    These tests do NOT require fganalysis to be installed — they source
    common.R into a fresh Rscript process, define a local stub function
    with a restricted formals list, and verify the helper's behaviour
    against that stub. This is exactly the situation a user with an
    upstream-master fganalysis (lacking FINNGEN/fganalysis-r#30) lands
    in: the named arg `use_atc_mapping` should be silently dropped and
    a notice surfaced via `message()`.
    """

    def _run_r(self, body: str) -> subprocess.CompletedProcess:
        script = (
            f'source("{COMMON_R.as_posix()}")\n'
            f"{body}\n"
        )
        return subprocess.run(
            [server.RSCRIPT, "-e", script],
            capture_output=True,
            text=True,
            timeout=30,
        )

    def test_drops_unsupported_named_arg_and_returns_value(self) -> None:
        result = self._run_r(
            """
            stub <- function(x, y) x + y
            value <- call_supported(stub, x = 2, y = 3, use_atc_mapping = TRUE)
            cat(sprintf("VALUE=%d", value))
            """
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("VALUE=5", result.stdout)
        # message() output goes to stderr in R; helper must announce the drop
        self.assertIn("use_atc_mapping", result.stderr)
        self.assertIn("dropping", result.stderr)

    def test_passes_supported_arg_through_unchanged(self) -> None:
        result = self._run_r(
            """
            stub <- function(x, y, use_atc_mapping = FALSE) {
              if (use_atc_mapping) x * y else x + y
            }
            value <- call_supported(stub, x = 2, y = 3, use_atc_mapping = TRUE)
            cat(sprintf("VALUE=%d", value))
            """
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        # Supported arg is forwarded -> stub uses multiplication branch
        self.assertIn("VALUE=6", result.stdout)
        # No drop message should be emitted for a supported arg
        self.assertNotIn("dropping", result.stderr)

    def test_preserves_positional_args(self) -> None:
        result = self._run_r(
            """
            stub <- function(first, second) paste(first, second, sep = "::")
            value <- call_supported(
              stub,
              "alpha", "beta",
              use_atc_mapping = TRUE
            )
            cat(sprintf("VALUE=%s", value))
            """
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("VALUE=alpha::beta", result.stdout)
        self.assertIn("use_atc_mapping", result.stderr)

    def test_drops_multiple_unsupported_args(self) -> None:
        result = self._run_r(
            """
            stub <- function(x) x * 10
            value <- call_supported(
              stub,
              x = 4,
              use_atc_mapping = TRUE,
              require_mapping = FALSE,
              future_param = "ignored"
            )
            cat(sprintf("VALUE=%d", value))
            """
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("VALUE=40", result.stdout)
        for dropped in ("use_atc_mapping", "require_mapping", "future_param"):
            self.assertIn(dropped, result.stderr)

    def test_simulates_upstream_master_get_drug_purchases(self) -> None:
        """Reproduces the exact scenario from issue #1.

        Simulates the upstream FINNGEN/fganalysis-r master branch's
        get_drug_purchases (whose formals do NOT include use_atc_mapping,
        because that param ships in unmerged PR #30) and drives it with
        the exact call pattern used inside get_drug_purchases.R. The
        wrapper must complete successfully, deliver the supported args
        verbatim to the upstream stub, and emit a stderr notice for the
        dropped use_atc_mapping.
        """
        result = self._run_r(
            """
            # Stub mirrors upstream-master get_drug_purchases formals.
            # Critically, no use_atc_mapping parameter.
            upstream_master_get_drug_purchases <- function(
              conn,
              druglist,
              finngen_ids = NULL,
              use_only_reimbursement = FALSE,
              lazy = TRUE
            ) {
              list(
                conn_label = "fake_conn",
                druglist = druglist,
                finngen_ids = finngen_ids,
                use_only_reimbursement = use_only_reimbursement,
                lazy = lazy
              )
            }

            # Exact call pattern from get_drug_purchases.R post-fix.
            result <- call_supported(
              upstream_master_get_drug_purchases,
              "fake_conn_obj",
              druglist = c("A10BJ", "C10AA01"),
              finngen_ids = NULL,
              use_only_reimbursement = FALSE,
              use_atc_mapping = TRUE,
              lazy = TRUE
            )

            stopifnot(identical(result$druglist, c("A10BJ", "C10AA01")))
            stopifnot(identical(result$lazy, TRUE))
            stopifnot(identical(result$use_only_reimbursement, FALSE))
            cat("UPSTREAM_MASTER_OK")
            """
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("UPSTREAM_MASTER_OK", result.stdout)
        self.assertIn("use_atc_mapping", result.stderr)
        self.assertIn("dropping", result.stderr)
        # No other params should be reported as dropped
        self.assertNotIn("'druglist'", result.stderr)
        self.assertNotIn("'lazy'", result.stderr)


if __name__ == "__main__":
    unittest.main()
