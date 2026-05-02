"use client";

import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { ChartContainer } from "@/components/ChartContainer";
import { useLanguage } from "@/i18n";

interface SpeedBarChartProps {
  data: { method: string; execution_time_ms: number; converged: boolean }[];
}

const COLORS = [
  "#3b82f6", "#10b981", "#8b5cf6", "#f59e0b", "#ef4444",
  "#06b6d4", "#22c55e", "#a855f7", "#f97316", "#ec4899",
];

export function SpeedBarChart({ data }: SpeedBarChartProps) {
  const { t } = useLanguage();
  const sorted = [...data]
    .filter((d) => d.converged)
    .sort((a, b) => a.execution_time_ms - b.execution_time_ms);

  const chartData = sorted.map((d, i) => ({
    method: d.method.replace("Newton-Raphson", "NR").replace("Gauss-Seidel", "GS"),
    time: d.execution_time_ms,
    fill: COLORS[i % COLORS.length],
  }));

  return (
    <ChartContainer height={Math.max(200, chartData.length * 40)}>
        <BarChart data={chartData} layout="vertical" margin={{ top: 5, right: 40, left: 10, bottom: 5 }}>
          {/* Increased grid visibility */}
          <CartesianGrid horizontal={false} stroke="#e2e8f0" strokeDasharray="3 3" />
          <XAxis
            type="number"
            axisLine={{ stroke: '#cbd5e1' }}
            tickLine={false}
            stroke="#64748b"
            tick={{ fontSize: 10, fill: "#64748b", fontWeight: 500 }}
            tickFormatter={(v) => `${v.toFixed(1)}ms`}
          />
          <YAxis
            type="category"
            dataKey="method"
            axisLine={{ stroke: '#cbd5e1' }}
            tickLine={false}
            stroke="#64748b"
            tick={{ fontSize: 10, fill: "#64748b", fontWeight: 600 }}
            width={90}
          />
          <Tooltip
            cursor={{ fill: "#f1f5f9" }}
            contentStyle={{
              border: "1px solid #e2e8f0",
              borderRadius: "12px",
              boxShadow: "0 10px 15px -3px rgba(0, 0, 0, 0.05)",
              padding: "10px 14px",
            }}
            formatter={(v: unknown) => [`${Number(v).toFixed(2)} ms`, t("chart.time.label")]}
          />
          <Bar dataKey="time" radius={[0, 4, 4, 0]} maxBarSize={24} animationDuration={1000}>
            {chartData.map((entry, i) => (
              <Cell key={i} fill={entry.fill} fillOpacity={0.8} />
            ))}
          </Bar>
        </BarChart>
    </ChartContainer>
  );
}
