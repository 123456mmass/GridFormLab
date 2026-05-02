"use client";

import { useEffect, useState } from "react";
import { X, Plus, Edit3, Trash2, Star } from "lucide-react";
import { listPersonas, savePersona, updatePersona, deletePersona } from "@/lib/api";
import type { Persona } from "@/lib/types";
import { useLanguage } from "@/i18n";

const TONES = ["Friendly", "Professional", "Concise", "Enthusiastic", "Sarcastic"];
const STYLES = ["Casual", "Academic", "Technical", "Creative"];
const LANGUAGES = [
  { value: "en", label: "English" },
  { value: "th", label: "Thai" },
];

export default function PersonaModal({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
  const [personas, setPersonas] = useState<Persona[]>([]);
  const { t } = useLanguage();
  const [editing, setEditing] = useState<Persona | null>(null);
  const [form, setForm] = useState({
    name: "",
    ai_tone: "",
    ai_style: "",
    language_preference: "",
    custom_prompt: "",
    is_default: false,
  });
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (open) {
      listPersonas()
        .then(setPersonas)
        .catch(() => {});
    }
  }, [open]);

  function resetForm() {
    setForm({ name: "", ai_tone: "", ai_style: "", language_preference: "", custom_prompt: "", is_default: false });
    setEditing(null);
  }

  async function handleSave() {
    if (!form.name.trim()) return;
    setLoading(true);
    try {
      if (editing) {
        await updatePersona(editing.id, form);
      } else {
        await savePersona(form);
      }
      const list = await listPersonas();
      setPersonas(list);
      resetForm();
    } catch {
      // ignore
    } finally {
      setLoading(false);
    }
  }

  async function handleDelete(id: number) {
    await deletePersona(id);
    setPersonas((p) => p.filter((x) => x.id !== id));
    if (editing?.id === id) resetForm();
  }

  function startEdit(p: Persona) {
    setEditing(p);
    setForm({
      name: p.name,
      ai_tone: p.ai_tone || "",
      ai_style: p.ai_style || "",
      language_preference: p.language_preference || "",
      custom_prompt: p.custom_prompt || "",
      is_default: p.is_default,
    });
  }

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-lg max-h-[80vh] overflow-y-auto p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-bold text-slate-900">{t("persona.title")}</h3>
          <button onClick={onClose} className="p-1 rounded-lg hover:bg-slate-100">
            <X className="w-5 h-5 text-slate-500" />
          </button>
        </div>

        {/* Existing personas */}
        {personas.length > 0 && (
          <div className="space-y-2 mb-4">
            {personas.map((p) => (
              <div
                key={p.id}
                className="flex items-center gap-2 p-2 rounded-xl border border-slate-200 bg-slate-50"
              >
                <div className="flex-1 text-sm">
                  <span className="font-semibold text-slate-800">{p.name}</span>
                  {p.is_default && <Star className="inline w-3 h-3 ml-1 text-amber-500" />}
                  <span className="text-xs text-slate-500 ml-2">
                    {p.ai_tone} · {p.ai_style} · {p.language_preference === "th" ? "ไทย" : "EN"}
                  </span>
                </div>
                <button onClick={() => startEdit(p)} className="p-1.5 rounded-lg hover:bg-slate-200">
                  <Edit3 className="w-3.5 h-3.5 text-slate-500" />
                </button>
                <button onClick={() => handleDelete(p.id)} className="p-1.5 rounded-lg hover:bg-red-100">
                  <Trash2 className="w-3.5 h-3.5 text-red-500" />
                </button>
              </div>
            ))}
          </div>
        )}

        {/* Form */}
        <div className="space-y-3">
          <input
            value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
            placeholder={t("persona.namePlaceholder")}
            className="w-full rounded-xl px-4 py-2.5 text-sm border border-slate-200 outline-none focus:ring-2 focus:ring-violet-500/20"
          />

          <div className="grid grid-cols-2 gap-2">
            <select
              value={form.ai_tone}
              onChange={(e) => setForm({ ...form, ai_tone: e.target.value })}
              className="rounded-xl px-3 py-2 text-sm border border-slate-200 outline-none"
            >
              <option value="">{t("persona.toneDefault")}</option>
              {TONES.map((t) => (
                <option key={t} value={t.toLowerCase()}>{t}</option>
              ))}
            </select>
            <select
              value={form.ai_style}
              onChange={(e) => setForm({ ...form, ai_style: e.target.value })}
              className="rounded-xl px-3 py-2 text-sm border border-slate-200 outline-none"
            >
              <option value="">{t("persona.styleDefault")}</option>
              {STYLES.map((s) => (
                <option key={s} value={s.toLowerCase()}>{s}</option>
              ))}
            </select>
          </div>

          <select
            value={form.language_preference}
            onChange={(e) => setForm({ ...form, language_preference: e.target.value })}
            className="w-full rounded-xl px-3 py-2 text-sm border border-slate-200 outline-none"
          >
            <option value="">{t("persona.languageDefault")}</option>
            {LANGUAGES.map((l) => (
              <option key={l.value} value={l.value}>{l.label}</option>
            ))}
          </select>

          <textarea
            value={form.custom_prompt}
            onChange={(e) => setForm({ ...form, custom_prompt: e.target.value })}
            placeholder={t("persona.customInstructions")}
            rows={3}
            className="w-full rounded-xl px-4 py-2.5 text-sm border border-slate-200 outline-none resize-none focus:ring-2 focus:ring-violet-500/20"
          />

          <label className="flex items-center gap-2 text-sm text-slate-600">
            <input
              type="checkbox"
              checked={form.is_default}
              onChange={(e) => setForm({ ...form, is_default: e.target.checked })}
              className="rounded"
            />
            {t("persona.setDefault")}
          </label>

          <div className="flex gap-2">
            <button
              onClick={handleSave}
              disabled={loading || !form.name.trim()}
              className="btn-gradient rounded-xl px-4 py-2.5 text-sm flex-1"
            >
              {editing ? t("persona.update") : t("persona.create")} {t("persona.title")}
            </button>
            {editing && (
              <button
                onClick={resetForm}
                className="px-4 py-2.5 text-sm font-semibold text-slate-500 hover:text-slate-700 rounded-xl border border-slate-200"
              >
                {t("persona.cancel")}
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
