"use client";

import type { LineResult } from "@/lib/types";
import { useLanguage } from "@/i18n";

export function LineTable({ lines }: { lines: LineResult[] }) {
  const { t } = useLanguage();
  if (!lines || lines.length === 0) return null;

  return (
    <div className="overflow-x-auto">
      <table className="premium-table">
        <thead>
          <tr>
            <th>{t("table.from")}</th>
            <th>{t("table.to")}</th>
            <th className="text-right">{t("linetable.pFrom")}</th>
            <th className="text-right">{t("linetable.qFrom")}</th>
            <th className="text-right">{t("linetable.pLoss")}</th>
            <th className="text-right">{t("linetable.qLoss")}</th>
          </tr>
        </thead>
        <tbody>
          {lines.map((l, i) => (
            <tr key={i}>
              <td className="text-text font-semibold">{l.from_bus}</td>
              <td className="text-text font-semibold">{l.to_bus}</td>
              <td className="text-right">{l.P_from.toFixed(4)}</td>
              <td className="text-right text-text-dim">{l.Q_from.toFixed(4)}</td>
              <td className="text-right text-warning">{l.P_loss.toFixed(6)}</td>
              <td className="text-right text-text-dim">{l.Q_loss.toFixed(6)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
