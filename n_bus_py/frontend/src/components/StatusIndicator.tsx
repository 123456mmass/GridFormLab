"use client";

import { useEffect, useState } from "react";
import { getHealth } from "@/lib/api";
import { useLanguage } from "@/i18n";

export function StatusIndicator() {
  const [online, setOnline] = useState<boolean | null>(null);
  const [solverCount, setSolverCount] = useState(0);
  const { t } = useLanguage();

  useEffect(() => {
    let mounted = true;
    async function check() {
      try {
        const h = await getHealth();
        if (mounted) {
          setOnline(true);
          setSolverCount(h.solvers?.length ?? 0);
        }
      } catch {
        if (mounted) setOnline(false);
      }
    }
    check();
    const iv = setInterval(check, 15000);
    return () => {
      mounted = false;
      clearInterval(iv);
    };
  }, []);

  if (online === null) {
    return (
      <div className="flex items-center gap-2 text-xs text-text-muted">
        <div className="w-2 h-2 rounded-full bg-text-muted animate-pulse" />
        {t("status.connecting")}
      </div>
    );
  }

  return (
    <div className={`flex items-center gap-2 text-xs ${online ? "text-success" : "text-danger"}`}>
      <div className={`glow-dot ${online ? "bg-success text-success" : "bg-danger text-danger"}`} />
      {online ? (
        <span className="text-text-dim">
          {t("status.online")} · {solverCount} {t("benchmark.solvers")}
        </span>
      ) : (
        <span className="text-danger">{t("status.offline")}</span>
      )}
    </div>
  );
}
