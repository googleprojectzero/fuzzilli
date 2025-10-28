"""
// pyodide_runner.js - Runs Python code in Pyodide within Deno
import { serve } from "https://deno.land/std/http/server.ts";
// TODO: AVM
import { loadPyodide } from "https://cdn.jsdelivr.net/pyodide/v0.24.1/full/pyodide.mjs";
//const pyodide = await loadPyodide({ indexURL: "https://cdn.jsdelivr.net/pyodide/v0.24.1/full/" });
let pyodide;
try {
    pyodide = await loadPyodide({
        indexURL: "https://cdn.jsdelivr.net/pyodide/v0.24.1/full/",
    });

    // Load micropip for package management
    await pyodide.loadPackage("micropip");

    // Load additional packages if specified
    //{self._get_package_loading_code()}

} catch (error) {
    console.error("Failed to initialize Pyodide:", error);
    Deno.exit(1);
}

// Load Pyodide
//const pyodidePromise = (async () => {
//  const pyodide = await import("https://cdn.jsdelivr.net/pyodide/v0.24.1/full/pyodide.js");
//  return await pyodide.loadPyodide();
//})();
"""

# JS_CODE_0 = """\
# // pyodide_runner.js - Runs Python code in Pyodide within Deno
# import { serve } from "https://deno.land/std/http/server.ts";
# import { loadPyodide } from "https://cdn.jsdelivr.net/pyodide/v0.27.5/full/pyodide.mjs";
#
#
# const indexURL = "https://cdn.jsdelivr.net/pyodide/v0.27.5/full/";
# const pyodidePromise = loadPyodide({
#   indexURL,
#   locateFile: path => indexURL + path
# });
#
#
# // Function to execute Python code and return the result
# async function executePythonCode(code, returnFinalAnswer = false) {
#   //TODO:AVM:
#   const pyodide = await pyodidePromise;
#   //const pyodide = await pyodideReadyPromise;
#
#   // Create a capture for stdout
#   pyodide.runPython(`
#     import sys
#     import io
#     sys.stdout = io.StringIO()
#   `);
#
#   // Execute the code and capture any errors
#   let result = null;
#   let error = null;
#   let stdout = "";
#
#   try {
#     // Execute the code
#     if (returnFinalAnswer) {
#       // Extract the final_answer call if present
#       const finalAnswerMatch = code.match(/final_answer\\s*\\((.*)\\)/);
#       if (finalAnswerMatch) {
#         // Execute the code up to the final_answer call
#         const preCode = code.replace(/final_answer\\s*\\(.*\\)/, "");
#         pyodide.runPython(preCode);
#
#         // Execute the final_answer expression and get the result
#         const finalAnswerExpr = finalAnswerMatch[1];
#         result = pyodide.runPython(`${finalAnswerExpr}`);
#
#         // Handle image results
#         if (result && result.constructor.name === "Image") {
#           // Convert PIL Image to base64
#           const pngBytes = pyodide.runPython(`
#             import io
#             import base64
#             buf = io.BytesIO()
#             _result.save(buf, format='PNG')
#             base64.b64encode(buf.getvalue()).decode('utf-8')
#           `);
#           result = { type: "image", data: pngBytes };
#         }
#       }
#     } else {
#       // Just run the code without expecting a final answer
#       result = pyodide.runPython(code);
#     }
#
#     // Get captured stdout
#     stdout = pyodide.runPython("sys.stdout.getvalue()");
#   } catch (e) {
#     error = {
#       name: e.constructor.name,
#       message: e.message,
#       stack: e.stack
#     };
#   }
#
#   return {
#     result: result,
#     stdout: stdout,
#     error: error
#   };
# }
#
# // Start a simple HTTP server to receive code execution requests
# const port = 8765;
# console.log(`Starting Pyodide server on port ${port}`);
#
# serve(async (req) => {
#   if (req.method === "POST") {
#     try {
#       const body = await req.json();
#       const { code, returnFinalAnswer = false, packages = [] } = body;
#
#       // Load any requested packages
#       if (packages && packages.length > 0) {
#         const pyodide = await pyodidePromise;
#         await pyodide.loadPackagesFromImports(code);
#         for (const pkg of packages) {
#           try {
#             await pyodide.loadPackage(pkg);
#           } catch (e) {
#             console.error(`Failed to load package ${pkg}: ${e.message}`);
#           }
#         }
#       }
#
#       const result = await executePythonCode(code, returnFinalAnswer);
#       return new Response(JSON.stringify(result), {
#         headers: { "Content-Type": "application/json" }
#       });
#     } catch (e) {
#       return new Response(JSON.stringify({ error: e.message }), {
#         status: 500,
#         headers: { "Content-Type": "application/json" }
#       });
#     }
#   }
#
#   return new Response("Pyodide-Deno Executor is running. Send POST requests with code to execute.", {
#     headers: { "Content-Type": "text/plain" }
#   });
# });
# """

# JS_CODE_2 = """\
# // pyodide_runner.js - Runs Python code in Pyodide within Deno
# import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
# import { loadPyodide } from "https://cdn.jsdelivr.net/pyodide/v0.23.4/full/pyodide.mjs";
#
# const handler = async (request) => {
#     try {
#         // Initialize Pyodide if not already initialized
#         if (!globalThis.pyodide) {
#             console.log("Initializing Pyodide...");
#             globalThis.pyodide = await loadPyodide({
#                 indexURL: "https://cdn.jsdelivr.net/pyodide/v0.23.4/full/",
#                 stdout: (text) => console.log(text),
#                 stderr: (text) => console.error(text)
#             });
#             console.log("Pyodide initialized successfully");
#         }
#
#         if (request.method === "POST") {
#             const body = await request.json();
#             const code = body.code;
#
#             let output = "";
#             let error = null;
#             let result = null;
#
#             try {
#                 // Redirect stdout/stderr to capture output
#                 globalThis.pyodide.setStdout({ write: (text) => output += text });
#                 globalThis.pyodide.setStderr({ write: (text) => output += text });
#
#                 // Execute the Python code
#                 result = await globalThis.pyodide.runPythonAsync(code);
#
#                 return new Response(JSON.stringify({
#                     output,
#                     result: result?.toString() || "",
#                     error: null
#                 }), {
#                     headers: { "Content-Type": "application/json" }
#                 });
#             } catch (e) {
#                 return new Response(JSON.stringify({
#                     output,
#                     result: null,
#                     error: e.toString()
#                 }), {
#                     headers: { "Content-Type": "application/json" }
#                 });
#             }
#         }
#
#         return new Response("Method not allowed", { status: 405 });
#     } catch (e) {
#         return new Response(JSON.stringify({ error: e.toString() }), {
#             status: 500,
#             headers: { "Content-Type": "application/json" }
#         });
#     }
# };
#
# //console.log(`Starting server on port {self.port}...`);
# //await serve(handler, { port: {self.port} });
# //const port = 8765;
# //console.log(`Starting Pyodide server on port ${port}`);
# //await serve(handler, { port: 8765 });
# //const port = 8000;
# //console.log(`Starting Pyodide server on port ${port}`);
# //await serve(handler, { port: 8000 });
# """
