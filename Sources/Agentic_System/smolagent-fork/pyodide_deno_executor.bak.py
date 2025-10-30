#!/usr/bin/env python
# coding=utf-8

# Copyright 2024 The HuggingFace Inc. team. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
import base64
import os
import subprocess
import tempfile
from io import BytesIO
from typing import Any, List, Optional, Tuple

import PIL.Image
import requests

from .monitoring import LogLevel
from .remote_executors import RemotePythonExecutor
from .utils import AgentError


class PyodideDenoExecutor(RemotePythonExecutor):
    """
    Executes Python code securely in a sandboxed JavaScript environment using Pyodide and Deno.

    This executor leverages Deno's secure runtime and Pyodide to run Python code in a sandboxed
    environment within the browser's JavaScript engine. It provides strong isolation guarantees
    while still allowing Python code execution.

    Args:
        additional_imports (`list[str]`): Additional Python packages to install in the Pyodide environment.
        logger (`Logger`): Logger to use for output and errors.
        deno_path (`str`, optional): Path to the Deno executable. If not provided, will use "deno" from PATH.
        deno_permissions (`list[str]`, optional): List of permissions to grant to the Deno runtime.
            Default is minimal permissions needed for execution.
        pyodide_packages (`list[str]`, optional): Additional Pyodide packages to load.
        timeout (`int`, optional): Timeout in seconds for code execution. Default is 60 seconds.
    """

    def __init__(
        self,
        additional_imports: List[str],
        logger,
        deno_path: str = "deno",
        deno_permissions: Optional[List[str]] = None,
        pyodide_packages: Optional[List[str]] = None,
        timeout: int = 60,
    ):
        super().__init__(additional_imports, logger)

        # Check if Deno is installed
        try:
            subprocess.run([deno_path, "--version"], capture_output=True, check=True)
        except (subprocess.SubprocessError, FileNotFoundError):
            raise RuntimeError(
                "Deno is not installed or not found in PATH. Please install Deno from https://deno.land/"
            )

        self.deno_path = deno_path
        self.timeout = timeout

        # Default minimal permissions needed
        if deno_permissions is None:
            # self.deno_permissions = ["--allow-net=cdn.jsdelivr.net"]  # TODO: AVM
            self.deno_permissions = [
                # "--allow-net=cdn.jsdelivr.net,0.0.0.0:8000",  # allow fetch & server
                "--allow-net=cdn.jsdelivr.net,0.0.0.0:8000",  # allow fetch & server with dynamic binding
                "--allow-read",  # grant read access for pyodide.asm.wasm
                "--allow-write",  # grant write access to load pyodide packages
                # "--unstable",  # allow top‑level await: DEPRECATED
            ]
        else:
            self.deno_permissions = [f"--{perm}" for perm in deno_permissions]

        # Default Pyodide packages
        if pyodide_packages is None:
            self.pyodide_packages = ["numpy", "pandas", "matplotlib", "pillow"]
        else:
            self.pyodide_packages = pyodide_packages

        # Create the Deno JavaScript runner file
        self._create_deno_runner()

        # Install additional packages
        self.installed_packages = self.install_packages(additional_imports)
        self.logger.log("PyodideDenoExecutor is running", level=LogLevel.INFO)

    def _create_deno_runner(self):
        """Create the Deno JavaScript file that will run Pyodide and execute Python code."""
        self.runner_dir = tempfile.mkdtemp(prefix="pyodide_deno_")
        self.runner_path = os.path.join(self.runner_dir, "pyodide_runner.js")

        # Create the JavaScript runner file
        with open(self.runner_path, "w") as f:
            f.write(JS_CODE)

        # Start the Deno server
        self._start_deno_server()

    def _start_deno_server(self):
        """Start the Deno server that will run our JavaScript code."""
        cmd = [self.deno_path, "run"] + self.deno_permissions + [self.runner_path]

        # Start the server process
        self.server_process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        # Wait for the server to start
        import time

        time.sleep(2)  # time.sleep(2)  # Give the server time to start

        # Check if the server started successfully
        if self.server_process.poll() is not None:
            stderr = self.server_process.stderr.read()
            raise RuntimeError(f"Failed to start Deno server: {stderr}")

        self.server_url = "http://localhost:8765"
        self.server_url = "http://localhost:8000"  # TODO: AVM

        # Test the connection
        try:
            response = requests.get(self.server_url)
            if response.status_code != 200:
                raise RuntimeError(f"Server responded with status code {response.status_code}: {response.text}")
        except requests.RequestException as e:
            raise RuntimeError(f"Failed to connect to Deno server: {e}")

    def run_code_raise_errors(self, code: str, return_final_answer: bool = False) -> Tuple[Any, str]:
        """
        Execute Python code in the Pyodide environment and return the result.

        Args:
            code (str): Python code to execute.
            return_final_answer (bool): Whether to extract and return the final answer.

        Returns:
            Tuple[Any, str]: A tuple containing the result and execution logs.
        """
        try:
            # Prepare the request payload
            payload = {
                "code": code,
                "returnFinalAnswer": return_final_answer,
                "packages": self.pyodide_packages + self.installed_packages,
            }

            # Send the request to the Deno server
            response = requests.post(self.server_url, json=payload, timeout=self.timeout)

            if response.status_code != 200:
                raise AgentError(f"Server error: {response.text}", self.logger)

            # Parse the response
            result_data = response.json()

            # Check for execution errors
            if result_data.get("error"):
                error = result_data["error"]
                error_message = f"{error.get('name', 'Error')}: {error.get('message', 'Unknown error')}"
                if "stack" in error:
                    error_message += f"\n{error['stack']}"
                raise AgentError(error_message, self.logger)

            # Get the execution logs
            execution_logs = result_data.get("stdout", "")

            # Process the result
            result = result_data.get("result")

            # Handle image results
            if isinstance(result, dict) and result.get("type") == "image":
                image_data = result.get("data", "")
                decoded_bytes = base64.b64decode(image_data.encode("utf-8"))
                return PIL.Image.open(BytesIO(decoded_bytes)), execution_logs

            return result, execution_logs

        except requests.RequestException as e:
            raise AgentError(f"Failed to communicate with Deno server: {e}", self.logger)

    def install_packages(self, additional_imports: List[str]) -> List[str]:
        """
        Install additional Python packages in the Pyodide environment.

        Args:
            additional_imports (List[str]): List of package names to install.

        Returns:
            List[str]: List of installed packages.
        """
        # In Pyodide, we don't actually install packages here, but we keep track of them
        # to load them when executing code
        self.logger.log(f"Adding packages to load: {', '.join(additional_imports)}", level=LogLevel.INFO)
        return additional_imports

    def cleanup(self):
        """Clean up resources used by the executor."""
        if hasattr(self, "server_process") and self.server_process:
            self.logger.log("Stopping Deno server...", level=LogLevel.INFO)
            self.server_process.terminate()
            try:
                self.server_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.server_process.kill()

        # Remove the temporary directory
        if hasattr(self, "runner_dir") and os.path.exists(self.runner_dir):
            import shutil

            shutil.rmtree(self.runner_dir)

    def delete(self):
        """Ensure cleanup on deletion."""
        self.cleanup()


