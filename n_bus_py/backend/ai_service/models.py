"""Pydantic request/response models for AI analysis endpoints."""

from __future__ import annotations

import enum
from typing import Any, Literal

from pydantic import BaseModel, Field


class Assessment(str, enum.Enum):
    normal = "normal"
    caution = "caution"
    warning = "warning"


class StabilityRisk(str, enum.Enum):
    secure = "secure"
    marginal = "marginal"
    critical = "critical"


class AnalyzerFinding(BaseModel):
    assessment: Assessment = Field(..., description="Overall health assessment")
    observations: list[str] = Field(default_factory=list, max_length=20)
    issues: list[str] = Field(default_factory=list, max_length=20)
    recommendations: list[str] = Field(default_factory=list, max_length=20)


class CPFFinding(BaseModel):
    risk_level: StabilityRisk = Field(..., description="Voltage stability risk")
    loading_margin_pct: float | None = Field(None)
    nose_near: bool = Field(False)
    observations: list[str] = Field(default_factory=list, max_length=20)
    recommendations: list[str] = Field(default_factory=list, max_length=20)


class OPFFinding(BaseModel):
    optimal: bool = Field(..., description="Is the dispatch optimal?")
    binding_constraints: list[str] = Field(default_factory=list, max_length=20)
    cost_efficiency: str = Field("")
    observations: list[str] = Field(default_factory=list, max_length=20)


# ── Request models ──────────────────────────────────────────

class AnalyzeRequest(BaseModel):
    method: str = Field(..., min_length=1, max_length=100)
    system_name: str = Field("Unknown", max_length=200)
    num_buses: int = Field(0, ge=0, le=10000)
    num_lines: int = Field(0, ge=0, le=50000)
    iterations: int = Field(0, ge=0, le=100000)
    converged: bool = Field(True)
    P_loss_total: float = Field(0.0)
    Q_loss_total: float = Field(0.0)
    bus_data: dict[str, Any] | None = Field(None)
    mismatch_history: list[float] | None = Field(None, max_length=10000)


class CPFRequest(BaseModel):
    method: str = Field("CPF Predictor-Corrector", max_length=100)
    system_name: str = Field("Unknown", max_length=200)
    num_buses: int = Field(0, ge=0, le=10000)
    target_bus: int = Field(0)
    num_points: int = Field(0)
    nose_detected: bool = Field(False)
    lambda_min: float = Field(0.0)
    lambda_max: float = Field(0.0)
    voltage_min: float = Field(0.0)
    voltage_max: float = Field(0.0)
    stop_reason: str = Field("")
    lambdas: list[float] | None = Field(None, max_length=10000)
    target_voltage: list[float] | None = Field(None, max_length=10000)


class OPFRequest(BaseModel):
    system_name: str = Field("Unknown", max_length=200)
    demand_MW: float = Field(0.0)
    total_cost: float = Field(0.0)
    lambda_cost: float = Field(0.0, description="Incremental cost $/MWh")
    balance_residual: float = Field(0.0)
    generators: list[dict[str, Any]] | None = Field(None, max_length=200)


class AskRequest(BaseModel):
    question: str = Field(..., min_length=1, max_length=10000)
    results_json: str | None = Field(None, max_length=50000)
    conversation_id: str | None = Field(None, max_length=64)
    model: str | None = Field(None, max_length=100)
    persona_id: int | None = Field(None)
    session_title: str | None = Field(None, max_length=300)


class CompareRequest(BaseModel):
    method_a: str = Field(..., min_length=1, max_length=100)
    results_a: AnalyzeRequest = Field(...)
    method_b: str = Field(..., min_length=1, max_length=100)
    results_b: AnalyzeRequest = Field(...)


class ReportRequest(BaseModel):
    system_name: str = Field("Unknown", max_length=200)
    methods: list[AnalyzeRequest] = Field(..., min_length=1, max_length=20)
    cpf_result: CPFRequest | None = Field(None)
    opf_result: OPFRequest | None = Field(None)
    include_recommendations: bool = Field(True)
    language: Literal["en", "th"] = Field("en")


# ── Response models ─────────────────────────────────────────

class AnalysisResponse(BaseModel):
    analysis: str = Field(...)
    structured: AnalyzerFinding | None = Field(None)


class CPFAnalysisResponse(BaseModel):
    analysis: str
    structured: CPFFinding | None = Field(None)


class OPFAnalysisResponse(BaseModel):
    analysis: str
    structured: OPFFinding | None = Field(None)


class CompareResponse(BaseModel):
    analysis: str = Field(...)
    winner: str | None = Field(None)
    comparison_table: list[dict[str, Any]] | None = Field(None)


class ReportResponse(BaseModel):
    report: str = Field(...)


class AskResponse(BaseModel):
    answer: str = Field(...)
    conversation_id: str | None = Field(None)


class HealthResponse(BaseModel):
    status: str = Field("ok")
    version: str = Field("2.0.0")
    api_status: str = Field("unknown")
    uptime_sec: float = Field(0.0)
