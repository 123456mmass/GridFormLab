"""FastAPI router for power flow solver endpoints.

Endpoints:
    GET  /api/health              — service status
    GET  /api/cases               — list available cases
    GET  /api/cases/{name}        — case detail
    GET  /api/solvers             — list solvers + default options
    POST /api/solve/{method}      — run a solver
    POST /api/compare             — compare multiple solvers
    POST /api/benchmark           — benchmark all (or selected) solvers
"""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse

from cases import loader as case_loader
from db import operations as db_ops

logger = logging.getLogger("nbus.api")
from pfsolver import (
    ac_opf,
    cpf_ls,
    cpf_pc,
    dc_power_flow,
    dishonest_nr,
    dynamic_homotopy,
    economic_dispatch,
    fast_decoupled,
    gauss_seidel,
    helm,
    helm_nr_hybrid,
    newton_raphson,
)
from . import schemas

router = APIRouter(prefix="/api")

# ── Solver registry ─────────────────────────────────────────

SOLVERS: dict[str, Any] = {
    "newton-raphson": newton_raphson,
    "nr": newton_raphson,
    "gauss-seidel": gauss_seidel,
    "gs": gauss_seidel,
    "fast-decoupled": fast_decoupled,
    "fdlf": fast_decoupled,
    "dc-power-flow": dc_power_flow,
    "dc": dc_power_flow,
    "dishonest-nr": dishonest_nr,
    "dnr": dishonest_nr,
    "helm": helm,
    "helm-nr-hybrid": helm_nr_hybrid,
    "dynamic-homotopy": dynamic_homotopy,
    "homotopy": dynamic_homotopy,
    "cpf-pc": cpf_pc,
    "cpf-ls": cpf_ls,
    "cpf": cpf_pc,
    "economic-dispatch": economic_dispatch,
    "ed": economic_dispatch,
    "ac-opf": ac_opf,
    "opf": ac_opf,
}

SOLVER_DEFAULTS: dict[str, dict[str, Any]] = {
    "newton-raphson": {"max_iter": 30, "tolerance": 1e-6, "verbose": False},
    "gauss-seidel": {"max_iter": 200, "tolerance": 1e-6, "acceleration": 1.4, "verbose": False},
    "fast-decoupled": {"max_iter": 50, "tolerance": 1e-6, "verbose": False},
    "dc-power-flow": {"verbose": False},
    "dishonest-nr": {"max_iter": 30, "tolerance": 1e-6, "freeze_iterations": 3, "verbose": False},
    "helm": {"max_order": 20, "pade_L": 8, "pade_M": 8, "verbose": False},
    "helm-nr-hybrid": {"max_order": 8, "pade_L": 4, "pade_M": 4, "verbose": False},
    "dynamic-homotopy": {"step_size": 0.2, "min_step": 0.01, "tolerance": 1e-6, "verbose": False},
    "cpf-pc": {"lambda_start": 0.0, "lambda_target": 2.5, "step_size": 0.2, "tolerance": 1e-6},
    "cpf-ls": {"lambda_start": 0.0, "lambda_target": 2.5, "num_steps": 20, "tolerance": 1e-6},
    "economic-dispatch": {"include_losses": False, "loss_penalty_factor": 0.05},
    "ac-opf": {"step_size": 0.1, "max_iter": 100, "tolerance": 1e-6},
}


def _resolve_method(method: str):
    """Resolve solver method alias to module."""
    m = SOLVERS.get(method.lower())
    if m is None:
        raise HTTPException(404, f"Unknown solver: {method}. Available: {list(SOLVERS.keys())}")
    return m


def _get_options(method: str, user_opts: dict | None) -> dict:
    """Merge user options with solver defaults."""
    canonical = next((k for k in SOLVERS if k.lower() == method.lower()), method.lower())
    defaults = dict(SOLVER_DEFAULTS.get(canonical, {}))
    if user_opts:
        defaults.update(user_opts)
    return defaults


# ── Auth dependency ─────────────────────────────────────────

async def _check_auth(request: Request):
    """Validate JWT from Authorization header."""
    from auth.utils import decode_token
    import jwt as pyjwt
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return JSONResponse(status_code=401, content={"error": "Not authenticated"})
    try:
        payload = decode_token(auth_header.removeprefix("Bearer "))
        if payload.get("type") != "access":
            return JSONResponse(status_code=401, content={"error": "Not an access token"})
    except pyjwt.ExpiredSignatureError:
        return JSONResponse(status_code=401, content={"error": "Token expired"})
    except pyjwt.InvalidTokenError:
        return JSONResponse(status_code=401, content={"error": "Invalid token"})
    return None


