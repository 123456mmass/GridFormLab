"use client";

import type { LucideIcon } from "lucide-react";
import { CheckCircle2, Clock, Flame, Layers, XCircle } from "lucide-react";
import type { SolverResult } from "@/lib/types";
import { useLanguage } from "@/i18n";

export function ResultSummary({ result }: { result: SolverResult | null }) {
  const { t } = useLanguage();
  if (!result) return null;

  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-6 animate-fade-in">
      <StatBox
        icon={result.converged ? CheckCircle2 : XCircle}
        label={t("result.status")}
        value={result.converged ? t("result.converged") : t("result.failed")}
        color={result.converged ? "text-emerald-600" : "text-red-600"}
        bg={result.converged ? "bg-emerald-50" : "bg-red-50"}
      />
      <StatBox
        icon={Layers}
        label={t("result.iterations")}
        value={String(result.iterations)}
        color="text-violet-600"
        bg="bg-violet-50"
      />
      <StatBox
        icon={Clock}
        label={t("result.execution")}
        value={`${result.execution_time_ms?.toFixed(1) || 0} ms`}
        color="text-blue-600"
        bg="bg-blue-50"
      />
      <StatBox
        icon={Flame}
        label={t("result.activePowerLoss")}
        value={`${result.P_loss_total.toFixed(6)} pu`}
        color="text-amber-600"
        bg="bg-amber-50"
      />
    </div>
  );
}

interface StatBoxProps {
  icon: LucideIcon;
  label: string;
  value: string;
  color: string;
  bg: string;
}

function StatBox({ icon: Icon, label, value, color, bg }: StatBoxProps) {
  return (
    <div className="bg-white border border-slate-200 p-6 rounded-3xl flex items-center gap-5 shadow-sm">
      <div className={`p-3 rounded-2xl ${bg}`}>
        <Icon className={`w-5 h-5 ${color}`} />
      </div>
      <div>
        <p className="text-[10px] font-bold text-slate-400 uppercase tracking-widest">{label}</p>
        <p className={`text-lg font-black ${color} tabular-nums mt-0.5`}>{value}</p>
      </div>
    </div>
  );
}
