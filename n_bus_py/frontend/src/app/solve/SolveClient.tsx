"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useMemo, useState } from "react";
import {
  Activity,
  BarChart3,
  Bot,
  CircuitBoard,
  Flame,
  Gauge,
  LineChart,
  Play,
  Table2,
  TrendingDown,
  UploadCloud,
} from "lucide-react";
import { solve } from "@/lib/api";
import { SOLVER_LIST, type SolverResult } from "@/lib/types";
import { useLanguage, useTranslatedSolverList } from "@/i18n";
import { TabGroup } from "@/components/TabGroup";
import { BusTable } from "@/components/BusTable";
import { LineTable } from "@/components/LineTable";
import { MismatchChart } from "@/components/MismatchChart";
import { ResultSummary } from "@/components/ResultCard";
import { VoltageProfileChart } from "@/components/VoltageProfileChart";
import { AngleProfileChart } from "@/components/AngleProfileChart";
import { PowerBalanceChart } from "@/components/PowerBalanceChart";
import { LineFlowChart } from "@/components/LineFlowChart";
import { CPVCurveChart } from "@/components/CPVCurveChart";
import { DispatchChart } from "@/components/DispatchChart";
import { ImportModal } from "@/components/ImportModal";

type WorkflowKey = "pf" | "cpf" | "opt";

const WORKFLOWS: Record<
  WorkflowKey,
  {
    label: string;
    title: string;
    description: string;
    methods: string[];
  }
> = {
  pf: {
    label: "Power Flow",
    title: "Power Flow Studio",
    description: "Voltage, angle, line-flow, and convergence analysis",
    methods: [
      "newton-raphson",
      "gauss-seidel",
      "fast-decoupled",
      "dc-power-flow",
      "dishonest-nr",
      "helm",
      "helm-nr-hybrid",
      "dynamic-homotopy",
    ],
  },
  cpf: {
    label: "CPF Stability",
    title: "CPF Voltage Stability",
    description: "P-V curve tracing and loading margin analysis",
    methods: ["cpf-pc", "cpf-ls"],
  },
  opt: {
    label: "Optimization",
    title: "Dispatch and OPF",
    description: "Economic dispatch, OPF cost, and generator constraints",
    methods: ["economic-dispatch", "ac-opf"],
  },
};

const METHOD_ALIASES: Record<string, string> = {
  nr: "newton-raphson",
  gs: "gauss-seidel",
  fdlf: "fast-decoupled",
  dc: "dc-power-flow",
  dnr: "dishonest-nr",
  homotopy: "dynamic-homotopy",
  cpf_pc: "cpf-pc",
  cpf_ls: "cpf-ls",
  ed: "economic-dispatch",
  opf: "ac-opf",
};

const PF_TAB_KEYS = [
  { key: "overview", i18n: "tab.overview", icon: <CircuitBoard className="w-4 h-4" /> },
  { key: "voltages", i18n: "tab.voltages", icon: <BarChart3 className="w-4 h-4" /> },
  { key: "power", i18n: "tab.power", icon: <Flame className="w-4 h-4" /> },
  { key: "convergence", i18n: "tab.convergence", icon: <TrendingDown className="w-4 h-4" /> },
  { key: "data", i18n: "tab.data", icon: <Table2 className="w-4 h-4" /> },
];

const CPF_TAB_KEYS = [
  { key: "pv", i18n: "tab.pvCurve", icon: <LineChart className="w-4 h-4" /> },
  { key: "voltage", i18n: "tab.voltages", icon: <BarChart3 className="w-4 h-4" /> },
  { key: "data", i18n: "tab.data", icon: <Table2 className="w-4 h-4" /> },
];

const OPT_TAB_KEYS = [
  { key: "dispatch", i18n: "tab.dispatch", icon: <Gauge className="w-4 h-4" /> },
  { key: "power", i18n: "tab.network", icon: <Flame className="w-4 h-4" /> },
  { key: "data", i18n: "tab.data", icon: <Table2 className="w-4 h-4" /> },
];

const DEFAULT_CASES = [
  "ieee5bus",
  "ieee14bus",
  "ieee30bus",
  "ieee300bus",
  "saadat_ieee30bus",
  "saadat_example_6_7",
  "saadat_example_6_8",
];

