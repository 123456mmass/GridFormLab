"use client";

import { useContext, useMemo } from "react";
import { LanguageContext } from "./LanguageProvider";
import { SOLVER_LIST, SOLVER_CATEGORIES } from "@/lib/types";

export { LanguageProvider } from "./LanguageProvider";
export type { Language, InterpolationVars } from "./types";

export function useLanguage() {
  const ctx = useContext(LanguageContext);
  if (!ctx) throw new Error("useLanguage must be used within a LanguageProvider");
  return ctx;
}

export function useTranslatedSolverList() {
  const { t, lang } = useLanguage();
  return useMemo(
    () =>
      SOLVER_LIST.map((s) => ({
        ...s,
        description: t(`solver.${s.name.replace(/-/g, "")}.desc`, undefined, s.description),
        category: t(`category.${s.category}`, undefined, s.category),
      })),
    [lang, t],
  );
}

export function useTranslatedCategories() {
  const { t, lang } = useLanguage();
  return useMemo(
    () =>
      SOLVER_CATEGORIES.map((cat) => ({
        value: cat,
        label: t(`category.${cat}`, undefined, cat),
      })),
    [lang, t],
  );
}
