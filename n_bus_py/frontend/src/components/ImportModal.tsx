"use client";

import { useState } from "react";
import { UploadCloud, FileText, CheckCircle2, AlertCircle, X } from "lucide-react";
import { API_BASE_URL } from "@/lib/api";
import { useLanguage } from "@/i18n";

interface ImportModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: (caseName: string) => void;
}

export function ImportModal({ isOpen, onClose, onSuccess }: ImportModalProps) {
  const { t } = useLanguage();
  const [file, setFile] = useState<File | null>(null);
  const [caseName, setCaseName] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [successMsg, setSuccessMsg] = useState("");

  if (!isOpen) return null;

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
      setFile(e.dataTransfer.files[0]);
      if (!caseName) {
        setCaseName(e.dataTransfer.files[0].name.replace(/\.[^/.]+$/, ""));
      }
    }
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      setFile(e.target.files[0]);
      if (!caseName) {
        setCaseName(e.target.files[0].name.replace(/\.[^/.]+$/, ""));
      }
    }
  };

  const handleUpload = async () => {
    if (!file || !caseName) return;
    setLoading(true);
    setError("");
    setSuccessMsg("");

    const formData = new FormData();
    formData.append("file", file);
    const finalCaseName = caseName.replace(/[^a-zA-Z0-9_]/g, "_").toLowerCase();
    formData.append("case_name", finalCaseName);

    try {
      const res = await fetch(`${API_BASE_URL}/ai/import_case`, {
        method: "POST",
        body: formData,
      });
      
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || data.error || t("import.failed"));
      
      setSuccessMsg(data.message || t("import.successMsg"));
      
      // Give the user a moment to see the success message
      setTimeout(() => {
        onSuccess(finalCaseName);
        resetAndClose();
      }, 1500);
      
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t("import.failed"));
    } finally {
      setLoading(false);
    }
  };

  const resetAndClose = () => {
    setFile(null);
    setCaseName("");
    setError("");
    setSuccessMsg("");
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 backdrop-blur-sm p-4 animate-fade-in">
      <div className="bg-white rounded-3xl shadow-xl w-full max-w-lg overflow-hidden animate-slide-up relative">
        <button 
          onClick={resetAndClose}
          className="absolute top-4 right-4 p-2 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-full transition-colors"
        >
          <X className="w-5 h-5" />
        </button>

        <div className="p-8 space-y-6">
          <div className="text-center space-y-2">
            <div className="w-12 h-12 bg-blue-50 text-blue-600 rounded-xl flex items-center justify-center mx-auto mb-4">
              <UploadCloud className="w-6 h-6" />
            </div>
            <h2 className="text-2xl font-black text-slate-900">{t("import.title")}</h2>
            <p className="text-sm text-slate-500">{t("import.subtitle")}</p>
          </div>

          {successMsg ? (
            <div className="bg-emerald-50 text-emerald-700 p-6 rounded-2xl border border-emerald-100 flex flex-col items-center justify-center text-center space-y-3 animate-fade-in">
              <CheckCircle2 className="w-10 h-10 text-emerald-500" />
              <p className="font-bold">{successMsg}</p>
              <p className="text-xs opacity-80">{t("import.loadingCase")}</p>
            </div>
          ) : (
            <>
              <div
                onDragOver={(e) => e.preventDefault()}
                onDrop={handleDrop}
                className="border-2 border-dashed border-slate-200 rounded-2xl p-8 flex flex-col items-center justify-center text-center hover:bg-slate-50 hover:border-blue-300 transition-colors cursor-pointer"
                onClick={() => document.getElementById("modalFileUpload")?.click()}
              >
                <input
                  id="modalFileUpload"
                  type="file"
                  accept=".pdf,.txt,.md,.png,.jpg,.jpeg,.webp,.heic,.heif,image/png,image/jpeg,image/webp,image/heic,image/heif"
                  className="hidden"
                  onChange={handleFileChange}
                />
                {file ? (
                  <div className="flex flex-col items-center text-blue-600">
                    <FileText className="w-8 h-8 mb-2" />
                    <p className="font-bold text-sm truncate max-w-[200px]">{file.name}</p>
                    <p className="text-xs text-slate-400 mt-1">{(file.size / 1024).toFixed(1)} KB</p>
                  </div>
                ) : (
                  <div className="flex flex-col items-center text-slate-400">
                    <UploadCloud className="w-8 h-8 mb-2 text-slate-300" />
                    <p className="font-medium text-sm text-slate-600">{t("import.clickOrDrag")}</p>
                  </div>
                )}
              </div>

              <div className="space-y-2">
                <label className="text-xs font-bold text-slate-500 uppercase tracking-wide">{t("import.caseName")}</label>
                <input
                  type="text"
                  value={caseName}
                  onChange={(e) => setCaseName(e.target.value)}
                  placeholder={t("import.caseNamePlaceholder")}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-2.5 text-sm font-semibold outline-none focus:ring-2 focus:ring-blue-500/20"
                />
              </div>

              {error && (
                <div className="p-3 bg-red-50 text-red-600 rounded-xl flex items-start gap-2 text-sm font-medium">
                  <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
                  <p>{error}</p>
                </div>
              )}

              <button
                onClick={handleUpload}
                disabled={!file || !caseName || loading}
                className="w-full btn-gradient py-3.5 rounded-xl flex items-center justify-center gap-2 text-sm font-bold disabled:opacity-50"
              >
                {loading ? (
                  <>
                    <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    <span>{t("import.extracting")}</span>
                  </>
                ) : (
                  <>
                    <UploadCloud className="w-4 h-4" />
                    <span>{t("import.importData")}</span>
                  </>
                )}
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