function normalizeMethod(value: string | null) {
  if (!value) return null;
  const key = value.toLowerCase();
  return METHOD_ALIASES[key] ?? key;
}

function workflowForMethod(method: string): WorkflowKey {
  if (WORKFLOWS.cpf.methods.includes(method)) return "cpf";
  if (WORKFLOWS.opt.methods.includes(method)) return "opt";
  return "pf";
}

function defaultMethodFor(group: WorkflowKey) {
  return WORKFLOWS[group].methods[0];
}

function numberArray(value: unknown): number[] {
  return Array.isArray(value) ? value.map(Number).filter(Number.isFinite) : [];
}

function pvCurve(value: unknown): [number, number][] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((point) => {
    if (!Array.isArray(point) || point.length < 2) return [];
    const p = Number(point[0]);
    const v = Number(point[1]);
    return Number.isFinite(p) && Number.isFinite(v) ? [[p, v] as [number, number]] : [];
  });
}

function formatNumber(value: unknown, digits = 4) {
  const n = Number(value);
  return Number.isFinite(n) ? n.toFixed(digits) : "-";
}

export default function SolveClient() {
  const { t } = useLanguage();
  const translatedSolvers = useTranslatedSolverList();
  const router = useRouter();
  const searchParams = useSearchParams();
  const requestedMethod = normalizeMethod(searchParams.get("method"));
  const requestedGroup = (searchParams.get("group") as WorkflowKey | null) ?? null;
  const initialGroup =
    requestedMethod ? workflowForMethod(requestedMethod) : requestedGroup && requestedGroup in WORKFLOWS ? requestedGroup : "pf";
  const initialMethod =
    requestedMethod && WORKFLOWS[initialGroup].methods.includes(requestedMethod)
      ? requestedMethod
      : defaultMethodFor(initialGroup);

  const [workflow, setWorkflow] = useState<WorkflowKey>(initialGroup);
  const [method, setMethod] = useState(initialMethod);
  const [caseName, setCaseName] = useState("ieee5bus");
  const [availableCases, setAvailableCases] = useState(DEFAULT_CASES);
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<SolverResult | null>(null);
  const [activeTab, setActiveTab] = useState(workflow === "pf" ? "overview" : workflow === "cpf" ? "pv" : "dispatch");
  const [isImportOpen, setIsImportOpen] = useState(false);

  const workflowMeta = WORKFLOWS[workflow];
  const methods = useMemo(
    () => translatedSolvers.filter((solver) => workflowMeta.methods.includes(solver.name)),
    [translatedSolvers, workflowMeta.methods],
  );
  const solverMeta = translatedSolvers.find((s) => s.name === method) || methods[0] || translatedSolvers[0];

  function selectWorkflow(next: WorkflowKey) {
    const nextMethod = defaultMethodFor(next);
    setWorkflow(next);
    setMethod(nextMethod);
    setResult(null);
    setActiveTab(next === "pf" ? "overview" : next === "cpf" ? "pv" : "dispatch");
    router.replace(`/solve?group=${next}`);
  }

  function selectMethod(nextMethod: string) {
    setMethod(nextMethod);
    setResult(null);
    router.replace(`/solve?group=${workflow}&method=${nextMethod}`);
  }

  const run = useCallback(async () => {
    setLoading(true);
    try {
      const data = await solve(method, caseName);
      setResult(data.result);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  }, [method, caseName]);

  function handleAnalyze() {
    if (!result) return;
    try {
      sessionStorage.setItem("nbus_analyze_context", JSON.stringify(result));
    } catch { /* ignore quota */ }
    router.push("/analyze?from=solve");
  }

  const handleImportSuccess = (newCaseName: string) => {
    setAvailableCases((prev) => (prev.includes(newCaseName) ? prev : [...prev, newCaseName]));
    setCaseName(newCaseName);
  };

  return (
    <div className="bg-slate-50 min-h-screen">
      <div className="bg-white border-b border-slate-200 px-6 lg:px-10 py-6">
        <div className="max-w-7xl mx-auto space-y-5">
          <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-5">
            <div>
              <div className="flex flex-wrap items-center gap-3">
                <h1 className="text-2xl font-black text-slate-900 tracking-tight">{t(`solve.${workflow}.title`)}</h1>
                <span className="rounded-full bg-slate-100 border border-slate-200 px-3 py-1 text-xs font-bold text-slate-500">
                  {solverMeta.alias}
                </span>
              </div>
              <p className="text-xs text-slate-400 font-medium mt-1">{t(`solve.${workflow}.desc`)}</p>
            </div>
            <div className="flex flex-wrap items-center gap-3">
              <button
                onClick={() => setIsImportOpen(true)}
                className="flex items-center gap-2 px-3 py-2 rounded-xl text-sm font-semibold text-slate-600 bg-white border border-slate-200 hover:bg-slate-50 transition-colors shadow-sm"
                title="Import AI Case"
              >
                <UploadCloud className="w-4 h-4 text-blue-500" />
                <span className="hidden sm:inline">{t("solve.importData")}</span>
              </button>
              <select
                value={caseName}
                onChange={(e) => setCaseName(e.target.value)}
                className="bg-slate-50 border border-slate-200 rounded-xl px-4 py-2 text-sm font-semibold outline-none focus:ring-2 focus:ring-blue-500/20"
              >
                {availableCases.map((c) => (
                  <option key={c} value={c}>{c.toUpperCase()}</option>
                ))}
              </select>
              <button
                onClick={run}
                disabled={loading}
                className="btn-gradient px-8 py-2.5 flex items-center gap-2 text-sm font-bold shadow-blue-100"
              >
                {loading ? <Activity className="w-4 h-4 animate-spin" /> : <Play className="w-4 h-4 fill-current" />}
                {t("solve.run")}
              </button>
            </div>
          </div>

          <div className="flex flex-wrap gap-2">
            {(Object.keys(WORKFLOWS) as WorkflowKey[]).map((key) => (
              <button
                key={key}
                onClick={() => selectWorkflow(key)}
                className={`rounded-xl px-4 py-2 text-xs font-bold transition-colors ${
                  workflow === key
                    ? "bg-blue-600 text-white shadow-lg shadow-blue-100"
                    : "bg-slate-100 text-slate-500 hover:bg-slate-200"
                }`}
              >
                {key === "pf" ? t("nav.powerFlow") : key === "cpf" ? t("nav.cpfStability") : t("nav.optimization")}
              </button>
            ))}
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-3">
            {methods.map((solver) => (
              <button
                key={solver.name}
                onClick={() => selectMethod(solver.name)}
                className={`text-left rounded-2xl border p-4 transition-all ${
                  method === solver.name
                    ? "border-blue-400 bg-blue-50 shadow-sm"
                    : "border-slate-200 bg-white hover:border-slate-300"
                }`}
              >
                <div className="flex items-center justify-between gap-3">
                  <span className="text-sm font-black text-slate-900">{solver.alias}</span>
                  <span className="text-[10px] font-bold uppercase tracking-widest text-slate-400">{solver.category}</span>
                </div>
                <p className="mt-2 text-xs text-slate-500 leading-relaxed">{solver.description}</p>
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="p-6 lg:p-10 max-w-7xl mx-auto space-y-10">
        {result ? (
          <div className="animate-fade-in space-y-10">
            <div className="flex items-start justify-between gap-4 flex-wrap">
              <div className="flex-1"><ResultSummary result={result} /></div>
              <button
                onClick={handleAnalyze}
                className="flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm font-bold bg-gradient-to-r from-violet-500 to-fuchsia-500 text-white shadow-lg shadow-violet-200 hover:shadow-xl hover:shadow-violet-300 transition-all hover:scale-105"
              >
                <Bot className="w-4 h-4" />
                {t("solve.analyzeWithAI")}
              </button>
            </div>
            <div className="bg-white border border-slate-200 rounded-[2rem] shadow-sm overflow-hidden">
              <div className="px-8 pt-4 border-b border-slate-100 overflow-x-auto">
                <TabGroup
                  tabs={(workflow === "pf" ? PF_TAB_KEYS : workflow === "cpf" ? CPF_TAB_KEYS : OPT_TAB_KEYS).map(tab => ({ ...tab, label: t(tab.i18n) }))}
                  activeTab={activeTab}
                  onChange={setActiveTab}
                />
              </div>
              <div className="p-6 lg:p-10">
                {workflow === "pf" && <PowerFlowResults result={result} activeTab={activeTab} />}
                {workflow === "cpf" && <CpfResults result={result} activeTab={activeTab} />}
                {workflow === "opt" && <OptimizationResults result={result} activeTab={activeTab} />}
              </div>
            </div>
          </div>
        ) : (
          <div className="flex flex-col items-center justify-center py-28 text-center space-y-6">
            <div className="w-20 h-20 bg-white border border-slate-100 rounded-[2rem] flex items-center justify-center shadow-xl shadow-slate-200/50">
              <Play className="w-8 h-8 text-blue-600 fill-current ml-1" />
            </div>
            <div>
              <h2 className="text-xl font-bold text-slate-900">{t("solve.ready.title")}</h2>
              <p className="text-sm text-slate-400 mt-1">{t("solve.ready.desc")}</p>
            </div>
          </div>
        )}
      </div>

      <ImportModal
        isOpen={isImportOpen}
        onClose={() => setIsImportOpen(false)}
        onSuccess={handleImportSuccess}
      />
    </div>
  );
}

function PowerFlowResults({ result, activeTab }: { result: SolverResult; activeTab: string }) {
  const { t } = useLanguage();
  return (
    <>
      {activeTab === "overview" && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12">
          <ChartBlock title={t("chart.voltageMag")}><VoltageProfileChart buses={result.buses} /></ChartBlock>
          <ChartBlock title={t("chart.convergenceTrend")}><MismatchChart history={result.mismatch_history} converged={result.converged} /></ChartBlock>
        </div>
      )}
      {activeTab === "voltages" && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12">
          <ChartBlock title={t("chart.busVoltage")}><VoltageProfileChart buses={result.buses} /></ChartBlock>
          <ChartBlock title={t("chart.busAngle")}><AngleProfileChart buses={result.buses} /></ChartBlock>
        </div>
      )}
      {activeTab === "power" && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12">
          <ChartBlock title={t("chart.powerBalance")}><PowerBalanceChart buses={result.buses} /></ChartBlock>
          <ChartBlock title={t("chart.lineFlow")}><LineFlowChart lines={result.lines} /></ChartBlock>
        </div>
      )}
      {activeTab === "convergence" && (
        <div className="max-w-4xl mx-auto space-y-6">
          <ChartBlock title={t("chart.fullIterHistory")}><MismatchChart history={result.mismatch_history} converged={result.converged} /></ChartBlock>
        </div>
      )}
      {activeTab === "data" && <NetworkTables result={result} />}
    </>
  );
}

function CpfResults({ result, activeTab }: { result: SolverResult; activeTab: string }) {
  const { t } = useLanguage();
  const curve = pvCurve(result.solver_specific?.cpf_pv_curve);
  return (
    <>
      {activeTab === "pv" && (
        <div className="grid grid-cols-1 xl:grid-cols-[1fr_320px] gap-10">
          <ChartBlock title={t("chart.pvCurve")}>
            {curve.length > 0 ? <CPVCurveChart pvCurve={curve} /> : <EmptyState text={t("empty.noPVCurve")} />}
          </ChartBlock>
          <MetricPanel
            rows={[
              [t("metric.finalLambda"), formatNumber(result.solver_specific?.cpf_lambda_final, 3)],
              [t("metric.noseLambda"), formatNumber(result.solver_specific?.cpf_nose_lambda, 3)],
              [t("metric.curvePoints"), String(result.solver_specific?.cpf_steps ?? curve.length)],
              [t("metric.iterations"), String(result.iterations)],
            ]}
          />
        </div>
      )}
      {activeTab === "voltage" && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12">
          <ChartBlock title={t("chart.finalVoltageProfile")}><VoltageProfileChart buses={result.buses} /></ChartBlock>
          <ChartBlock title={t("chart.finalBusAngle")}><AngleProfileChart buses={result.buses} /></ChartBlock>
        </div>
      )}
      {activeTab === "data" && <NetworkTables result={result} />}
    </>
  );
}

