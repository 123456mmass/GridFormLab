"use client";

import { X } from "lucide-react";
import { useEffect, type ReactNode } from "react";

interface ChartModalProps {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
}

export function ChartModal({ open, onClose, title, children }: ChartModalProps) {
  useEffect(() => {
    if (open) {
      const handler = (e: KeyboardEvent) => {
        if (e.key === "Escape") onClose();
      };
      document.addEventListener("keydown", handler);
      return () => document.removeEventListener("keydown", handler);
    }
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center animate-fade-in"
      onClick={onClose}
    >
      {/* Backdrop */}
      <div className="absolute inset-0 bg-[rgba(6,10,19,0.85)] backdrop-blur-md" />
      {/* Modal */}
      <div
        className="relative w-[90vw] max-w-5xl max-h-[85vh] overflow-auto card-premium animate-slide-up"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-bold text-text">{title}</h2>
          <button
            onClick={onClose}
            className="w-8 h-8 rounded-xl flex items-center justify-center text-text-muted hover:text-text hover:bg-white/[0.06] transition-all"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="min-h-[300px]">{children}</div>
      </div>
    </div>
  );
}
