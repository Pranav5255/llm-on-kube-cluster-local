"""Tiny BFF: static chat UI + CORS proxy to Ollama OpenAI-compatible API."""

from pathlib import Path

import httpx
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

OLLAMA_BASE = "http://ollama.llm.svc.cluster.local:11434"

app = FastAPI(title="OSS LLM Chat UI")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

static_dir = Path(__file__).parent / "static"
app.mount("/assets", StaticFiles(directory=static_dir), name="assets")


@app.get("/")
async def index():
    return FileResponse(static_dir / "index.html")


@app.api_route("/v1/{path:path}", methods=["GET", "POST", "DELETE", "OPTIONS"])
async def proxy_v1(path: str, request: Request):
    url = f"{OLLAMA_BASE}/v1/{path}"
    body = await request.body()
    headers = {
        k: v
        for k, v in request.headers.items()
        if k.lower() in ("content-type", "authorization")
    }
    # CPU inference in kind can exceed several minutes for first full completion
    async with httpx.AsyncClient(timeout=httpx.Timeout(900.0)) as client:
        r = await client.request(
            request.method,
            url,
            content=body if body else None,
            headers=headers,
            params=request.query_params,
        )
    ct = r.headers.get("content-type", "application/json")
    return Response(content=r.content, status_code=r.status_code, media_type=ct)
