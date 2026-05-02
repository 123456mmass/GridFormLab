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
import { useLanguage } from "@/i18n";

interface DispatchChartProps {
  P_gen: number[];
  P_min: number[];
  P_max: number[];
  incrementalCost: number[];
}

export function DispatchChart({ P_gen, P_min, P_max, incrementalCost }: DispatchChartProps) {
  const { t } = useLanguage();
  if (!P_gen || P_gen.length === 0) return null;

  const data = P_gen.map((p, i) => ({
    name: `G${i + 1}`,
    dispatch: p,
    min: P_min[i] || 0,
    max: P_max[i] || 0,
    cost: incrementalCost[i] || 0,
  }));

  return (
    <div className="space-y-10">
      <ChartContainer height={280} className="">
          <BarChart data={data} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
            {/* Increased grid visibility */}
            <CartesianGrid vertical={false} stroke="#e2e8f0" strokeDasharray="3 3" />
            <XAxis
              dataKey="name"
              axisLine={{ stroke: '#cbd5e1' }}
              tickLine={false}
              tick={{ fontSize: 11, fill: "#64748b", fontWeight: 600 }}
              dy={10}
            />
            <YAxis
              axisLine={{ stroke: '#cbd5e1' }}
              tickLine={false}
              tick={{ fontSize: 10, fill: "#64748b", fontWeight: 500 }}
              label={{ value: t("chart.powerAxis.label"), angle: -90, position: "insideLeft", offset: 25, style: { fill: "#64748b", fontSize: 11, fontWeight: 600 } }}
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
            <Bar dataKey="dispatch" name={t("chart.dispatch.label")} fill="#10b981" radius={[4, 4, 0, 0]} maxBarSize={40} />
          </BarChart>
      </ChartContainer>

      {/* Cost Info Grid */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
        {data.map((d, i) => (
          <div key={i} className="bg-white border border-slate-100 p-5 rounded-2xl shadow-sm">
            <p className="text-[10px] text-slate-400 font-bold uppercase tracking-widest mb-2">{d.name}</p>
            <div className="flex justify-between items-baseline">
              <span className="text-lg font-black text-emerald-600">{d.dispatch.toFixed(4)}</span>
              <span className="text-[10px] text-slate-400 font-bold">pu</span>
            </div>
            <div className="mt-3 pt-3 border-t border-slate-50 space-y-1.5">
              <div className="flex justify-between text-[10px] font-medium">
                <span className="text-slate-400">{t("chart.cost.label")}:</span>
                <span className="text-blue-600 font-bold">{d.cost.toFixed(2)} $/MWh</span>
              </div>
              <div className="flex justify-between text-[10px] font-medium">
                <span className="text-slate-400">{t("chart.range.label")}:</span>
                <span className="text-slate-500">{d.min.toFixed(1)}-{d.max.toFixed(1)}</span>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
