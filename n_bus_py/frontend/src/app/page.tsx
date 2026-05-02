"use client";

import type { LucideIcon } from "lucide-react";
import { useMemo, useState } from "react";
import {
  Activity,
  ArrowRight,
  CheckCircle2,
  Clock,
  Play,
  Zap,
} from "lucide-react";
import { benchmark } from "@/lib/api";
import { SOLVER_LIST, type SolverResult } from "@/lib/types";
import { useLanguage, useTranslatedSolverList } from "@/i18n";

function loadCachedResults() {
  if (typeof window === "undefined") return [];
  const cached = window.sessionStorage.getItem("dashboard_benchmark");
  if (!cached) return [];
  try {
    return JSON.parse(cached) as SolverResult[];
  } catch {
    return [];
  }
}

export default function DashboardPage() {
  const { t } = useLanguage();
  const translatedSolvers = useTranslatedSolverList();
  const [loading, setLoading] = useState(false);
  const [results, setResults] = useState<SolverResult[]>(loadCachedResults);

  async function runAll() {
    setLoading(true);
    try {
      const data = await benchmark("ieee5bus");
      setResults(data.results);
      sessionStorage.setItem("dashboard_benchmark", JSON.stringify(data.results));
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  }

  const converged = results.filter((r) => r.converged).length;
  const avgMs = results.length > 0
    ? results.reduce((s, r) => s + (r.execution_time_ms || 0), 0) / results.length
    : 0;
  const resultsByMethod = useMemo(() => {
    return new Map(results.map((r) => [r.method.toLowerCase(), r]));
  }, [results]);

  return (
    <div className="p-10 max-w-7xl mx-auto space-y-12">
      {/* Header */}
      <div className="flex items-end justify-between">
        <div>
          <h1 className="text-4xl font-extrabold text-slate-900 tracking-tight">
            {t("nav.powerFlow")} <span className="text-blue-600">Studio</span>
          </h1>
          <p className="text-slate-500 mt-2 font-medium">
            {t("dashboard.subtitle")}
          </p>
        </div>
        <button
          onClick={runAll}
          disabled={loading}
          className="btn-gradient px-8 py-3.5 flex items-center gap-2 text-sm font-bold disabled:opacity-50"
        >
          {loading ? <Activity className="w-4 h-4 animate-spin" /> : <Play className="w-4 h-4 fill-current" />}
          {loading ? t("dashboard.running") : t("dashboard.runBenchmark")}
        </button>
      </div>

      {/* Highlights */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <HighlightCard
          icon={CheckCircle2}
          label={t("dashboard.convergence")}
          value={`${converged} / ${results.length || 12}`}
          desc={t("dashboard.methodsReached")}
          color="text-emerald-600"
          bg="bg-emerald-50"
        />
        <HighlightCard
          icon={Clock}
          label={t("dashboard.avgPerformance")}
          value={`${avgMs.toFixed(1)} ms`}
          desc={t("dashboard.meanExecTime")}
          color="text-blue-600"
          bg="bg-blue-50"
        />
        <HighlightCard
          icon={Zap}
          label={t("dashboard.activeSolvers")}
          value="12"
          desc={t("dashboard.availableMethods")}
          color="text-amber-600"
          bg="bg-amber-50"
        />
      </div>

      {/* Solver Explorer */}
      <div className="space-y-8">
        <div className="flex items-center gap-4">
          <h2 className="text-xl font-bold text-slate-800">{t("dashboard.methodologies")}</h2>
          <div className="h-px flex-1 bg-slate-200" />
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {translatedSolvers.map((s) => {
            const res = resultsByMethod.get(s.name.toLowerCase());
            return (
              <button
                type="button"
                key={s.name}
                onClick={() => window.location.assign(`/methodology/${s.name}`)}
                className="card-glass group p-6 bg-white border border-slate-200 rounded-3xl hover:border-blue-400 hover:shadow-xl hover:shadow-blue-50 transition-all cursor-pointer relative overflow-hidden text-left"
              >
                <div className="relative z-10">
                  <div className="flex items-center justify-between mb-4">
                    <span className="text-[10px] font-bold uppercase tracking-widest text-slate-400">
                      {s.category}
                    </span>
                    {res && (
                      res.converged ?
                      <div className="w-2 h-2 rounded-full bg-emerald-500 shadow-lg shadow-emerald-200" /> :
                      <div className="w-2 h-2 rounded-full bg-red-500 shadow-lg shadow-red-200" />
                    )}
                  </div>
                  <h3 className="text-lg font-bold text-slate-900 group-hover:text-blue-600 transition-colors">
                    {s.alias}
                  </h3>
                  <p className="text-sm text-slate-500 mt-2 line-clamp-2 leading-relaxed">
                    {s.description}
                  </p>
                  <div className="mt-6 flex items-center gap-2 text-blue-600 font-bold text-xs opacity-0 group-hover:opacity-100 transition-all transform translate-y-2 group-hover:translate-y-0">
                    {t("dashboard.readMethodology")} <ArrowRight className="w-3 h-3" />
                  </div>
                </div>
                {/* Decorative element */}
                <div className="absolute -right-4 -bottom-4 w-20 h-20 bg-slate-50 rounded-full group-hover:bg-blue-50 transition-colors" />
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

interface HighlightCardProps {
  icon: LucideIcon;
  label: string;
  value: string;
  desc: string;
  color: string;
  bg: string;
}

function HighlightCard({ icon: Icon, label, value, desc, color, bg }: HighlightCardProps) {
  return (
    <div className="p-8 bg-white border border-slate-200 rounded-[2rem] shadow-sm flex items-start gap-6">
      <div className={`p-4 rounded-2xl ${bg}`}>
        <Icon className={`w-6 h-6 ${color}`} />
      </div>
      <div>
        <p className="text-xs font-bold text-slate-400 uppercase tracking-widest">{label}</p>
        <p className="text-3xl font-black text-slate-900 mt-1">{value}</p>
        <p className="text-xs text-slate-500 mt-1 font-medium">{desc}</p>
      </div>
    </div>
  );
}