function OptimizationResults({ result, activeTab }: { result: SolverResult; activeTab: string }) {
  const { t } = useLanguage();
  const specific = result.solver_specific ?? {};
  const pGen = numberArray(specific.P_generation).length > 0
    ? numberArray(specific.P_generation)
    : numberArray(specific.opf_P_gen);
  const pMin = numberArray(specific.P_min);
  const pMax = numberArray(specific.P_max);
  const incrementalCost = numberArray(specific.incremental_cost);
  return (
    <>
      {activeTab === "dispatch" && (
        <div className="grid grid-cols-1 xl:grid-cols-[1fr_320px] gap-10">
          <ChartBlock title={t("chart.generatorDispatch")}>
            {pGen.length > 0 ? (
              <DispatchChart P_gen={pGen} P_min={pMin} P_max={pMax} incrementalCost={incrementalCost} />
            ) : (
              <EmptyState text={t("empty.noDispatch")} />
            )}
          </ChartBlock>
          <MetricPanel
            rows={[
              [t("metric.totalCost"), formatNumber(specific.total_cost ?? specific.opf_total_cost, 4)],
              [t("metric.lambdaCost"), formatNumber(specific.lambda, 4)],
              [t("metric.pTarget"), formatNumber(specific.P_target, 4)],
              [t("metric.pDispatched"), formatNumber(specific.P_dispatched, 4)],
            ]}
          />
        </div>
      )}
      {activeTab === "power" && (
        result.buses.length > 0 ? (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-12">
            <ChartBlock title={t("chart.voltageProfile")}><VoltageProfileChart buses={result.buses} /></ChartBlock>
            <ChartBlock title={t("chart.powerBalance")}><PowerBalanceChart buses={result.buses} /></ChartBlock>
          </div>
        ) : (
          <EmptyState text={t("empty.edNoNetwork")} />
        )
      )}
      {activeTab === "data" && (result.buses.length > 0 ? <NetworkTables result={result} /> : <DispatchTable values={pGen} />)}
    </>
  );
}

