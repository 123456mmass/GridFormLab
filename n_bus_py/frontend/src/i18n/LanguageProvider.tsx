"use client";

import React, { createContext, useCallback, useEffect, useMemo, useState } from "react";
import type { InterpolationVars, Language } from "./types";
import DICT from "./dictionary";

const STORAGE_KEY = "nbus_language";

interface LanguageContextValue {
  lang: Language;
  setLang: (lang: Language) => void;
  t: (key: string, vars?: InterpolationVars, fallback?: string) => string;
}

export const LanguageContext = createContext<LanguageContextValue>({
  lang: "en",
  setLang: () => {},
  t: (key: string) => key,
});

function detectLanguage(): Language {
  if (typeof window === "undefined") return "en";
  const stored = localStorage.getItem(STORAGE_KEY);
  if (stored === "th" || stored === "en") return stored;
  if (navigator.language.startsWith("th")) return "th";
  return "en";
}

function interpolate(template: string, vars?: InterpolationVars): string {
  if (!vars) return template;
  return template.replace(/\{(\w+)\}/g, (_, key) => String(vars[key] ?? `{${key}}`));
}

export function LanguageProvider({ children }: { children: React.ReactNode }) {
  const [lang, setLangState] = useState<Language>("en");

  useEffect(() => {
    setLangState(detectLanguage());
  }, []);

  const setLang = useCallback((next: Language) => {
    setLangState(next);
    if (typeof window !== "undefined") {
      localStorage.setItem(STORAGE_KEY, next);
    }
  }, []);

  const t = useCallback(
    (key: string, vars?: InterpolationVars, fallback?: string): string => {
      const entry = DICT[key];
      if (!entry) return fallback ?? key;
      const template = entry[lang] ?? entry.en;
      return interpolate(template, vars);
    },
    [lang],
  );

  const value = useMemo(() => ({ lang, setLang, t }), [lang, setLang, t]);

  return (
    <LanguageContext.Provider value={value}>
      {children}
    </LanguageContext.Provider>
  );
}