# ── Endpoints ────────────────────────────────────────────────

@router.get("/health", response_model=schemas.HealthResponse)
async def health():
    return schemas.HealthResponse(
        solvers=list(SOLVER_DEFAULTS.keys()),
        cases=case_loader.list_cases(),
    )


@router.get("/cases", response_model=schemas.CaseListResponse)
async def list_cases():
    items = []
    for name in case_loader.list_cases():
        try:
            case = case_loader.load_case(name)
            bus = case.get("bus_data", [])
            lines = case.get("line_data", [])
            items.append(schemas.CaseListItem(
                name=name,
                system_name=case.get("system_name", name),
                bus_count=len(bus) if isinstance(bus, list) else 0,
                line_count=len(lines) if isinstance(lines, list) else 0,
            ))
        except Exception:
            items.append(schemas.CaseListItem(name=name, system_name=name, bus_count=0, line_count=0))
    return schemas.CaseListResponse(cases=items)


@router.get("/cases/{name}", response_model=schemas.CaseDetailResponse)
async def case_detail(name: str):
    try:
        case = case_loader.load_case(name)
    except FileNotFoundError:
        raise HTTPException(404, f"Case not found: {name}")
    bus = case.get("bus_data", [])
    lines = case.get("line_data", [])
    return schemas.CaseDetailResponse(
        name=name,
        system_name=case.get("system_name", name),
        bus_count=len(bus) if isinstance(bus, list) else 0,
        line_count=len(lines) if isinstance(lines, list) else 0,
        base_MVA=case.get("base_values", {}).get("baseMVA"),
        bus_data=bus,
        line_data=lines,
    )


@router.get("/history")
async def run_history(solver: str | None = None, limit: int = 50):
    """Return recent solve runs from the database."""
    try:
        return await db_ops.get_recent_runs(limit=limit, solver=solver)
    except Exception:
        raise HTTPException(503, "Database unavailable")


@router.get("/solvers")
async def list_solvers():
    return [
        schemas.OptionsInfo(solver=k, default_options=v, description="")
        for k, v in SOLVER_DEFAULTS.items()
    ]


@router.post("/solve/{method}", response_model=schemas.SolveResponse)
async def solve(request: Request, method: str, req: schemas.SolveRequest):
    if auth_err := await _check_auth(request): return auth_err
    """Run a single power flow solver on a case."""
    mod = _resolve_method(method)
    opts = _get_options(method, req.options)

    try:
        case = case_loader.load_case(req.case_name)
    except FileNotFoundError:
        raise HTTPException(404, f"Case not found: {req.case_name}")

    t0 = time.perf_counter()
    try:
        raw = mod.solve(case, opts)
    except Exception as e:
        raise HTTPException(500, f"Solver failed: {e}")
    elapsed_ms = (time.perf_counter() - t0) * 1000

    if "error" in raw:
        raise HTTPException(422, raw["error"])

    result = schemas.result_to_response(raw, elapsed_ms)

    asyncio.create_task(_safe_save_run(
        req.case_name, method, opts,
        raw.get("converged", False),
        raw.get("iterations", 0),
        raw.get("P_loss_total"), raw.get("Q_loss_total"),
        elapsed_ms, raw,
    ))

    return schemas.SolveResponse(result=result, case_name=req.case_name)


