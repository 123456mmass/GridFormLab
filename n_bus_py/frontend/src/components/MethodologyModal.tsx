"use client";

import { useEffect, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkMath from "remark-math";
import rehypeKatex from "rehype-katex";
import remarkGfm from "remark-gfm";
import { X, Loader2, BookOpen } from "lucide-react";
import { useLanguage } from "@/i18n";
import "katex/dist/katex.min.css"; 

interface MethodologyModalProps {
  methodName: string;
  isOpen: boolean;
  onClose: () => void;
}

export default function MethodologyModal({ methodName, isOpen, onClose }: MethodologyModalProps) {
  const { t } = useLanguage();
  const [lang, setLang] = useState<"TH" | "EN">("TH");
  const [content, setContent] = useState<{ methodName: string; en: string; th: string } | null>(null);

  useEffect(() => {
    if (isOpen && methodName) {
      fetch(`/api/methodology/${encodeURIComponent(methodName)}`)
        .then(res => res.json())
        .then(data => {
          setContent({ methodName, en: data.en, th: data.th });
        });
    }
  }, [isOpen, methodName]);

  if (!isOpen) return null;

  const loading = !content || content.methodName !== methodName;
  const displayContent = !loading ? (lang === "TH" ? content.th : content.en) : "";

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6">
      {/* Backdrop */}
      <div 
        className="absolute inset-0 bg-slate-900/60 backdrop-blur-sm transition-opacity"
        onClick={onClose}
      />
      
      {/* Modal Dialog */}
      <div className="relative w-full max-w-5xl max-h-[90vh] bg-white rounded-3xl shadow-2xl flex flex-col overflow-hidden animate-in fade-in zoom-in-95 duration-200">
        
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-slate-100 bg-slate-50/80 backdrop-blur-md">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-blue-100 text-blue-600 rounded-xl">
              <BookOpen className="w-5 h-5" />
            </div>
            <h2 className="text-xl font-black text-slate-800 tracking-tight">
              {t("methodology.title")}
            </h2>
          </div>
          
          <div className="flex items-center gap-4">
            {/* Language Toggle */}
            <div className="flex items-center gap-2 bg-slate-200/60 p-1 rounded-full">
              <button
                onClick={() => setLang("EN")}
                className={`px-4 py-1.5 text-xs font-bold rounded-full transition-all ${
                  lang === "EN" ? "bg-white text-blue-600 shadow-sm" : "text-slate-500 hover:text-slate-700"
                }`}
              >
                EN
              </button>
              <button
                onClick={() => setLang("TH")}
                className={`px-4 py-1.5 text-xs font-bold rounded-full transition-all ${
                  lang === "TH" ? "bg-white text-blue-600 shadow-sm" : "text-slate-500 hover:text-slate-700"
                }`}
              >
                TH
              </button>
            </div>
            
            <div className="w-px h-6 bg-slate-200" />
            
            {/* Close Button */}
            <button 
              onClick={onClose}
              className="p-2 text-slate-400 hover:bg-slate-200/50 hover:text-slate-600 rounded-full transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
        </div>

        {/* Content Area */}
        <div className="flex-1 overflow-y-auto p-8 sm:p-12 relative bg-white">
          {loading ? (
            <div className="absolute inset-0 flex items-center justify-center bg-white/80 backdrop-blur-sm z-10">
              <div className="flex flex-col items-center gap-4 text-blue-600">
                <Loader2 className="w-8 h-8 animate-spin" />
                <span className="font-medium">{t("methodology.loading")}</span>
              </div>
            </div>
          ) : (
            <div className="prose prose-slate prose-lg max-w-none prose-headings:text-slate-900 prose-h1:text-4xl prose-h1:font-black prose-h1:tracking-tight prose-h2:text-2xl prose-h2:font-bold prose-h2:mt-10 prose-h2:border-b prose-h2:border-slate-100 prose-h2:pb-4 prose-p:text-slate-600 prose-p:leading-relaxed prose-a:text-blue-600 hover:prose-a:text-blue-500 prose-blockquote:border-l-4 prose-blockquote:border-blue-500 prose-blockquote:bg-blue-50/50 prose-blockquote:py-1 prose-blockquote:px-6 prose-blockquote:rounded-r-2xl prose-blockquote:not-italic prose-blockquote:text-slate-700">
              <ReactMarkdown
                remarkPlugins={[remarkMath, remarkGfm]}
                rehypePlugins={[rehypeKatex]}
                components={{
                  a: ({ node, ...props }) => {
                    void node;
                    return <a {...props} target="_blank" rel="noopener noreferrer" />;
                  }
                }}
              >
                {displayContent}
              </ReactMarkdown>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
