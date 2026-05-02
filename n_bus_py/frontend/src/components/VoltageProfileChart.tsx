"use client";

import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ReferenceLine,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { ChartContainer } from "@/components/ChartContainer";
import type { BusResult } from "@/lib/types";
import { useLanguage } from "@/i18n";

export function VoltageProfileChart({ buses }: { buses: BusResult[] }) {
  const { t } = useLanguage();
  if (!buses || buses.length === 0) return null;

  const data = buses.map((b) => ({
    bus: `${b.bus_id}`,
    voltage: b.voltage_pu,
  }));

  return (
    <ChartContainer height={260}>
        <BarChart data={data} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
          {/* Increased grid visibility */}
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
            domain={[0.9, 1.1]}
          />
          <ReferenceLine
            y={1.0}
            stroke="#94a3b8"
            strokeWidth={1}
            strokeDasharray="5 5"
            label={{ value: "1.0", position: "right", fill: "#64748b", fontSize: 10, fontWeight: 600 }}
          />
          <Tooltip
            cursor={{ fill: "#f1f5f9" }}
            contentStyle={{
              border: "1px solid #e2e8f0",
              borderRadius: "12px",
              boxShadow: "0 10px 15px -3px rgba(0, 0, 0, 0.05)",
              padding: "10px 14px",
            }}
            formatter={(v: unknown) => [Number(v).toFixed(4), t("chart.voltage.tooltip")]}
          />
          <Bar
            dataKey="voltage"
            radius={[4, 4, 0, 0]}
            maxBarSize={32}
            animationDuration={800}
          >
            {data.map((entry, index) => (
              <Cell
                key={`cell-${index}`}
                fill={
                  entry.voltage < 0.95
                    ? "#ef4444" 
                    : entry.voltage < 0.98
                    ? "#f59e0b" 
                    : "#3b82f6" 
                }
              />
            ))}
          </Bar>
        </BarChart>
    </ChartContainer>
  );
}
