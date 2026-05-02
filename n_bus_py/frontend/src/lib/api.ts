// ── API client for backend ─────────────────────────────────
import type {
  BenchmarkResponse,
  CaseDetail,
  CaseListItem,
  CompareResponse,
  Persona,
  SessionSummary,
  SolverInfo,
  SolveResponse,
} from "./types";
import { getAccessToken, refreshAccessToken, clearTokens } from "./auth";

export const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";

async function fetchJSON<T>(path: string, init?: RequestInit): Promise<T> {
  const token = getAccessToken();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...((init?.headers as Record<string, string>) || {}),
  };
  if (token) headers["Authorization"] = `Bearer ${token}`;

  let res = await fetch(`${API_BASE_URL}${path}`, { ...init, headers });

  if (res.status === 401 && token) {
    const newToken = await refreshAccessToken();
    if (newToken) {
      headers["Authorization"] = `Bearer ${newToken}`;
      res = await fetch(`${API_BASE_URL}${path}`, { ...init, headers });
    }
  }

  if (res.status === 401) {
    clearTokens();
    if (typeof window !== "undefined") window.location.href = "/login";
    throw new Error("Session expired");
  }

  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error((body as { detail?: string }).detail || res.statusText);
  }
  return res.json() as Promise<T>;
}

// ── Health ─────────────────────────────────────────────────
export function getHealth(): Promise<{ status: string; solvers: string[]; cases: string[] }> {
  return fetchJSON("/api/health");
}

// ── Cases ──────────────────────────────────────────────────
export function listCases(): Promise<{ cases: CaseListItem[] }> {
  return fetchJSON("/api/cases");
}

export function getCase(name: string): Promise<CaseDetail> {
  return fetchJSON(`/api/cases/${name}`);
}

// ── Solvers ────────────────────────────────────────────────
export function listSolvers(): Promise<SolverInfo[]> {
  return fetchJSON("/api/solvers");
}

export function solve(
  method: string,
  caseName: string,
  options?: Record<string, unknown>
): Promise<SolveResponse> {
  return fetchJSON<SolveResponse>(`/api/solve/${method}`, {
    method: "POST",
    body: JSON.stringify({ case_name: caseName, options }),
  });
}

// ── Compare / Benchmark ────────────────────────────────────
export function compare(
  caseName: string,
  methods: string[],
  options?: Record<string, unknown>
): Promise<CompareResponse> {
  return fetchJSON<CompareResponse>("/api/compare", {
    method: "POST",
    body: JSON.stringify({ case_name: caseName, methods, options }),
  });
}

export function benchmark(
  caseName: string,
  methods?: string[],
  options?: Record<string, unknown>
): Promise<BenchmarkResponse> {
  return fetchJSON<BenchmarkResponse>("/api/benchmark", {
    method: "POST",
    body: JSON.stringify({ case_name: caseName, methods, options }),
  });
}

// ── AI ─────────────────────────────────────────────────────
export async function* askStream(
  question: string,
  conversationId?: string,
  resultsJson?: string,
  model?: string,
  files?: File[],
): AsyncGenerator<{ token?: string; thinking?: string; done?: boolean; conversation_id?: string; error?: string }> {
  const token = getAccessToken();
  const headers: Record<string, string> = {};
  if (token) headers["Authorization"] = `Bearer ${token}`;

  let body: FormData | string;
  if (files && files.length > 0) {
    const fd = new FormData();
    fd.set("question", question);
    if (conversationId) fd.set("conversation_id", conversationId);
    if (resultsJson) fd.set("results_json", resultsJson);
    if (model) fd.set("model", model);
    for (const f of files) fd.append("files", f);
    body = fd;
  } else {
    headers["Content-Type"] = "application/json";
    body = JSON.stringify({ question, conversation_id: conversationId, results_json: resultsJson, model });
  }

  const res = await fetch(`${API_BASE_URL}/ai/ask/stream`, {
    method: "POST",
    headers,
    body,
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error((body as { detail?: string; error?: string }).detail || (body as { error?: string }).error || res.statusText);
  }
  const reader = res.body?.getReader();
  if (!reader) throw new Error("No response stream");
  const decoder = new TextDecoder();
  let buffer = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n\n");
    buffer = lines.pop() || "";
    for (const line of lines) {
      const m = line.match(/^data: (.+)$/m);
      if (m) {
        try {
          yield JSON.parse(m[1]);
        } catch {
          // skip malformed chunks
        }
      }
    }
  }
}

export function aiAnalyze(payload: {
  method: string;
  system_name?: string;
  num_buses?: number;
  num_lines?: number;
  iterations: number;
  converged: boolean;
  P_loss_total?: number;
  Q_loss_total?: number;
  bus_data?: Record<string, unknown>;
  mismatch_history?: number[];
}) {
  return fetchJSON("/ai/analyze", { method: "POST", body: JSON.stringify(payload) });
}

// ── Sessions ───────────────────────────────────────────────

export function listSessions(type?: string): Promise<SessionSummary[]> {
  const qs = type ? `?type=${type}` : "";
  return fetchJSON(`/ai/sessions${qs}`);
}

export function createSession(title: string, sessionType: string = "chat"): Promise<{ id: string }> {
  return fetchJSON("/ai/sessions", {
    method: "POST",
    body: JSON.stringify({ title, session_type: sessionType }),
  });
}

export function getSession(id: string): Promise<{
  id: string;
  messages: { role: string; content: string }[];
  analysis_context?: Record<string, unknown>;
  session_type?: string;
}> {
  return fetchJSON(`/ai/sessions/${id}`);
}

export function deleteSession(id: string): Promise<void> {
  return fetchJSON(`/ai/sessions/${id}`, { method: "DELETE" });
}

// ── Personas ───────────────────────────────────────────────

export function listPersonas(): Promise<Persona[]> {
  return fetchJSON("/ai/personas");
}

export function savePersona(data: Partial<Persona>): Promise<Persona> {
  return fetchJSON("/ai/personas", { method: "POST", body: JSON.stringify(data) });
}

export function updatePersona(id: number, data: Partial<Persona>): Promise<void> {
  return fetchJSON(`/ai/personas/${id}`, { method: "PUT", body: JSON.stringify(data) });
}

export function deletePersona(id: number): Promise<void> {
  return fetchJSON(`/ai/personas/${id}`, { method: "DELETE" });
}
