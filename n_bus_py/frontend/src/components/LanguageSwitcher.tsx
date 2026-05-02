"use client";

import { useLanguage } from "@/i18n";

export function LanguageSwitcher() {
  const { lang, setLang } = useLanguage();
  return (
    <div className="flex items-center gap-1 bg-slate-100 p-1 rounded-full border border-slate-200/50">
      <button
        onClick={() => setLang("en")}
        className={`px-3 py-1 text-xs font-bold rounded-full transition-all ${
          lang === "en"
            ? "bg-white text-blue-600 shadow-sm ring-1 ring-slate-200"
            : "text-slate-500 hover:text-slate-700"
        }`}
      >
        EN
      </button>
      <button
        onClick={() => setLang("th")}
        className={`px-3 py-1 text-xs font-bold rounded-full transition-all ${
          lang === "th"
            ? "bg-white text-blue-600 shadow-sm ring-1 ring-slate-200"
            : "text-slate-500 hover:text-slate-700"
        }`}
      >
        TH
      </button>
    </div>
  );
}