function ChartBlock({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="space-y-4">
      <h3 className="text-sm font-bold text-slate-800 uppercase tracking-wider">{title}</h3>
      {children}
    </div>
  );
}

function MetricPanel({ rows }: { rows: [string, string][] }) {
  const { t } = useLanguage();
  return (
    <div className="bg-slate-50 border border-slate-200 rounded-2xl p-5 h-fit">
      <h3 className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-4">{t("metric.panelTitle")}</h3>
      <div className="space-y-3">
        {rows.map(([label, value]) => (
          <div key={label} className="flex items-center justify-between gap-4 border-b border-slate-200/70 pb-2 last:border-0 last:pb-0">
            <span className="text-xs font-semibold text-slate-500">{label}</span>
            <span className="text-sm font-black text-slate-900 tabular-nums">{value}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function NetworkTables({ result }: { result: SolverResult }) {
  const { t } = useLanguage();
  return (
    <div className="space-y-12">
      <ChartBlock title={t("chart.busAnalysisResults")}>
        <div className="border border-slate-100 rounded-2xl overflow-hidden"><BusTable buses={result.buses} /></div>
      </ChartBlock>
      <ChartBlock title={t("chart.lineFlowResults")}>
        <div className="border border-slate-100 rounded-2xl overflow-hidden"><LineTable lines={result.lines} /></div>
      </ChartBlock>
    </div>
  );
}

function DispatchTable({ values }: { values: number[] }) {
  const { t } = useLanguage();
  if (values.length === 0) return <EmptyState text={t("empty.noDispatchData")} />;
  return (
    <div className="overflow-x-auto border border-slate-100 rounded-2xl">
      <table className="premium-table">
        <thead><tr><th>{t("table.generator")}</th><th>{t("table.pDispatch")}</th></tr></thead>
        <tbody>
          {values.map((value, index) => (
            <tr key={index}><td>G{index + 1}</td><td>{value.toFixed(6)}</td></tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function EmptyState({ text }: { text: string }) {
  return (
    <div className="h-[240px] flex items-center justify-center rounded-2xl border border-dashed border-slate-200 bg-slate-50 text-sm font-semibold text-slate-400">
      {text}
    </div>
  );
}
