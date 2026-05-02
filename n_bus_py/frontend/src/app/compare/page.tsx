"use client";

import { useState } from "react";
import { Activity, CheckCircle2, GitCompare, XCircle } from "lucide-react";
import { compare } from "@/lib/api";
import { SOLVER_CATEGORIES, SOLVER_LIST, type CompareResponse } from "@/lib/types";
import { MismatchChart } from "@/components/MismatchChart";
import { ConvergenceOverlayChart } from "@/components/ConvergenceOverlayChart";
import { useLanguage } from "@/i18n";

export default function ComparePage() {
  const { t } = useLanguage();
  const [selected, setSelected] = useState<string[]>([
    "newton-raphson",
    "fast-decoupled",
    "dc-power-flow",
  ]);
  const [loading, setLoading] = useState(false);
  const [data, setData] = useState<CompareResponse | null>(null);
  const [error, setError] = useState("");

  function toggle(method: string) {
    setSelected((prev) =>
      prev.includes(method)
        ? prev.filter((m) => m !== method)
        : [...prev, method],
    );
  }

  async function run() {
    if (selected.length < 2) return;
    setLoading(true);
    setError("");
    try {
      const res = await compare("ieee5bus", selected);
      setData(res);
    } catch (e) {
      setError(e instanceof Error ? e.message : t("compare.failed"));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-8">
      <div className="flex items-center gap-3 animate-fade-in">
        <div className="w-10 h-10 rounded-2xl bg-gradient-to-br from-emerald-500 to-teal-500 flex items-center justify-center shadow-lg shadow-emerald-500/20">
          <GitCompare className="w-5 h-5 text-white" />
        </div>
        <div>
          <h1 className="text-3xl font-black tracking-tight">
            <span className="text-gradient">{t("compare.title")}</span>
          </h1>
          <p className="text-text-dim text-sm">
            {t("compare.subtitle")}
          </p>
        </div>
      </div>

      {/* Solver selection by category */}
      <div className="card-glass animate-slide-up">
        <div className="space-y-3">
          {SOLVER_CATEGORIES.map((cat) => {
            const items = SOLVER_LIST.filter((s) => s.category === cat);
            return (
              <div key={cat}>
                <p className="text-[10px] text-text-muted uppercase tracking-widest mb-1.5 font-medium">{cat}</p>
                <div className="flex flex-wrap gap-1.5">
                  {items.map((s) => {
                    const isSelected = selected.includes(s.name);
                    return (
                      <button
                        key={s.name}
                        onClick={() => toggle(s.name)}
                        className={`badge cursor-pointer transition-all duration-200 py-1.5 px-3 text-[11px] ${
                          isSelected
                            ? "bg-primary/15 text-primary border border-primary/40 shadow-[0_0_10px_rgba(56,189,248,0.08)]"
                            : "bg-white/[0.03] text-text-muted border border-border hover:border-text-muted/30 hover:text-text-dim"
                        }`}
                      >
                        {s.alias}
                      </button>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
        <button
          onClick={run}
          disabled={loading || selected.length < 2}
          className="mt-4 btn-gradient btn-gradient-hover rounded-xl px-6 py-2.5 text-sm shadow-lg shadow-indigo-500/15"
        >
          {loading ? (
            <Activity className="w-4 h-4 animate-spin" />
          ) : (
            <GitCompare className="w-4 h-4" />
          )}
          {loading ? t("compare.comparing") : `${t("compare.btn")} (${selected.length})`}
        </button>
      </div>

      {error && (
        <div className="card border-danger/30 text-danger text-sm animate-fade-in">{error}</div>
      )}

      {data && (
        <div className="space-y-6 animate-slide-up">
          {/* Summary */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 stagger">
            <SummaryCard label={t("result.converged")} value={`${data.summary.num_converged}/${data.results.length}`} color="text-success" />
            <SummaryCard label={t("compare.fastest")} value={data.summary.fastest ?? "—"} sub={data.summary.fastest_ms ? `${data.summary.fastest_ms.toFixed(1)} ms` : ""} color="text-primary" />
            <SummaryCard label={t("compare.lowestLoss")} value={data.summary.lowest_loss_method ?? "—"} sub={data.summary.lowest_P_loss ? data.summary.lowest_P_loss.toFixed(6) : ""} color="text-accent" />
            <SummaryCard label={t("result.failed")} value={String(data.summary.num_failed)} color="text-danger" />
          </div>

          {/* Comparison table */}
          <div className="card-glass overflow-x-auto">
            <h3 className="font-semibold text-xs text-text-dim uppercase tracking-wider mb-3">
              {t("compare.results")}
            </h3>
            <table className="premium-table">
              <thead>
                <tr>
                  <th>{t("table.method")}</th>
                  <th>{t("table.status")}</th>
                  <th>{t("table.iterations")}</th>
                  <th>{t("table.pLoss")}</th>
                  <th>{t("table.qLoss")}</th>
                  <th>{t("table.time")}</th>
                  <th>{t("table.minV")}</th>
                </tr>
              </thead>
              <tbody>
                {data.results.map((r, i) => {
                  const minV = r.buses.length > 0 ? Math.min(...r.buses.map((b) => b.voltage_pu)) : 0;
                  return (
                    <tr key={i}>
                      <td className="font-semibold text-text">{data.methods[i]}</td>
                      <td>
                        {r.converged ? (
                          <CheckCircle2 className="w-4 h-4 text-success" />
                        ) : (
                          <XCircle className="w-4 h-4 text-danger" />
                        )}
                      </td>
                      <td>{r.iterations}</td>
                      <td>{r.P_loss_total.toFixed(6)}</td>
                      <td className="text-text-dim">{r.Q_loss_total.toFixed(6)}</td>
                      <td className="text-text-dim">{r.execution_time_ms?.toFixed(1)} ms</td>
                      <td className="text-text-dim">{minV.toFixed(4)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          {/* Convergence overlay */}
          {data.results.some((r) => r.mismatch_history.length > 0) && (
            <div className="card-glass">
              <h3 className="font-semibold text-xs text-text-dim uppercase tracking-wider mb-4">
                {t("compare.convergenceComp")}
              </h3>
              <ConvergenceOverlayChart results={data.results} />
            </div>
          )}

          {/* Individual convergence charts */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {data.results
              .filter((r) => r.mismatch_history.length > 0)
              .map((r, i) => (
                <div key={i} className="card-glass">
                  <h3 className="font-semibold text-xs text-text-dim uppercase tracking-wider mb-3">
                    {r.method}
                  </h3>
                  <MismatchChart history={r.mismatch_history} converged={r.converged} />
                </div>
              ))}
          </div>
        </div>
      )}
    </div>
  );
}

function SummaryCard({ label, value, sub, color }: { label: string; value: string; sub?: string; color: string }) {
  return (
    <div className="card-glass">
      <p className="text-[10px] text-text-muted uppercase tracking-widest font-medium mb-1">{label}</p>
      <p className={`text-lg font-bold ${color}`}>{value}</p>
      {sub && <p className="text-[11px] text-text-muted mt-0.5">{sub}</p>}
    </div>
  );
}
