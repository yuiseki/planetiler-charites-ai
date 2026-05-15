"""
planetiler-charites-ai HTTP gateway.

  /data/*          -> static (pmtiles, style.json) with HTTP Range support
  /web/*           -> UI
  POST /api/instruct  -> spawn `claude -p`, stream stdout (stream-json) to
                        the client over SSE so the UI can show progress and
                        reload the map when build finishes
"""
import asyncio
import json
from pathlib import Path

from fastapi import Body, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from fastapi.staticfiles import StaticFiles

# Project layout: this file lives in <root>/api/main.py
ROOT = Path(__file__).resolve().parent.parent

app = FastAPI(title="planetiler-charites-ai")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Range", "Accept-Ranges", "Content-Length"],
)


# Tools the agent is allowed to invoke. Read/Edit/Write for fragment edits,
# Bash(make *) so it can rebuild, Bash(npx tsx *) for direct script use.
ALLOWED_TOOLS = "Read Edit Write Bash(make *) Bash(npx tsx *) Bash(ls *) Bash(cat *) Glob Grep"


_THEME_RE = __import__("re").compile(r"^[A-Za-z0-9_]+$")


@app.post("/api/instruct")
async def instruct(payload: dict = Body(...)):
    instruction = (payload.get("instruction") or "").strip()
    theme = (payload.get("theme") or "monaco").strip()
    if not instruction:
        return {"error": "instruction required"}
    if not theme.replace("_", "").isalnum():
        return {"error": "invalid theme name"}

    cmd = [
        "claude",
        "-p", instruction,
        "--output-format", "stream-json",
        "--verbose",
        "--allowedTools", *ALLOWED_TOOLS.split(),
        # acceptEdits only auto-approves Edit/Write. Bash needs bypassPermissions
        # (the allowedTools allowlist still restricts which Bash commands run).
        "--permission-mode", "bypassPermissions",
        "--max-budget-usd", "1",
        "--append-system-prompt",
        (
            f"The current theme is '{theme}'. Edit fragments under themes/{theme}/ only. "
            f"After every edit, run: make {theme}-build && make {theme}-pmtiles. "
            f"If you add a new layer that uses an OSM tag that is rare in the source PBF, "
            f"prefer wider include_when patterns so the user actually sees something on the map."
        ),
    ]

    async def stream():
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            cwd=str(ROOT),
        )
        assert proc.stdout is not None
        async for raw in proc.stdout:
            line = raw.decode(errors="replace").rstrip("\n")
            if not line:
                continue
            # Pass through verbatim -- UI parses stream-json itself.
            yield f"data: {line}\n\n"
        await proc.wait()
        yield "data: " + json.dumps({"type": "done", "exit": proc.returncode}) + "\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


@app.post("/api/build")
async def build(payload: dict = Body(...)):
    """Run `make {theme}-pmtiles` and stream Planetiler's stdout as SSE.

    Separated from /api/instruct so the agent edits fragments + runs `make
    {theme}-build` (cheap, gives the agent its validator feedback), and the
    expensive Planetiler step is driven by the UI with live progress.
    """
    theme = (payload.get("theme") or "monaco").strip()
    if not _THEME_RE.match(theme):
        return {"error": "invalid theme name"}

    cmd = ["make", f"{theme}-pmtiles"]

    async def stream():
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            cwd=str(ROOT),
        )
        assert proc.stdout is not None
        async for raw in proc.stdout:
            line = raw.decode(errors="replace").rstrip("\r\n")
            if not line:
                continue
            yield "data: " + json.dumps({"type": "log", "line": line}) + "\n\n"
        await proc.wait()
        yield "data: " + json.dumps({"type": "done", "exit": proc.returncode}) + "\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


app.mount("/data", StaticFiles(directory=str(ROOT / "data")), name="data")
app.mount("/", StaticFiles(directory=str(ROOT / "web"), html=True), name="ui")