JS_CODE = """\
// pyodide_runner.js - Runs Python code in Pyodide within Deno
import { serve } from "https://deno.land/std/http/server.ts";
import { loadPyodide } from "npm:pyodide";


// Initialize Pyodide instance
const pyodidePromise = loadPyodide();
// Initialize Pyodide instance and load numpy
//const pyodidePromise = (async () => {
//  const pyodide = await loadPyodide();
//  await pyodide.loadPackage('numpy');
//  return pyodide;
//})();

// Function to execute Python code and return the result
async function executePythonCode(code, returnFinalAnswer = false) {
  //TODO:AVM:
  const pyodide = await pyodidePromise;
  //const pyodide = await pyodideReadyPromise;
  //let pyodide = await loadPyodide();

  //await pyodide.loadPackage('numpy');

  // Create a capture for stdout
  pyodide.runPython(`
    import sys
    import io
    sys.stdout = io.StringIO()
  `);

  // Execute the code and capture any errors
  let result = null;
  let error = null;
  let stdout = "";

  try {
    // Execute the code
    if (returnFinalAnswer) {
      // Extract the final_answer call if present
      const finalAnswerMatch = code.match(/final_answer\\s*\\((.*)\\)/);
      if (finalAnswerMatch) {
        // Execute the code up to the final_answer call
        const preCode = code.replace(/final_answer\\s*\\(.*\\)/, "");
        pyodide.runPython(preCode);

        // Execute the final_answer expression and get the result
        const finalAnswerExpr = finalAnswerMatch[1];
        result = pyodide.runPython(`${finalAnswerExpr}`);

        // Handle image results
        if (result && result.constructor.name === "Image") {
          // Convert PIL Image to base64
          const pngBytes = pyodide.runPython(`
            import io
            import base64
            buf = io.BytesIO()
            _result.save(buf, format='PNG')
            base64.b64encode(buf.getvalue()).decode('utf-8')
          `);
          result = { type: "image", data: pngBytes };
        }
      }
    } else {
      // Just run the code without expecting a final answer
      result = pyodide.runPython(code);
    }

    // Get captured stdout
    stdout = pyodide.runPython("sys.stdout.getvalue()");
  } catch (e) {
    error = {
      name: e.constructor.name,
      message: e.message,
      stack: e.stack
    };
  }

  return {
    result: result,
    stdout: stdout,
    error: error
  };
}

// Start a simple HTTP server to receive code execution requests
//const port = 8765;
//console.log(`Starting Pyodide server on port ${port}`);

serve(async (req) => {
  if (req.method === "POST") {
    try {
      const body = await req.json();
      const { code, returnFinalAnswer = false, packages = [] } = body;

      // Load any requested packages
      if (packages && packages.length > 0) {
        const pyodide = await pyodidePromise;
        //await pyodide.loadPackagesFromImports(code);
        for (const pkg of packages) {
          try {
            await pyodide.loadPackage(pkg);
          } catch (e) {
            console.error(`Failed to load package ${pkg}: ${e.message}`);
          }
        }
      } else {
        console.log("Skipping package loading block. Packages:", packages); // Added log for else case
      }
      //const pyodide = await pyodidePromise;
      //await pyodide.loadPackage("numpy");

      const result = await executePythonCode(code, returnFinalAnswer);
      return new Response(JSON.stringify(result), {
        headers: { "Content-Type": "application/json" }
      });
    } catch (e) {
      return new Response(JSON.stringify({ error: e.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" }
      });
    }
  }

  return new Response("Pyodide-Deno Executor is running. Send POST requests with code to execute.", {
    headers: { "Content-Type": "text/plain" }
  });
});
"""
