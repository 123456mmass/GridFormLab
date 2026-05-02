"use client";

import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { ChartContainer } from "@/components/ChartContainer";
import type { SolverResult } from "@/lib/types";

interface ConvergenceOverlayChartProps {
  results: SolverResult[];
}

const COLORS = [
  "#3b82f6", "#10b981", "#8b5cf6", "#f59e0b", "#ef4444",
  "#06b6d4", "#22c55e", "#a855f7", "#f97316", "#ec4899",
];

export function ConvergenceOverlayChart({ results }: ConvergenceOverlayChartProps) {
  const filtered = results.filter((r) => r.mismatch_history.length > 0);
  if (filtered.length === 0) return null;

  const maxLen = Math.max(...filtered.map((r) => r.mismatch_history.length));
  const data = Array.from({ length: maxLen }, (_, i) => {
    const point: Record<string, unknown> = { iter: i + 1 };
    for (const r of filtered) {
      const label = r.method.replace("Newton-Raphson", "NR").replace("Gauss-Seidel", "GS");
      point[label] = r.mismatch_history[i] ?? null;
    }
    return point;
  });

  const keys = filtered.map((r) =>
    r.method.replace("Newton-Raphson", "NR").replace("Gauss-Seidel", "GS"),
  );

  return (
    <ChartContainer height={320}>
        <LineChart data={data} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
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
          <Tooltip
            contentStyle={{
              border: "1px solid #e2e8f0",
              borderRadius: "12px",
              boxShadow: "0 10px 15px -3px rgba(0, 0, 0, 0.05)",
              padding: "10px 14px",
              fontSize: "11px"
            }}
            formatter={(v: unknown) => [Number(v).toExponential(3), ""]}
          />
          <Legend wrapperStyle={{ fontSize: 11, paddingTop: 20 }} />
          {keys.map((key, i) => (
            <Line
              key={key}
              type="monotone"
              dataKey={key}
              stroke={COLORS[i % COLORS.length]}
              strokeWidth={2.5}
              dot={false}
              activeDot={{ r: 5 }}
              connectNulls
              animationDuration={1000}
            />
          ))}
        </LineChart>
    </ChartContainer>
  );
}
