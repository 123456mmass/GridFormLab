"""Pydantic schemas for solver API."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


# ── Request models ──────────────────────────────────────────

class SolveRequest(BaseModel):
    case_name: str = Field("ieee5bus", max_length=200, description="Case file name without .yaml")
    options: dict[str, Any] | None = Field(None, description="Solver-specific options")


class CompareRequest(BaseModel):
    case_name: str = Field("ieee5bus", max_length=200)
    methods: list[str] = Field(..., min_length=2, max_length=12, description="Solver methods to compare")
    options: dict[str, Any] | None = Field(None)


class BenchmarkRequest(BaseModel):
    case_name: str = Field("ieee5bus", max_length=200)
    methods: list[str] | None = Field(None, description="Methods to include (default: all)")
    options: dict[str, Any] | None = Field(None)


class OptionsInfo(BaseModel):
    solver: str
    default_options: dict[str, Any]
    description: str


# ── Response models ─────────────────────────────────────────

class BusResult(BaseModel):
    bus_id: int
    type: int
    voltage_pu: float
    angle_deg: float
    P_gen: float
    Q_gen: float
    P_load: float
    Q_load: float


class LineResult(BaseModel):
    from_bus: int
    to_bus: int
    P_from: float
    Q_from: float
    P_loss: float
    Q_loss: float


class SolverResult(BaseModel):
    system_name: str
    method: str
    converged: bool
    iterations: int
    P_loss_total: float
    Q_loss_total: float
    P_total_gen: float
    Q_total_gen: float
    P_total_load: float
    Q_total_load: float
    buses: list[BusResult]
    lines: list[LineResult]
    mismatch_history: list[float]
    execution_time_ms: float | None = None
    metadata: dict[str, Any]
    solver_specific: dict[str, Any] | None = None


class SolveResponse(BaseModel):
    result: SolverResult
    case_name: str


class CaseListItem(BaseModel):
    name: str
    system_name: str
    bus_count: int
    line_count: int


class CaseListResponse(BaseModel):
    cases: list[CaseListItem]


class CaseDetailResponse(BaseModel):
    name: str
    system_name: str
    bus_count: int
    line_count: int
    base_MVA: float | None = None
    bus_data: list[list[float]]
    line_data: list[list[float]]


class CompareResponse(BaseModel):
    case_name: str
    methods: list[str]
    results: list[SolverResult]
    summary: dict[str, Any]


class BenchmarkResponse(BaseModel):
    case_name: str
    results: list[SolverResult]
    ranking: dict[str, Any]


class HealthResponse(BaseModel):
    status: str = "ok"
    version: str = "1.0.0"
    solvers: list[str]
    cases: list[str]


# ── Helper: convert raw result dict to SolverResult ─────────

def result_to_response(raw: dict, elapsed_ms: float | None = None) -> SolverResult:
    """Convert solver result dict (numpy arrays) to JSON-safe SolverResult.

    Handles both standard PF results (bus voltages, line flows) and
    optimization results (ED/OPF) which have different structures.
    """
    meta = raw.get("metadata", {})
    n_bus = meta.get("num_buses", 0) if isinstance(meta, dict) else 0
    n_lines = meta.get("num_lines", 0) if isinstance(meta, dict) else 0

    # Bus results — only for PF solvers that have bus_voltage
    buses: list[BusResult] = []
    ext_ids = raw.get("external_bus_ids", [])
    bus_voltage = raw.get("bus_voltage", [])
    if len(ext_ids) > 0 and len(bus_voltage) > 0:
        n = min(len(ext_ids), len(bus_voltage))
        bus_type = raw.get("bus_type", [0] * n)
        bus_ang = raw.get("bus_angle_deg", [0.0] * n)
        p_gen = raw.get("P_generation", [0.0] * n)
        q_gen = raw.get("Q_generation", [0.0] * n)
        p_load = raw.get("P_load", [0.0] * n)
        q_load = raw.get("Q_load", [0.0] * n)
        for i in range(n):
            bt = int(bus_type[i]) if bus_type is not None else 0
            buses.append(BusResult(
                bus_id=int(ext_ids[i]),
                type=bt,
                voltage_pu=round(float(bus_voltage[i]), 6),
                angle_deg=round(float(bus_ang[i]), 4),
                P_gen=round(float(p_gen[i]), 6),
                Q_gen=round(float(q_gen[i]), 6),
                P_load=round(float(p_load[i]), 6),
                Q_load=round(float(q_load[i]), 6),
            ))

    # Line results — only for PF solvers
    lines: list[LineResult] = []
    line_eps = raw.get("line_endpoints")
    line_p = raw.get("line_flow_P")
    if line_eps is not None and line_p is not None and len(line_eps) > 0:
        n = len(line_eps)
        line_q = raw.get("line_flow_Q")
        line_pl = raw.get("line_loss_P")
        line_ql = raw.get("line_loss_Q")
        for i in range(n):
            ep = line_eps[i]
            if hasattr(ep, '__getitem__'):
                fb, tb = int(ep[0]), int(ep[1])
            else:
                fb, tb = int(line_eps[i, 0]), int(line_eps[i, 1])
            qf = float(line_q[i]) if line_q is not None else 0.0
            pl = float(line_pl[i]) if line_pl is not None else 0.0
            ql = float(line_ql[i]) if line_ql is not None else 0.0
            lines.append(LineResult(
                from_bus=fb,
                to_bus=tb,
                P_from=round(float(line_p[i]), 6),
                Q_from=round(qf, 6),
                P_loss=round(pl, 6),
                Q_loss=round(ql, 6),
            ))

    mis_hist = raw.get("mismatch_history", [])
    if hasattr(mis_hist, '__iter__') and not isinstance(mis_hist, (str, bytes)):
        mis_list = [float(x) for x in mis_hist]
    else:
        mis_list = []

    # Extract solver-specific data
    solver_specific = {}
    for k in ("lambda", "total_cost", "P_target", "P_dispatched", "P_mismatch",
              "P_generation", "P_min", "P_max", "incremental_cost", "active_generators",
              "cost_coefficients", "cpf_lambda_final", "cpf_nose_lambda", "cpf_steps",
              "cpf_pv_curve", "homotopy_final_lambda", "opf_total_cost", "opf_P_gen",
              "opf_V_gen", "opf_gen_buses", "options"):
        if k in raw:
            val = raw[k]
            if isinstance(val, (list, dict, str, int, float, bool, type(None))):
                solver_specific[k] = val
            elif hasattr(val, 'tolist'):
                solver_specific[k] = val.tolist()
            else:
                solver_specific[k] = float(val) if hasattr(val, '__float__') else str(val)

    return SolverResult(
        system_name=str(raw.get("system_name", "")),
        method=str(raw.get("method", "")),
        converged=bool(raw.get("converged", False)),
        iterations=int(raw.get("iterations", 0)),
        P_loss_total=round(float(raw.get("P_loss_total", 0)), 6),
        Q_loss_total=round(float(raw.get("Q_loss_total", 0)), 6),
        P_total_gen=round(float(raw.get("P_total_gen", raw.get("P_dispatched", 0))), 6),
        Q_total_gen=round(float(raw.get("Q_total_gen", 0)), 6),
        P_total_load=round(float(raw.get("P_total_load", raw.get("P_load_total", raw.get("P_target", 0)))), 6),
        Q_total_load=round(float(raw.get("Q_total_load", 0)), 6),
        buses=buses,
        lines=lines,
        mismatch_history=mis_list,
        execution_time_ms=round(elapsed_ms, 2) if elapsed_ms else raw.get("execution_time_ms"),
        metadata={
            "num_buses": n_bus,
            "num_lines": n_lines,
            "base_values": {k: v for k, v in raw.get("base_values", {}).items()} if raw.get("base_values") else {},
        },
        solver_specific=solver_specific if solver_specific else None,
    )
