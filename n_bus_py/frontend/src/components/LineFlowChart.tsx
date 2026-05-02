"use client";

import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { ChartContainer } from "@/components/ChartContainer";
import type { LineResult } from "@/lib/types";
import { useLanguage } from "@/i18n";

export function LineFlowChart({ lines }: { lines: LineResult[] }) {
  const { t } = useLanguage();
  if (!lines || lines.length === 0) return null;

  const data = lines.map((l) => ({
    line: `${l.from_bus}→${l.to_bus}`,
    P_flow: l.P_from,
    P_loss: l.P_loss,
  }));

  return (
    <ChartContainer height={260}>
        <BarChart data={data} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
          {/* Increased grid visibility */}
          <CartesianGrid vertical={false} stroke="#e2e8f0" strokeDasharray="3 3" />
          <XAxis
            dataKey="line"
            axisLine={{ stroke: '#cbd5e1' }}
            tickLine={false}
            tick={{ fontSize: 10, fill: "#64748b", fontWeight: 500 }}
            dy={10}
          />
          <YAxis
            axisLine={{ stroke: '#cbd5e1' }}
            tickLine={false}
            tick={{ fontSize: 10, fill: "#64748b", fontWeight: 500 }}
          />
          <Tooltip
            cursor={{ fill: "#f1f5f9" }}
            contentStyle={{
              border: "1px solid #e2e8f0",
              borderRadius: "12px",
              boxShadow: "0 10px 15px -3px rgba(0, 0, 0, 0.05)",
              padding: "10px 14px",
            }}
          />
          <Legend iconType="circle" wrapperStyle={{ fontSize: 11, paddingTop: 10 }} />
          <Bar dataKey="P_flow" name={t("chart.flow.label")} fill="#3b82f6" radius={[4, 4, 0, 0]} maxBarSize={16} />
          <Bar dataKey="P_loss" name={t("chart.loss.label")} fill="#f59e0b" radius={[4, 4, 0, 0]} maxBarSize={16} />
        </BarChart>
    </ChartContainer>
  );
}
