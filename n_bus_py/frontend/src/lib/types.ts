// ── Solver types matching backend Pydantic models ──────────

export interface BusResult {
  bus_id: number;
  type: number;
  voltage_pu: number;
  angle_deg: number;
  P_gen: number;
  Q_gen: number;
  P_load: number;
  Q_load: number;
}

export interface LineResult {
  from_bus: number;
  to_bus: number;
  P_from: number;
  Q_from: number;
  P_loss: number;
  Q_loss: number;
}

export interface SolverResult {
  system_name: string;
  method: string;
  converged: boolean;
  iterations: number;
  P_loss_total: number;
  Q_loss_total: number;
  P_total_gen: number;
  Q_total_gen: number;
  P_total_load: number;
  Q_total_load: number;
  buses: BusResult[];
  lines: LineResult[];
  mismatch_history: number[];
  execution_time_ms: number | null;
  metadata: {
    num_buses: number;
    num_lines: number;
    base_values: Record<string, number>;
  };
  solver_specific: Record<string, unknown> | null;
}

export interface SolveResponse {
  result: SolverResult;
  case_name: string;
}

export interface CaseListItem {
  name: string;
  system_name: string;
  bus_count: number;
  line_count: number;
}

export interface CaseDetail {
  name: string;
  system_name: string;
  bus_count: number;
  line_count: number;
  base_MVA: number | null;
  bus_data: number[][];
  line_data: number[][];
}

export interface SolverInfo {
  solver: string;
  default_options: Record<string, unknown>;
  description: string;
}

export interface CompareSummary {
  num_converged: number;
  num_failed: number;
  fastest: string | null;
  fastest_ms: number | null;
  lowest_loss_method: string | null;
  lowest_P_loss: number | null;
}

export interface CompareResponse {
  case_name: string;
  methods: string[];
  results: SolverResult[];
  summary: CompareSummary;
}

export interface BenchmarkResponse {
  case_name: string;
  results: SolverResult[];
  ranking: {
    by_speed: { method: string; execution_time_ms: number }[];
    by_convergence: { method: string; converged: boolean; iterations: number }[];
  };
}

// ── Solver metadata ───────────────────────────────────────

export const SOLVER_LIST: { name: string; alias: string; category: string; description: string }[] = [
  { name: "newton-raphson", alias: "NR", category: "Classical", description: "Full Jacobian per iteration + Q-limit enforcement" },
  { name: "gauss-seidel", alias: "GS", category: "Classical", description: "Per-bus iterative update with acceleration" },
  { name: "fast-decoupled", alias: "FDLF", category: "Fast", description: "XB scheme with constant B' and B'' matrices" },
  { name: "dc-power-flow", alias: "DC", category: "Fast", description: "Linear P = Bθ approximation" },
  { name: "dishonest-nr", alias: "DNR", category: "Fast", description: "Frozen Jacobian for k iterations then rebuild" },
  { name: "helm", alias: "HELM", category: "Holomorphic", description: "Taylor series + Padé approximant, no initial guess" },
  { name: "helm-nr-hybrid", alias: "H-NR", category: "Holomorphic", description: "HELM warm-start → NR refinement" },
  { name: "dynamic-homotopy", alias: "Homotopy", category: "Continuation", description: "Natural parameter continuation λ: 0→1" },
  { name: "cpf-pc", alias: "CPF PC", category: "Continuation", description: "Arclength continuation for P-V curve tracing" },
  { name: "cpf-ls", alias: "CPF LS", category: "Continuation", description: "Load scaling CPF with repeated NR" },
  { name: "economic-dispatch", alias: "ED", category: "Optimization", description: "KKT conditions + iterative limit enforcement" },
  { name: "ac-opf", alias: "OPF", category: "Optimization", description: "Coordinate pattern search over P_gen and V" },
];

export const SOLVER_CATEGORIES = ["Classical", "Fast", "Holomorphic", "Continuation", "Optimization"] as const;

// ── Chat / Session types ───────────────────────────────────

export interface SessionSummary {
  id: string;
  title: string | null;
  session_type: "chat" | "analysis";
  message_count: number;
  created_at: string | null;
  last_access: string | null;
}

export interface Persona {
  id: number;
  name: string;
  ai_tone: string | null;
  ai_style: string | null;
  language_preference: string | null;
  custom_prompt: string | null;
  is_default: boolean;
}
