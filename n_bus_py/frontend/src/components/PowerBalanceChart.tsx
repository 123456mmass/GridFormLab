"use client";

import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend as RechartsLegend,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { ChartContainer } from "@/components/ChartContainer";
import type { BusResult } from "@/lib/types";
import { useLanguage } from "@/i18n";

export function PowerBalanceChart({ buses }: { buses: BusResult[] }) {
  const { t } = useLanguage();
  if (!buses || buses.length === 0) return null;

  const data = buses.map((b) => ({
    bus: `${b.bus_id}`,
    P_gen: b.P_gen,
    P_load: -b.P_load,
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
          />
          <Tooltip
            cursor={{ fill: "#f1f5f9" }}
            contentStyle={{
              border: "1px solid #e2e8f0",
              borderRadius: "12px",
              boxShadow: "0 10px 15px -3px rgba(0, 0, 0, 0.05)",
              padding: "10px 14px",
            }}
            formatter={(v: unknown) => {
              const value = Number(v);
              return [Math.abs(value).toFixed(4) + " pu", value >= 0 ? t("chart.power.gen") : t("chart.power.load")];
            }}
          />
          <RechartsLegend
            iconType="circle"
            wrapperStyle={{ fontSize: 11, paddingTop: 10, color: "#64748b" }}
            content={<CustomLegend />}
          />
          <Bar dataKey="P_gen" name={t("chart.power.gen")} fill="#10b981" radius={[4, 4, 0, 0]} maxBarSize={20} />
          <Bar dataKey="P_load" name={t("chart.power.load")} fill="#f43f5e" radius={[0, 0, 4, 4]} maxBarSize={20} />
        </BarChart>
    </ChartContainer>
  );
}

interface LegendPayload {
  color?: string;
  value?: string;
}

function CustomLegend({ payload = [] }: { payload?: LegendPayload[] }) {
  return (
    <ul className="flex justify-center gap-6 mt-4 text-[11px] font-bold text-slate-500">
      {payload.map((entry, index) => (
        <li key={`item-${index}`} className="flex items-center gap-2">
          <div className="w-3 h-3 rounded-full" style={{ backgroundColor: entry.color }} />
          <span>{entry.value}</span>
        </li>
      ))}
    </ul>
  );
}
