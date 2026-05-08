"""FastMCP server exposing the fganalysis R package to agentic workflows."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

from dotenv import load_dotenv
from mcp.server.fastmcp import FastMCP


load_dotenv()

mcp = FastMCP("fganalysis-mcp")

REPO_ROOT = Path(__file__).resolve().parents[1]
WRAPPER_DIR = REPO_ROOT / "r_wrappers"
RSCRIPT = os.environ.get("RSCRIPT_PATH", "Rscript")
DEFAULT_CONFIG_PATH = (
    Path(os.environ.get("FGANALYSIS_CONFIG_PATH", ""))
    if os.environ.get("FGANALYSIS_CONFIG_PATH")
    else (REPO_ROOT.parent / "fganalysis-r" / "config" / "db_config.json")
)


class FgAnalysisMcpError(RuntimeError):
    """Base exception for local MCP server failures."""


class WrapperOutputError(FgAnalysisMcpError):
    """Raised when an R wrapper does not return parseable JSON."""


def _json_response(payload: Dict[str, Any]) -> str:
    return json.dumps(payload, indent=2, sort_keys=True)


def _normalise_config_path(config_path: Optional[str]) -> str:
    raw_path = Path(config_path) if config_path else DEFAULT_CONFIG_PATH
    return str(raw_path.expanduser().resolve())


def _normalise_optional_path(path: Optional[str]) -> Optional[str]:
    if not path:
        return None
    return str(Path(path).expanduser().resolve())


def _normalise_output_path(path: str) -> str:
    return str(Path(path).expanduser().resolve())


def _parse_json_from_stdout(stdout: str) -> Dict[str, Any]:
    """Parse the last JSON object from stdout while tolerating R progress prints."""
    stripped = stdout.strip()
    if not stripped:
        raise WrapperOutputError("R wrapper returned no stdout")

    decoder = json.JSONDecoder()
    candidate_starts = [idx for idx, char in enumerate(stripped) if char == "{"]

    for start in reversed(candidate_starts):
        try:
            parsed, end = decoder.raw_decode(stripped[start:])
        except json.JSONDecodeError:
            continue
        trailing = stripped[start + end :].strip()
        if trailing:
            continue
        if not isinstance(parsed, dict):
            raise WrapperOutputError("R wrapper returned JSON that was not an object")
        return parsed

    raise WrapperOutputError("R wrapper stdout did not contain a parseable JSON object")


def run_r_wrapper(
    script_name: str,
    params: Dict[str, Any],
    *,
    timeout_seconds: int = 3600,
    require_config: bool = True,
) -> Dict[str, Any]:
    """Run an R wrapper script and return its structured JSON payload."""
    script_path = WRAPPER_DIR / script_name
    if not script_path.exists():
        return {
            "status": "error",
            "error_type": "server_configuration",
            "message": f"R wrapper script not found: {script_path}",
        }

    wrapper_params = dict(params)
    if require_config:
        wrapper_params["config_path"] = _normalise_config_path(
            wrapper_params.get("config_path")
        )

    try:
        completed = subprocess.run(
            [RSCRIPT, str(script_path), json.dumps(wrapper_params)],
            capture_output=True,
            check=False,
            text=True,
            timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired as exc:
        return {
            "status": "error",
            "error_type": "timeout",
            "message": f"R wrapper timed out after {timeout_seconds} seconds",
            "script": script_name,
            "stdout": exc.stdout or "",
            "stderr": exc.stderr or "",
        }
    except OSError as exc:
        return {
            "status": "error",
            "error_type": "execution",
            "message": f"Failed to execute Rscript: {exc}",
            "script": script_name,
        }

    try:
        payload = _parse_json_from_stdout(completed.stdout)
    except WrapperOutputError as exc:
        return {
            "status": "error",
            "error_type": "wrapper_output",
            "message": str(exc),
            "script": script_name,
            "returncode": completed.returncode,
            "stdout": completed.stdout,
            "stderr": completed.stderr,
        }

    if completed.returncode != 0 and payload.get("status") != "error":
        payload["status"] = "error"
        payload["error_type"] = "execution"
        payload["message"] = payload.get(
            "message", f"R wrapper exited with status {completed.returncode}"
        )

    if completed.stderr.strip():
        payload.setdefault("stderr", completed.stderr.strip())
    payload.setdefault("script", script_name)
    payload.setdefault("returncode", completed.returncode)
    return payload


@mcp.tool()
def inspect_fganalysis_environment(config_path: Optional[str] = None) -> str:
    """Inspect R, fganalysis, wrapper, and optional data-configuration status."""
    params: Dict[str, Any] = {}
    require_config = config_path is not None or DEFAULT_CONFIG_PATH.exists()
    if require_config:
        params["config_path"] = _normalise_config_path(config_path)

    result = run_r_wrapper(
        "inspect_fganalysis.R",
        params,
        timeout_seconds=120,
        require_config=require_config,
    )
    return _json_response(result)


@mcp.tool()
def validate_fganalysis_config(config_path: Optional[str] = None) -> str:
    """Validate a fganalysis JSON data connection config before running analyses."""
    result = run_r_wrapper(
        "validate_config.R",
        {"config_path": _normalise_config_path(config_path)},
        timeout_seconds=120,
    )
    return _json_response(result)


@mcp.tool()
def run_drug_response_analysis(
    lab_id: List[str],
    drug_codes: List[str],
    output_prefix: str,
    before_window: Optional[List[float]] = None,
    after_window: Optional[List[float]] = None,
    filter_min_max: Optional[List[float]] = None,
    use_lab_free_text_values: bool = True,
    use_only_reimbursement_drugs: bool = False,
    use_atc_mapping: bool = True,
    remove_outliers_sd: Optional[float] = None,
    finngen_ids: Optional[List[str]] = None,
    create_upset_plot: bool = False,
    config_path: Optional[str] = None,
    timeout_seconds: int = 7200,
) -> str:
    """Create a fganalysis drug-response object and write summary artefacts."""
    params: Dict[str, Any] = {
        "lab_id": lab_id,
        "drug_codes": drug_codes,
        "before_window": before_window or [-1, 0],
        "after_window": after_window or [0.25, 1],
        "output_prefix": _normalise_output_path(output_prefix),
        "use_lab_free_text_values": use_lab_free_text_values,
        "use_only_reimbursement_drugs": use_only_reimbursement_drugs,
        "use_atc_mapping": use_atc_mapping,
        "create_upset_plot": create_upset_plot,
        "timeout_seconds": timeout_seconds,
    }
    if filter_min_max is not None:
        params["filter_min_max"] = filter_min_max
    if remove_outliers_sd is not None:
        params["remove_outliers_sd"] = remove_outliers_sd
    if finngen_ids:
        params["finngen_ids"] = finngen_ids
    if config_path:
        params["config_path"] = config_path

    result = run_r_wrapper(
        "run_drug_response.R", params, timeout_seconds=timeout_seconds
    )
    return _json_response(result)


@mcp.tool()
def run_blup_analysis(
    lab_id: List[str],
    drug_codes: List[str],
    output_dir: str,
    months_before: float = 3,
    min_measurements: int = 2,
    include_sex: bool = False,
    use_freetext_values: bool = True,
    use_only_reimbursement: bool = False,
    use_atc_mapping: bool = True,
    remove_outliers_sd: Optional[float] = None,
    winsorize_pct: Optional[float] = None,
    calculate_qc: bool = True,
    save_model: bool = False,
    plot_blup_correlation: bool = False,
    output_file_prefix: Optional[str] = None,
    config_path: Optional[str] = None,
    timeout_seconds: int = 7200,
) -> str:
    """Calculate per-individual BLUP slopes for longitudinal lab measurements."""
    params: Dict[str, Any] = {
        "lab_id": lab_id,
        "drug_codes": drug_codes,
        "output_dir": _normalise_output_path(output_dir),
        "months_before": months_before,
        "min_measurements": min_measurements,
        "include_sex": include_sex,
        "use_freetext_values": use_freetext_values,
        "use_only_reimbursement": use_only_reimbursement,
        "use_atc_mapping": use_atc_mapping,
        "calculate_qc": calculate_qc,
        "save_model": save_model,
        "plot_blup_correlation": plot_blup_correlation,
    }
    if remove_outliers_sd is not None:
        params["remove_outliers_sd"] = remove_outliers_sd
    if winsorize_pct is not None:
        params["winsorize_pct"] = winsorize_pct
    if output_file_prefix:
        params["output_file_prefix"] = output_file_prefix
    if config_path:
        params["config_path"] = config_path

    result = run_r_wrapper(
        "run_blup_analysis.R", params, timeout_seconds=timeout_seconds
    )
    return _json_response(result)


@mcp.tool()
def get_lab_data_summary(
    lab_id: List[str],
    require_values: bool = True,
    use_freetext_values: bool = True,
    limit: int = 10,
    config_path: Optional[str] = None,
) -> str:
    """Return count and preview rows for selected OMOP lab concept IDs."""
    params: Dict[str, Any] = {
        "lab_id": lab_id,
        "require_values": require_values,
        "use_freetext_values": use_freetext_values,
        "limit": limit,
    }
    if config_path:
        params["config_path"] = config_path

    result = run_r_wrapper("get_lab_summary.R", params, timeout_seconds=600)
    return _json_response(result)


@mcp.tool()
def get_drug_purchases(
    drug_codes: List[str],
    finngen_ids: Optional[List[str]] = None,
    use_only_reimbursement: bool = False,
    use_atc_mapping: bool = True,
    limit: int = 10,
    config_path: Optional[str] = None,
) -> str:
    """Return count and preview rows for purchases matching ATC code prefixes."""
    params: Dict[str, Any] = {
        "drug_codes": drug_codes,
        "use_only_reimbursement": use_only_reimbursement,
        "use_atc_mapping": use_atc_mapping,
        "limit": limit,
    }
    if finngen_ids:
        params["finngen_ids"] = finngen_ids
    if config_path:
        params["config_path"] = config_path

    result = run_r_wrapper("get_drug_purchases.R", params, timeout_seconds=600)
    return _json_response(result)


@mcp.tool()
def get_first_drug_purchase(
    drug_codes: List[str],
    finngen_ids: Optional[List[str]] = None,
    use_only_reimbursement: bool = False,
    use_atc_mapping: bool = True,
    limit: int = 10,
    config_path: Optional[str] = None,
) -> str:
    """Return the first qualifying drug purchase per FINNGENID."""
    params: Dict[str, Any] = {
        "drug_codes": drug_codes,
        "use_only_reimbursement": use_only_reimbursement,
        "use_atc_mapping": use_atc_mapping,
        "limit": limit,
    }
    if finngen_ids:
        params["finngen_ids"] = finngen_ids
    if config_path:
        params["config_path"] = config_path

    result = run_r_wrapper(
        "get_first_drug_purchase.R", params, timeout_seconds=600
    )
    return _json_response(result)


@mcp.tool()
def get_measurements_before_drug(
    lab_id: List[str],
    drug_codes: List[str],
    months_before: float = 3,
    use_freetext_values: bool = True,
    use_only_reimbursement: bool = False,
    use_atc_mapping: bool = True,
    remove_outliers_sd: Optional[float] = None,
    winsorize_pct: Optional[float] = None,
    range_sd_filter: Optional[Dict[str, float]] = None,
    output_file: Optional[str] = None,
    limit: int = 10,
    config_path: Optional[str] = None,
    timeout_seconds: int = 7200,
) -> str:
    """Get pre-drug lab measurements (exposed and unexposed individuals)."""
    params: Dict[str, Any] = {
        "lab_id": lab_id,
        "drug_codes": drug_codes,
        "months_before": months_before,
        "use_freetext_values": use_freetext_values,
        "use_only_reimbursement": use_only_reimbursement,
        "use_atc_mapping": use_atc_mapping,
        "limit": limit,
    }
    if remove_outliers_sd is not None:
        params["remove_outliers_sd"] = remove_outliers_sd
    if winsorize_pct is not None:
        params["winsorize_pct"] = winsorize_pct
    if range_sd_filter:
        params["range_sd_filter"] = range_sd_filter
    if output_file:
        params["output_file"] = _normalise_output_path(output_file)
    if config_path:
        params["config_path"] = config_path

    result = run_r_wrapper(
        "get_measurements_before_drug.R",
        params,
        timeout_seconds=timeout_seconds,
    )
    return _json_response(result)


@mcp.tool()
def calculate_fixed_slopes(
    lab_id: List[str],
    drug_codes: List[str],
    output_dir: str,
    months_before: float = 3,
    min_measurements: int = 2,
    use_freetext_values: bool = True,
    use_only_reimbursement: bool = False,
    use_atc_mapping: bool = True,
    remove_outliers_sd: Optional[float] = None,
    winsorize_pct: Optional[float] = None,
    output_file_prefix: Optional[str] = None,
    config_path: Optional[str] = None,
    timeout_seconds: int = 7200,
) -> str:
    """Compute simple OLS slopes per individual as a fast BLUP-comparable baseline."""
    params: Dict[str, Any] = {
        "lab_id": lab_id,
        "drug_codes": drug_codes,
        "output_dir": _normalise_output_path(output_dir),
        "months_before": months_before,
        "min_measurements": min_measurements,
        "use_freetext_values": use_freetext_values,
        "use_only_reimbursement": use_only_reimbursement,
        "use_atc_mapping": use_atc_mapping,
    }
    if remove_outliers_sd is not None:
        params["remove_outliers_sd"] = remove_outliers_sd
    if winsorize_pct is not None:
        params["winsorize_pct"] = winsorize_pct
    if output_file_prefix:
        params["output_file_prefix"] = output_file_prefix
    if config_path:
        params["config_path"] = config_path

    result = run_r_wrapper(
        "calculate_fixed_slopes.R", params, timeout_seconds=timeout_seconds
    )
    return _json_response(result)


@mcp.tool()
def compute_drug_purchase_cadence(
    drug_codes: List[str],
    output_file: Optional[str] = None,
    gap_days: float = 30,
    use_pills_per_pack_only: bool = True,
    use_only_reimbursement: bool = False,
    use_atc_mapping: bool = True,
    n_workers: Optional[int] = None,
    limit: int = 25,
    config_path: Optional[str] = None,
    timeout_seconds: int = 7200,
) -> str:
    """Compute purchase intervals (cadence) for selected ATC codes per VNR."""
    params: Dict[str, Any] = {
        "drug_codes": drug_codes,
        "gap_days": gap_days,
        "use_pills_per_pack_only": use_pills_per_pack_only,
        "use_only_reimbursement": use_only_reimbursement,
        "use_atc_mapping": use_atc_mapping,
        "limit": limit,
    }
    if n_workers is not None:
        params["n_workers"] = n_workers
    if output_file:
        params["output_file"] = _normalise_output_path(output_file)
    if config_path:
        params["config_path"] = config_path

    result = run_r_wrapper(
        "compute_drug_purchase_cadence.R",
        params,
        timeout_seconds=timeout_seconds,
    )
    return _json_response(result)


@mcp.tool()
def plot_median_pre_drug_diagnostics(
    lab_id: List[str],
    drug_codes: List[str],
    output_dir: str,
    months_before: float = 1,
    remove_outliers_mad_th: float = 5,
    use_atc_mapping: bool = True,
    include_sex_covariates: bool = False,
    output_file_prefix: str = "",
    config_path: Optional[str] = None,
    timeout_seconds: int = 7200,
) -> str:
    """Plot before/after MAD-outlier-removal diagnostics for median pre-drug values."""
    params: Dict[str, Any] = {
        "lab_id": lab_id,
        "drug_codes": drug_codes,
        "output_dir": _normalise_output_path(output_dir),
        "months_before": months_before,
        "remove_outliers_mad_th": remove_outliers_mad_th,
        "use_atc_mapping": use_atc_mapping,
        "include_sex_covariates": include_sex_covariates,
        "output_file_prefix": output_file_prefix,
    }
    if config_path:
        params["config_path"] = config_path

    result = run_r_wrapper(
        "plot_median_pre_drug.R", params, timeout_seconds=timeout_seconds
    )
    return _json_response(result)


@mcp.tool()
def process_variance_files(
    output_dir: str,
    pattern: str = "_variance\\.tsv$",
    save_normalized: bool = True,
    generate_plots: bool = False,
    timeout_seconds: int = 1800,
) -> str:
    """Process *_variance.tsv files: add inverse-rank-normalised columns and summarise."""
    params: Dict[str, Any] = {
        "output_dir": _normalise_output_path(output_dir),
        "pattern": pattern,
        "save_normalized": save_normalized,
        "generate_plots": generate_plots,
    }

    result = run_r_wrapper(
        "process_variance_files.R",
        params,
        timeout_seconds=timeout_seconds,
        require_config=False,
    )
    return _json_response(result)


@mcp.tool()
def load_atc_mappings_info(
    custom_mapping_file: Optional[str] = None,
    error_if_not_found: bool = False,
    preview_limit: int = 10,
) -> str:
    """Inspect the active ATC mapping file (version, source URL, total entries, preview)."""
    params: Dict[str, Any] = {
        "error_if_not_found": error_if_not_found,
        "preview_limit": preview_limit,
    }
    normalised_mapping_file = _normalise_optional_path(custom_mapping_file)
    if normalised_mapping_file:
        params["custom_mapping_file"] = normalised_mapping_file

    result = run_r_wrapper(
        "load_atc_mappings.R",
        params,
        timeout_seconds=120,
        require_config=False,
    )
    return _json_response(result)


@mcp.tool()
def clear_atc_mappings_cache() -> str:
    """Clear the in-memory ATC mappings cache for `fganalysis`."""
    result = run_r_wrapper(
        "clear_atc_cache.R", {}, timeout_seconds=60, require_config=False
    )
    return _json_response(result)


@mcp.tool()
def plot_lab_distribution(
    lab_id: List[str],
    drug_codes: List[str],
    output_file: str,
    before_window: Optional[List[float]] = None,
    after_window: Optional[List[float]] = None,
    remove_outliers: bool = True,
    use_atc_mapping: bool = True,
    config_path: Optional[str] = None,
    timeout_seconds: int = 7200,
) -> str:
    """Generate a before/after lab-value distribution plot for selected drugs."""
    params: Dict[str, Any] = {
        "lab_id": lab_id,
        "drug_codes": drug_codes,
        "output_file": _normalise_output_path(output_file),
        "before_window": before_window or [-1, 0],
        "after_window": after_window or [0.25, 1],
        "remove_outliers": remove_outliers,
        "use_atc_mapping": use_atc_mapping,
    }
    if config_path:
        params["config_path"] = config_path

    result = run_r_wrapper(
        "plot_lab_distribution.R", params, timeout_seconds=timeout_seconds
    )
    return _json_response(result)


@mcp.tool()
def get_median_pre_drug_values(
    lab_id: List[str],
    drug_codes: List[str],
    output_dir: str,
    months_before: float = 1,
    remove_outliers_mad_th: Optional[float] = 5,
    use_atc_mapping: bool = True,
    output_file_prefix: str = "",
    config_path: Optional[str] = None,
    timeout_seconds: int = 7200,
) -> str:
    """Create GWAS-ready median pre-drug lab-value phenotype files."""
    params: Dict[str, Any] = {
        "lab_id": lab_id,
        "drug_codes": drug_codes,
        "output_dir": _normalise_output_path(output_dir),
        "months_before": months_before,
        "remove_outliers_mad_th": remove_outliers_mad_th,
        "use_atc_mapping": use_atc_mapping,
        "output_file_prefix": output_file_prefix,
    }
    if config_path:
        params["config_path"] = config_path

    result = run_r_wrapper(
        "run_median_pre_drug.R", params, timeout_seconds=timeout_seconds
    )
    return _json_response(result)


@mcp.tool()
def get_atc_code_relationships(
    atc_codes: List[str],
    include_hierarchical: bool = True,
    require_mapping: bool = False,
    custom_mapping_file: Optional[str] = None,
) -> str:
    """Inspect fganalysis ATC expansion and historical code relationships."""
    params: Dict[str, Any] = {
        "atc_codes": atc_codes,
        "include_hierarchical": include_hierarchical,
        "require_mapping": require_mapping,
    }
    normalised_mapping_file = _normalise_optional_path(custom_mapping_file)
    if normalised_mapping_file:
        params["custom_mapping_file"] = normalised_mapping_file

    result = run_r_wrapper(
        "get_atc_relationships.R",
        params,
        timeout_seconds=120,
        require_config=False,
    )
    return _json_response(result)


@mcp.tool()
def execute_r_code(
    code: str,
    config_path: Optional[str] = None,
    timeout_seconds: int = 300,
) -> str:
    """Execute ad hoc R code with `conn` and fganalysis exports in scope."""
    params: Dict[str, Any] = {"code": code}
    if config_path:
        params["config_path"] = config_path

    result = run_r_wrapper(
        "execute_r_code.R", params, timeout_seconds=timeout_seconds
    )
    return _json_response(result)


@mcp.tool()
def generate_analysis_notebook(goal: str, output_path: str) -> str:
    """Generate a Jupyter notebook for a fganalysis analysis goal."""
    try:
        from .notebook_generator import generate_notebook

        path = generate_notebook(goal, _normalise_output_path(output_path))
        return _json_response({"status": "success", "notebook_path": path})
    except ImportError as exc:
        return _json_response(
            {
                "status": "error",
                "error_type": "optional_dependency",
                "message": (
                    "Notebook generation requires the optional Google Generative AI "
                    f"dependency: {exc}"
                ),
            }
        )
    except Exception as exc:
        return _json_response({"status": "error", "message": str(exc)})


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
