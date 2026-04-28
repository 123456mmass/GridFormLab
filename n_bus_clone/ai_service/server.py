"""Power-system AI analysis service.

Endpoints:
    GET  /health           — service status
    POST /analyze          — analyze power flow results
    POST /analyze/cpf      — analyze CPF results
    POST /analyze/opf      — analyze OPF results
    POST /ask              — free-form question about results

Run:
    cd ai_service
    pip install -r requirements.txt
    python server.py
"""

from __future__ import annotations

import json
from typing import Any

from openai import OpenAI
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

import config
import prompts

# ── Client ──────────────────────────────────────────────────

client = OpenAI(api_key=config.API_KEY, base_url=config.BASE_URL)

app = FastAPI(title="Power-System AI Analyst (GPT)", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Helpers ─────────────────────────────────────────────────

def _call_gpt(system: str, user_msg: str) -> str:
    """Send a single-turn request and return the text response."""
    resp = client.chat.completions.create(
        model=config.MODEL,
        max_tokens=config.MAX_TOKENS,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": user_msg},
        ],
    )
    return resp.choices[0].message.content


def _format_bus_table(bus_data: dict) -> str:
    """Pretty-print bus results as a text table."""
    lines = ["Bus  Type     V(pu)    Angle(deg)  Pgen(pu)  Qgen(pu)  Pload(pu) Qload(pu)"]
    for i in range(len(bus_data.get("bus", []))):
        lines.append(
            f"{bus_data['bus'][i]:>3}  {bus_data.get('type',[''])[i]:<6}  "
            f"{bus_data.get('voltage',[0])[i]:>7.4f}  "
            f"{bus_data.get('angle',[0])[i]:>10.3f}  "
            f"{bus_data.get('Pgen',[0])[i]:>8.4f}  "
            f"{bus_data.get('Qgen',[0])[i]:>8.4f}  "
            f"{bus_data.get('Pload',[0])[i]:>8.4f}  "
            f"{bus_data.get('Qload',[0])[i]:>8.4f}"
        )
    return "\n".join(lines)


# ── Request models ──────────────────────────────────────────

class AnalyzeRequest(BaseModel):
    method: str = Field(..., description="Solver method name")
    system_name: str = Field("Unknown", description="System identifier")
    num_buses: int = Field(0)
    num_lines: int = Field(0)
    iterations: int = Field(0)
    converged: bool = Field(True)
    P_loss_total: float = Field(0.0, description="Total active power loss (pu)")
    Q_loss_total: float = Field(0.0, description="Total reactive power loss (pu)")
    bus_data: dict | None = Field(None, description="Bus voltage/angle/generation data")
    mismatch_history: list[float] | None = Field(None)


class CPFRequest(BaseModel):
    method: str = Field("CPF Predictor-Corrector")
    system_name: str = Field("Unknown")
    num_buses: int = Field(0)
    target_bus: int = Field(0)
    num_points: int = Field(0)
    nose_detected: bool = Field(False)
    lambda_min: float = Field(0.0)
    lambda_max: float = Field(0.0)
    voltage_min: float = Field(0.0)
    voltage_max: float = Field(0.0)
    stop_reason: str = Field("")
    lambdas: list[float] | None = Field(None)
    target_voltage: list[float] | None = Field(None)


class OPFRequest(BaseModel):
    system_name: str = Field("Unknown")
    demand_MW: float = Field(0.0)
    total_cost: float = Field(0.0)
    lambda_cost: float = Field(0.0, description="Incremental cost $/MWh")
    balance_residual: float = Field(0.0)
    generators: list[dict] | None = Field(None, description="Per-gen: {id, P_MW, cost, limit}")


class AskRequest(BaseModel):
    question: str = Field(..., description="Free-form question")
    results_json: str | None = Field(None, description="Optional results JSON for context")


# ── Endpoints ───────────────────────────────────────────────

@app.get("/health")
def health():
    return {
        "status": "ok",
        "model": config.MODEL,
        "base_url": config.BASE_URL,
    }


@app.post("/analyze")
def analyze(req: AnalyzeRequest):
    """Analyze power flow results (NR or GS)."""
    # Build result summary
    parts = [
        f"Converged: {req.converged}",
        f"Iterations: {req.iterations}",
        f"P_loss: {req.P_loss_total:.6f} pu",
        f"Q_loss: {req.Q_loss_total:.6f} pu",
    ]
    if req.bus_data:
        parts.append("\nBus results:\n" + _format_bus_table(req.bus_data))
    if req.mismatch_history:
        parts.append(f"\nMismatch history (last 5): {req.mismatch_history[-5:]}")

    prompt = prompts.ANALYZE_PROMPT_TEMPLATE.format(
        method=req.method,
        system_name=req.system_name,
        num_buses=req.num_buses,
        num_lines=req.num_lines,
        result_data="\n".join(parts),
    )

    try:
        text = _call_gpt(prompts.SYSTEM_PROMPT,prompt)
        return {"analysis": text}
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/analyze/cpf")
def analyze_cpf(req: CPFRequest):
    """Analyze CPF results for voltage stability."""
    prompt = prompts.CPF_PROMPT_TEMPLATE.format(
        method=req.method,
        system_name=req.system_name,
        num_buses=req.num_buses,
        target_bus=req.target_bus,
        num_points=req.num_points,
        nose_detected="Yes" if req.nose_detected else "No",
        lambda_min=req.lambda_min,
        lambda_max=req.lambda_max,
        voltage_min=req.voltage_min,
        voltage_max=req.voltage_max,
        stop_reason=req.stop_reason,
    )

    try:
        text = _call_gpt(prompts.SYSTEM_PROMPT,prompt)
        return {"analysis": text}
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/analyze/opf")
def analyze_opf(req: OPFRequest):
    """Analyze economic dispatch results."""
    dispatch_lines = []
    if req.generators:
        for g in req.generators:
            dispatch_lines.append(
                f"  Gen {g.get('id','?')}: {g.get('P_MW',0):.2f} MW, "
                f"cost={g.get('cost',0):.2f} $/h, limit={g.get('limit','free')}"
            )

    prompt = prompts.OPF_PROMPT_TEMPLATE.format(
        system_name=req.system_name,
        demand=req.demand_MW,
        total_cost=req.total_cost,
        lambda_cost=req.lambda_cost,
        residual=req.balance_residual,
        dispatch_table="\n".join(dispatch_lines) if dispatch_lines else "  (no generator data)",
    )

    try:
        text = _call_gpt(prompts.SYSTEM_PROMPT,prompt)
        return {"analysis": text}
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.post("/ask")
def ask(req: AskRequest):
    """Free-form question, optionally with results context."""
    user_msg = req.question
    if req.results_json:
        user_msg += f"\n\nRelevant results data:\n{req.results_json}"

    try:
        text = _call_gpt(prompts.SYSTEM_PROMPT,user_msg)
        return {"analysis": text}
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


# ── Main ────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    print(f"Starting AI analysis service on http://{config.HOST}:{config.PORT}")
    print(f"Model: {config.MODEL}")
    print(f"Docs:  http://{config.HOST}:{config.PORT}/docs")
    uvicorn.run(app, host=config.HOST, port=config.PORT)
