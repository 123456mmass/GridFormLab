"use client";

import type { BusResult } from "@/lib/types";
import { useLanguage } from "@/i18n";

export function BusTable({ buses }: { buses: BusResult[] }) {
  const { t } = useLanguage();
  if (!buses || buses.length === 0) return null;

  const typeLabel = (type: number) => {
    if (type === 1) return "Slack";
    if (type === 2) return "PV";
    return "PQ";
  };

  const voltageColor = (v: number) => {
    if (v < 0.95) return "text-red-600 font-bold";
    if (v < 0.98) return "text-amber-600 font-bold";
    return "text-emerald-600 font-bold";
  };

  return (
    <div className="overflow-x-auto">
      <table className="premium-table">
        <thead>
          <tr>
            <th>{t("table.bus")}</th>
            <th>{t("table.type")}</th>
            <th className="text-right">{t("bustable.v_pu")}</th>
            <th className="text-right">{t("bustable.angle_deg")}</th>
            <th className="text-right">{t("bustable.pGen")}</th>
            <th className="text-right">{t("bustable.qGen")}</th>
            <th className="text-right">P_load</th>
            <th className="text-right">Q_load</th>
          </tr>
        </thead>
        <tbody>
          {buses.map((b) => (
            <tr key={b.bus_id} className="hover:bg-slate-50 transition-colors">
              <td className="font-bold text-slate-700">{b.bus_id}</td>
              <td>
                <span className={`text-[10px] font-black uppercase tracking-wider px-2 py-0.5 rounded ${
                  b.type === 1 ? "bg-blue-100 text-blue-700" : 
                  b.type === 2 ? "bg-amber-100 text-amber-700" : 
                  "bg-slate-100 text-slate-600"
                }`}>
                  {typeLabel(b.type)}
                </span>
              </td>
              <td className={`text-right tabular-nums ${voltageColor(b.voltage_pu)}`}>
                {b.voltage_pu.toFixed(4)}
              </td>
              <td className="text-right tabular-nums text-slate-500">{b.angle_deg.toFixed(2)}</td>
              <td className="text-right tabular-nums text-slate-700">{b.P_gen.toFixed(4)}</td>
              <td className="text-right tabular-nums text-slate-700">{b.Q_gen.toFixed(4)}</td>
              <td className="text-right tabular-nums text-slate-400">{b.P_load.toFixed(4)}</td>
              <td className="text-right tabular-nums text-slate-400">{b.Q_load.toFixed(4)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
