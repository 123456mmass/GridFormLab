"use client";

import { useState } from "react";
import { Activity, BarChart3, CheckCircle2, Play, Trophy, XCircle } from "lucide-react";
import { benchmark } from "@/lib/api";
import { SOLVER_LIST, type BenchmarkResponse } from "@/lib/types";
import { AnimatedCounter } from "@/components/AnimatedCounter";
import { SpeedBarChart } from "@/components/SpeedBarChart";
import { ConvergenceOverlayChart } from "@/components/ConvergenceOverlayChart";
import { useLanguage } from "@/i18n";

const MEDALS = ["🥇", "🥈", "🥉"];

export default function BenchmarkPage() {
  const { t } = useLanguage();
  const [loading, setLoading] = useState(false);
  const [data, setData] = useState<BenchmarkResponse | null>(null);
  const [error, setError] = useState("");
  const [selected, setSelected] = useState<string[]>(
    SOLVER_LIST.map((s) => s.name),
  );

  function toggleAll() {
    setSelected((prev) =>
      prev.length === SOLVER_LIST.length ? [] : SOLVER_LIST.map((s) => s.name),
    );
  }

  async function run() {
    setLoading(true);
    setError("");
    try {
      const res = await benchmark("ieee5bus", selected);
      setData(res);
    } catch (e) {
      setError(e instanceof Error ? e.message : t("benchmark.failed"));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-8">
      {/* Header */}
      <div className="flex items-start justify-between animate-fade-in">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-2xl bg-gradient-to-br from-amber-500 to-red-500 flex items-center justify-center shadow-lg shadow-amber-500/20">
            <BarChart3 className="w-5 h-5 text-white" />
          </div>
          <div>
            <h1 className="text-3xl font-black tracking-tight">
              <span className="text-gradient">{t("benchmark.title")}</span>
            </h1>
            <p className="text-text-dim text-sm">
              {t("benchmark.subtitle")}
            </p>
          </div>
        </div>
        <button
          onClick={run}
          disabled={loading}
          className="btn-gradient btn-gradient-hover rounded-2xl px-7 py-3 text-sm shadow-xl shadow-indigo-500/15"
        >
          {loading ? (
            <Activity className="w-4 h-4 animate-spin" />
          ) : (
            <Play className="w-4 h-4" />
          )}
          {loading ? t("benchmark.running") : t("benchmark.run")}
        </button>
      </div>

      {/* Solver selection */}
      <div className="card-glass animate-slide-up">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-xs font-semibold text-text-dim uppercase tracking-wider">
            {t("benchmark.solvers")} ({selected.length}/{SOLVER_LIST.length})
          </h3>
          <button
            onClick={toggleAll}
            className="text-[11px] text-primary hover:text-primary-dim transition-colors font-medium"
          >
            {selected.length === SOLVER_LIST.length ? t("benchmark.deselectAll") : t("benchmark.selectAll")}
          </button>
        </div>
        <div className="flex flex-wrap gap-1.5">
          {SOLVER_LIST.map((s) => {
            const isSelected = selected.includes(s.name);
            return (
              <button
                key={s.name}
                onClick={() =>
                  setSelected((prev) =>
                    prev.includes(s.name)
                      ? prev.filter((m) => m !== s.name)
                      : [...prev, s.name],
                  )
                }
                className={`badge cursor-pointer transition-all duration-200 py-1.5 px-3 text-[11px] ${
                  isSelected
                    ? "bg-primary/15 text-primary border border-primary/40"
                    : "bg-white/[0.03] text-text-muted border border-border hover:border-text-muted/30"
                }`}
              >
                {s.alias}
              </button>
            );
          })}
        </div>
      </div>

      {error && (
        <div className="card border-danger/30 text-danger text-sm animate-fade-in">{error}</div>
      )}

      {data && (
        <div className="space-y-6 animate-slide-up">
          {/* Speed Chart */}
          <div className="card-glass">
            <h3 className="font-semibold text-xs text-text-dim uppercase tracking-wider mb-4 flex items-center gap-2">
              <Trophy className="w-4 h-4 text-warning" />
              {t("benchmark.speedRanking")}
            </h3>
            <SpeedBarChart
              data={data.results.map((r) => ({
                method: r.method,
                execution_time_ms: r.execution_time_ms ?? 0,
                converged: r.converged,
              }))}
            />
          </div>

          {/* Speed ranking list with medals */}
          <div className="card-glass">
            <h3 className="font-semibold text-xs text-text-dim uppercase tracking-wider mb-4">
              {t("benchmark.speedLeaderboard")}
            </h3>
            <div className="space-y-1">
              {data.ranking.by_speed.map((r, i) => {
                const maxTime = data.ranking.by_speed[data.ranking.by_speed.length - 1]?.execution_time_ms || 1;
                const pct = Math.min(100, (r.execution_time_ms / maxTime) * 100);
                return (
                  <div
                    key={r.method}
                    className="flex items-center gap-3 text-sm py-2.5 px-3 rounded-xl hover:bg-white/[0.02] transition-colors"
                  >
                    <span className="w-8 text-center text-lg">
                      {i < 3 ? MEDALS[i] : <span className="text-text-muted text-xs font-bold">{i + 1}</span>}
                    </span>
                    <span className="w-28 font-semibold text-text text-xs truncate">
                      {r.method}
                    </span>
                    <div className="flex-1 h-2 bg-surface-alt rounded-full overflow-hidden">
                      <div
                        className="h-full rounded-full transition-all duration-700 ease-out"
                        style={{
                          width: `${pct}%`,
                          background: `linear-gradient(90deg, ${
                            i === 0 ? "#fbbf24, #f59e0b" :
                            i === 1 ? "#94a3b8, #64748b" :
                            i === 2 ? "#d97706, #b45309" :
                            "#38bdf8, #0284c7"
                          })`,
                        }}
                      />
                    </div>
                    <span className="w-20 text-right font-mono text-text-dim text-xs">
                      <AnimatedCounter value={r.execution_time_ms} decimals={1} suffix=" ms" />
                    </span>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Convergence overlay */}
          {data.results.some((r) => r.mismatch_history.length > 0) && (
            <div className="card-glass">
              <h3 className="font-semibold text-xs text-text-dim uppercase tracking-wider mb-4">
                {t("benchmark.convergenceComp")}
              </h3>
              <ConvergenceOverlayChart results={data.results} />
            </div>
          )}

          {/* Full results table */}
          <div className="card-glass overflow-x-auto">
            <h3 className="font-semibold text-xs text-text-dim uppercase tracking-wider mb-3">
              {t("benchmark.allResults")}
            </h3>
            <table className="premium-table">
              <thead>
                <tr>
                  <th>{t("table.method")}</th>
                  <th>{t("table.status")}</th>
                  <th>{t("table.iterations")}</th>
                  <th>{t("table.pLoss")}</th>
                  <th>{t("table.time")}</th>
                  <th>{t("table.minV")}</th>
                </tr>
              </thead>
              <tbody>
                {data.results.map((r) => {
                  const minV = r.buses.length > 0 ? Math.min(...r.buses.map((b) => b.voltage_pu)) : 0;
                  return (
                    <tr key={r.method}>
                      <td className="font-semibold text-text">{r.method}</td>
                      <td>
                        {r.converged ? (
                          <CheckCircle2 className="w-4 h-4 text-success" />
                        ) : (
                          <XCircle className="w-4 h-4 text-danger" />
                        )}
                      </td>
                      <td>{r.iterations}</td>
                      <td>{r.P_loss_total.toFixed(6)}</td>
                      <td className="text-text-dim">{r.execution_time_ms?.toFixed(1)} ms</td>
                      <td className="text-text-dim">{minV.toFixed(4)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
