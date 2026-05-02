"use client";

import {
  Area,
  CartesianGrid,
  ComposedChart,
  Line,
  ReferenceLine,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { ChartContainer } from "@/components/ChartContainer";
import { useLanguage } from "@/i18n";

interface MismatchChartProps {
  history: number[];
  converged: boolean;
  tolerance?: number;
}

export function MismatchChart({ history, converged, tolerance = 1e-6 }: MismatchChartProps) {
  const { t } = useLanguage();
  if (!history || history.length === 0) return (
    <div className="h-[240px] flex items-center justify-center text-slate-400 text-sm font-medium">
      {t("chart.noConvergenceData")}
    </div>
  );

  const data = history.map((v, i) => ({
    iter: i + 1,
    mismatch: v,
  }));

  return (
    <ChartContainer height={260}>
        <ComposedChart data={data} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
          <defs>
            <linearGradient id="mismatchGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor={converged ? "#10b981" : "#ef4444"} stopOpacity={0.1}/>
              <stop offset="95%" stopColor={converged ? "#10b981" : "#ef4444"} stopOpacity={0}/>
            </linearGradient>
          </defs>
          <CartesianGrid vertical={false} stroke="#e2e8f0" strokeDasharray="3 3" />
          <XAxis
            dataKey="iter"
            axisLine={{ stroke: '#cbd5e1' }}
            tickLine={false}
            tick={{ fontSize: 11, fill: "#64748b", fontWeight: 500 }}
            dy={10}
          />
          <YAxis
            scale="log"
            domain={["auto", "auto"]}
            axisLine={{ stroke: '#cbd5e1' }}
            tickLine={false}
            tick={{ fontSize: 10, fill: "#64748b", fontWeight: 500 }}
            tickFormatter={(v) => v.toExponential(0)}
          />
          <ReferenceLine
            y={tolerance}
            stroke="#ef4444"
            strokeDasharray="3 3"
            strokeWidth={1.5}
            label={{ value: t("chart.mismatch.target"), position: "right", fill: "#ef4444", fontSize: 9, fontWeight: 700 }}
          />
          <Tooltip
            cursor={{ stroke: "#cbd5e1", strokeWidth: 1 }}
            contentStyle={{
              border: "1px solid #e2e8f0",
              borderRadius: "12px",
              boxShadow: "0 10px 15px -3px rgba(0, 0, 0, 0.05)",
              padding: "10px 14px",
            }}
            formatter={(v: unknown) => [Number(v).toExponential(4), t("chart.mismatch.label")]}
          />
          <Area
            type="monotone"
            dataKey="mismatch"
            fill="url(#mismatchGrad)"
            stroke="none"
          />
          <Line
            type="monotone"
            dataKey="mismatch"
            stroke={converged ? "#10b981" : "#ef4444"}
            strokeWidth={3}
            dot={{ r: 4, fill: "#fff", stroke: converged ? "#10b981" : "#ef4444", strokeWidth: 2 }}
            activeDot={{ r: 6, strokeWidth: 0 }}
            animationDuration={1000}
          />
        </ComposedChart>
    </ChartContainer>
  );
}
