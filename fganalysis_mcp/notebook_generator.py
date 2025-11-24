import os
import json
import google.generativeai as genai
from typing import Optional

def generate_notebook(goal: str, output_path: str, api_key: Optional[str] = None) -> str:
    """
    Generates a Jupyter notebook based on the user's goal using Google Generative AI.
    
    Args:
        goal: The analysis goal description.
        output_path: Path to save the generated notebook.
        api_key: Vertex AI API key. If None, tries to read from env.
        
    Returns:
        Path to the generated notebook.
    """
    if not api_key:
        api_key = os.getenv("VERTEX_API_KEY")
    
    if not api_key:
        raise ValueError("VERTEX_API_KEY not found in environment variables.")

    genai.configure(api_key=api_key)
    
    # Use a model that supports JSON generation well
    model = genai.GenerativeModel('gemini-1.5-pro-latest')
    
    prompt = f"""
    You are an expert R programmer and data scientist.
    Create a Jupyter notebook (v4 format) that uses the `fganalysis` R package to achieve the following goal:
    "{goal}"
    
    The notebook should:
    1. Load the `fganalysis` package.
    2. Connect to data using `connect_fgdata("config/db_config.json")`.
    3. Perform the necessary analysis steps (get data, run analysis, visualize).
    4. Include markdown cells explaining the steps.
    
    Return ONLY the raw JSON content of the .ipynb file. Do not include markdown code fences (```json ... ```).
    """
    
    try:
        response = model.generate_content(prompt)
        notebook_content = response.text
        
        # Clean up potential markdown fences if the model ignores instruction
        if notebook_content.startswith("```json"):
            notebook_content = notebook_content[7:]
        if notebook_content.startswith("```"):
            notebook_content = notebook_content[3:]
        if notebook_content.endswith("```"):
            notebook_content = notebook_content[:-3]
            
        notebook_json = json.loads(notebook_content)
        
        with open(output_path, 'w') as f:
            json.dump(notebook_json, f, indent=2)
            
        return output_path
        
    except Exception as e:
        raise RuntimeError(f"Failed to generate notebook: {str(e)}")
