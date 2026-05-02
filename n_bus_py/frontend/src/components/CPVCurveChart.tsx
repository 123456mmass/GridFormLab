"use client";

import {
  CartesianGrid,
  Line,
  LineChart,
  ReferenceDot,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { ChartContainer } from "@/components/ChartContainer";
import { useLanguage } from "@/i18n";

interface CPVCurveChartProps {
  pvCurve: [number, number][];
}

export function CPVCurveChart({ pvCurve }: CPVCurveChartProps) {
  const { t } = useLanguage();
  if (!pvCurve || pvCurve.length === 0) return null;

  const data = pvCurve.map(([p, v]) => ({
    P: p,
    V: v,
  }));

  const criticalPoint = data.reduce((prev, current) => (current.P > prev.P ? current : prev), data[0]);

  return (
    <ChartContainer height={320}>
        <LineChart data={data} margin={{ top: 20, right: 30, left: -20, bottom: 10 }}>
          {/* Increased grid visibility */}
          <CartesianGrid vertical={false} stroke="#e2e8f0" strokeDasharray="3 3" />
          <XAxis
            dataKey="P"
            type="number"
            axisLine={{ stroke: '#cbd5e1' }}
            tickLine={false}
            tick={{ fontSize: 10, fill: "#64748b", fontWeight: 500 }}
            label={{ value: t("chart.loadP.label"), position: "insideBottom", offset: -5, style: { fill: "#64748b", fontSize: 11, fontWeight: 600 } }}
          />
          <YAxis
            type="number"
            domain={["auto", "auto"]}
            axisLine={{ stroke: '#cbd5e1' }}
            tickLine={false}
            tick={{ fontSize: 10, fill: "#64748b", fontWeight: 500 }}
            label={{ value: t("chart.voltageV.label"), angle: -90, position: "insideLeft", offset: 25, style: { fill: "#64748b", fontSize: 11, fontWeight: 600 } }}
          />
          <Tooltip
            contentStyle={{
              border: "1px solid #e2e8f0",
              borderRadius: "12px",
              boxShadow: "0 10px 15px -3px rgba(0, 0, 0, 0.05)",
              padding: "10px 14px",
            }}
            formatter={(v: unknown) => [Number(v).toFixed(4), ""]}
          />
          <Line
            type="monotone"
            dataKey="V"
            stroke="#3b82f6"
            strokeWidth={3}
            dot={false}
            activeDot={{ r: 6, fill: "#3b82f6", stroke: "#fff", strokeWidth: 2 }}
            animationDuration={1200}
          />
          <ReferenceDot
            x={criticalPoint.P}
            y={criticalPoint.V}
            r={5}
            fill="#ef4444"
            stroke="#fff"
            strokeWidth={2}
          />
        </LineChart>
    </ChartContainer>
  );
}
