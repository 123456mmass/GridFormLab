"use client";

import {
  Bar,
  BarChart,
  CartesianGrid,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { ChartContainer } from "@/components/ChartContainer";
import type { BusResult } from "@/lib/types";
import { useLanguage } from "@/i18n";

export function AngleProfileChart({ buses }: { buses: BusResult[] }) {
  const { t } = useLanguage();
  if (!buses || buses.length === 0) return null;

  const data = buses.map((b) => ({
    bus: `${b.bus_id}`,
    angle: b.angle_deg,
  }));

  return (
    <ChartContainer height={260}>
        <BarChart data={data} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
          <CartesianGrid vertical={false} stroke="#e2e8f0" strokeDasharray="3 3" />
          <XAxis
            dataKey="bus"
            axisLine={{ stroke: '#cbd5e1' }}
            tickLine={false}
            tick={{ fontSize: 11, fill: "#64748b", fontWeight: 500 }}
            dy={10}
          />
          <YAxis
            axisLine={{ stroke: '#cbd5e1' }}
            tickLine={false}
            tick={{ fontSize: 11, fill: "#64748b", fontWeight: 500 }}
          />
          <Tooltip
            cursor={{ fill: "#f1f5f9" }}
            contentStyle={{
              border: "1px solid #e2e8f0",
              borderRadius: "12px",
              boxShadow: "0 10px 15px -3px rgba(0, 0, 0, 0.05)",
              padding: "10px 14px",
            }}
            formatter={(v: unknown) => [Number(v).toFixed(2) + "°", t("chart.angle.tooltip")]}
          />
          <Bar
            dataKey="angle"
            fill="#8b5cf6" 
            radius={[4, 4, 0, 0]}
            maxBarSize={32}
            animationDuration={800}
          />
        </BarChart>
    </ChartContainer>
  );
}
