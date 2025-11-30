import os
import json
import subprocess
import asyncio
from typing import Any, Dict, List
from mcp.server.fastmcp import FastMCP
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Initialize MCP Server
mcp = FastMCP("fganalysis-mcp")

# Helper to run R scripts
def run_r_wrapper(script_name: str, params: Dict[str, Any]) -> Dict[str, Any]:
    script_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "r_wrappers", script_name)
    
    # Ensure config path is absolute if provided, or default to standard location
    if "config_path" not in params:
        # Default to a likely location or require it
        # For now, let's assume a default relative to the repo root if not provided
        params["config_path"] = os.path.abspath(os.path.join(os.path.dirname(os.path.dirname(__file__)), "../fganalysis-r/config/db_config.json"))
    
    json_params = json.dumps(params)
    
    try:
        result = subprocess.run(
            ["Rscript", script_path, json_params],
            capture_output=True,
            text=True,
            check=True
        )
        # R script prints JSON to stdout
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        return {"status": "error", "message": f"R script failed: {e.stderr}", "stdout": e.stdout}
    except json.JSONDecodeError:
        return {"status": "error", "message": "Failed to parse R output", "raw_output": result.stdout}

@mcp.tool()
def run_drug_response_analysis(lab_id: List[str], drug_codes: List[str], output_prefix: str, before_window: List[float] = [-1, 0], after_window: List[float] = [0.25, 1], config_path: str = None) -> str:
    """
    Performs drug response analysis using fganalysis R package.
    
    Args:
        lab_id: List of OMOP concept IDs for labs.
        drug_codes: List of ATC codes for drugs.
        output_prefix: Prefix for output files.
        before_window: Time window before drug (years), e.g. [-1, 0].
        after_window: Time window after drug (years), e.g. [0.25, 1].
        config_path: Path to db_config.json.
    """
    params = {
        "lab_id": lab_id,
        "drug_codes": drug_codes,
        "before_window": before_window,
        "after_window": after_window,
        "output_prefix": output_prefix
    }
    if config_path:
        params["config_path"] = config_path
        
    result = run_r_wrapper("run_drug_response.R", params)
    return json.dumps(result, indent=2)

@mcp.tool()
def run_blup_analysis(lab_id: List[str], drug_codes: List[str], output_dir: str, config_path: str = None) -> str:
    """
    Calculates BLUP slopes for lab values.
    
    Args:
        lab_id: List of OMOP concept IDs.
        drug_codes: List of ATC codes.
        output_dir: Directory to save results.
        config_path: Path to db_config.json.
    """
    params = {
        "lab_id": lab_id,
        "drug_codes": drug_codes,
        "output_dir": output_dir
    }
    if config_path:
        params["config_path"] = config_path
        
    result = run_r_wrapper("run_blup_analysis.R", params)
    return json.dumps(result, indent=2)

@mcp.tool()
def get_lab_data_summary(lab_id: List[str], config_path: str = None) -> str:
    """
    Gets a summary (count and preview) of lab measurements.
    
    Args:
        lab_id: List of OMOP concept IDs.
        config_path: Path to db_config.json.
    """
    params = {"lab_id": lab_id}
    if config_path:
        params["config_path"] = config_path
        
    result = run_r_wrapper("get_lab_summary.R", params)
    return json.dumps(result, indent=2)

@mcp.tool()
def get_drug_purchases(drug_codes: List[str], config_path: str = None) -> str:
    """
    Gets a summary of drug purchases.
    
    Args:
        drug_codes: List of ATC codes.
        config_path: Path to db_config.json.
    """
    params = {"drug_codes": drug_codes}
    if config_path:
        params["config_path"] = config_path
        
    result = run_r_wrapper("get_drug_purchases.R", params)
    return json.dumps(result, indent=2)

@mcp.tool()
def plot_lab_distribution(lab_id: List[str], drug_codes: List[str], output_file: str, config_path: str = None) -> str:
    """
    Generates a violin plot comparing lab values before and after drug purchase.
    
    Args:
        lab_id: List of OMOP concept IDs.
        drug_codes: List of ATC codes.
        output_file: Path to save the plot (e.g., plot.pdf or plot.png).
        config_path: Path to db_config.json.
    """
    params = {
        "lab_id": lab_id,
        "drug_codes": drug_codes,
        "output_file": output_file
    }
    if config_path:
        params["config_path"] = config_path
        
    result = run_r_wrapper("plot_lab_distribution.R", params)
    return json.dumps(result, indent=2)

@mcp.tool()
def execute_r_code(code: str, config_path: str = None) -> str:
    """
    Executes arbitrary R code using the fganalysis package.
    The code has access to 'conn' (database connection).
    
    Args:
        code: R code to execute.
        config_path: Path to db_config.json.
    """
    params = {"code": code}
    if config_path:
        params["config_path"] = config_path
        
    result = run_r_wrapper("execute_r_code.R", params)
    return json.dumps(result, indent=2)

@mcp.tool()
def generate_analysis_notebook(goal: str, output_path: str) -> str:
    """
    Generates a Jupyter notebook for fganalysis based on a goal.
    
    Args:
        goal: Description of the analysis goal.
        output_path: Path to save the .ipynb file.
    """
    from .notebook_generator import generate_notebook
    
    try:
        path = generate_notebook(goal, output_path)
        return json.dumps({"status": "success", "notebook_path": path})
    except Exception as e:
        return json.dumps({"status": "error", "message": str(e)})

def main():
    mcp.run()

if __name__ == "__main__":
    main()