@router.post("/compare", response_model=schemas.CompareResponse)
async def compare(request: Request, req: schemas.CompareRequest):
    if auth_err := await _check_auth(request): return auth_err
    """Compare multiple solvers on the same case."""
    try:
        case = case_loader.load_case(req.case_name)
    except FileNotFoundError:
        raise HTTPException(404, f"Case not found: {req.case_name}")

    results = []
    for method in req.methods:
        mod = _resolve_method(method)
        opts = _get_options(method, req.options)
        try:
            raw = mod.solve(case, opts)
        except Exception as e:
            results.append(schemas.SolverResult(
                system_name=case.get("system_name", ""),
                method=method,
                converged=False,
                iterations=0, P_loss_total=0, Q_loss_total=0,
                P_total_gen=0, Q_total_gen=0, P_total_load=0, Q_total_load=0,
                buses=[], lines=[], mismatch_history=[], metadata={},
                solver_specific={"error": str(e)},
            ))
            continue
        if "error" in raw:
            results.append(schemas.SolverResult(
                system_name=case.get("system_name", ""),
                method=method,
                converged=False,
                iterations=0, P_loss_total=0, Q_loss_total=0,
                P_total_gen=0, Q_total_gen=0, P_total_load=0, Q_total_load=0,
                buses=[], lines=[], mismatch_history=[], metadata={},
                solver_specific={"error": raw["error"]},
            ))
        else:
            results.append(schemas.result_to_response(raw))

    summary = _build_compare_summary(results)
    return schemas.CompareResponse(
        case_name=req.case_name,
        methods=req.methods,
        results=results,
        summary=summary,
    )


@router.post("/benchmark", response_model=schemas.BenchmarkResponse)
async def benchmark(request: Request, req: schemas.BenchmarkRequest):
    if auth_err := await _check_auth(request): return auth_err
    """Benchmark all (or selected) solvers on a case."""
    try:
        case = case_loader.load_case(req.case_name)
    except FileNotFoundError:
        raise HTTPException(404, f"Case not found: {req.case_name}")

    methods = req.methods if req.methods else list(SOLVER_DEFAULTS.keys())
    results = []
    for method in methods:
        mod = _resolve_method(method)
        opts = _get_options(method, req.options)
        t0 = time.perf_counter()
        try:
            raw = mod.solve(case, opts)
        except Exception as e:
            raw = {"error": str(e)}
        elapsed_ms = (time.perf_counter() - t0) * 1000
        if "error" in raw:
            results.append(schemas.SolverResult(
                system_name=case.get("system_name", ""), method=method,
                converged=False, iterations=0, P_loss_total=0, Q_loss_total=0,
                P_total_gen=0, Q_total_gen=0, P_total_load=0, Q_total_load=0,
                buses=[], lines=[], mismatch_history=[], metadata={},
                execution_time_ms=elapsed_ms, solver_specific={"error": raw["error"]},
            ))
        else:
            r = schemas.result_to_response(raw, elapsed_ms)
            results.append(r)

    ranking = _build_ranking(results)
    return schemas.BenchmarkResponse(case_name=req.case_name, results=results, ranking=ranking)


def _build_compare_summary(results: list[schemas.SolverResult]) -> dict:
    converged = [r for r in results if r.converged]
    fastest = min(converged, key=lambda r: r.execution_time_ms or float("inf")) if converged else None
    lowest_loss = min(converged, key=lambda r: abs(r.P_loss_total)) if converged else None
    return {
        "num_converged": len(converged),
        "num_failed": len(results) - len(converged),
        "fastest": fastest.method if fastest else None,
        "fastest_ms": round(fastest.execution_time_ms, 1) if fastest and fastest.execution_time_ms else None,
        "lowest_loss_method": lowest_loss.method if lowest_loss else None,
        "lowest_P_loss": round(lowest_loss.P_loss_total, 6) if lowest_loss else None,
    }


def _build_ranking(results: list[schemas.SolverResult]) -> dict:
    return {
        "by_speed": [
            {"method": r.method, "execution_time_ms": r.execution_time_ms}
            for r in sorted(results, key=lambda x: x.execution_time_ms or float("inf"))
            if r.execution_time_ms is not None
        ],
        "by_convergence": [
            {"method": r.method, "converged": r.converged, "iterations": r.iterations}
            for r in sorted(results, key=lambda x: (not x.converged, x.iterations))
        ],
    }


async def _safe_save_run(
    case_name: str,
    solver: str,
    options: dict | None,
    converged: bool,
    iterations: int,
    P_loss: float | None,
    Q_loss: float | None,
    elapsed_ms: float | None,
    raw: dict,
):
    try:
        await db_ops.save_run(
            case_name=case_name,
            solver=solver,
            options=options,
            converged=converged,
            iterations=iterations,
            P_loss=P_loss,
            Q_loss=Q_loss,
            execution_time_ms=elapsed_ms,
            result_data=raw,
        )
    except Exception:
        logger.warning("Failed to persist run history (DB may be unavailable)", exc_info=True)
