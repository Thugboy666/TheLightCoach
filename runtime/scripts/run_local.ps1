$ErrorActionPreference = "Stop"
Write-Host "[run_local] Starting llama.cpp server..."
Start-Process -FilePath "runtime/llm/llamacpp/llama-server.exe" -ArgumentList "--model", "runtime/llm/models/model.gguf" -WindowStyle Minimized
Write-Host "[run_local] Starting FastAPI server..."
& "runtime/python310/python.exe" -m uvicorn app.server:app --host 0.0.0.0 --port 8000
