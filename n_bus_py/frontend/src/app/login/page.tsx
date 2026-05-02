"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Activity, KeyRound, LogIn, UserPlus } from "lucide-react";
import { login, register } from "@/lib/auth";
import { useLanguage } from "@/i18n";

export default function LoginPage() {
  const { t } = useLanguage();
  const router = useRouter();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [mode, setMode] = useState<"login" | "register">("login");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!username.trim() || !password) return;
    setError("");
    setLoading(true);
    try {
      if (mode === "register") {
        await register(username.trim(), password);
      } else {
        await login(username.trim(), password);
      }
      router.replace("/");
    } catch (err) {
      setError(err instanceof Error ? err.message : (mode === "register" ? t("login.registerFailed") : t("login.loginFailed")));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-100 to-blue-50">
      <div className="w-full max-w-sm">
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="w-14 h-14 rounded-2xl bg-blue-600 flex items-center justify-center mx-auto mb-4 shadow-lg shadow-blue-200">
            <Activity className="w-7 h-7 text-white" />
          </div>
          <h1 className="text-2xl font-black tracking-tight text-slate-900">
            N-Bus <span className="text-blue-600">Power Flow</span>
          </h1>
          <p className="text-xs text-slate-500 mt-1">
            {mode === "login" ? t("login.signInSubtitle") : t("login.createAccountSub")}
          </p>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className="card-glass space-y-4">
          <div>
            <label className="block text-xs font-semibold text-slate-600 mb-1.5">
              {t("login.username")}
            </label>
            <input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder={t("login.usernamePlaceholder")}
              autoComplete="username"
              className="input-premium w-full rounded-xl px-4 py-2.5 text-sm"
              disabled={loading}
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-600 mb-1.5">
              {t("login.password")}
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder={t("login.passwordPlaceholder")}
              autoComplete={mode === "register" ? "new-password" : "current-password"}
              onKeyDown={(e) => e.key === "Enter" && handleSubmit(e)}
              className="input-premium w-full rounded-xl px-4 py-2.5 text-sm"
              disabled={loading}
            />
          </div>

          {error && (
            <div className="text-xs text-danger font-medium bg-red-50 border border-red-200 rounded-xl px-3 py-2">
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={loading || !username.trim() || !password}
            className="btn-gradient w-full rounded-xl py-2.5 text-sm flex items-center justify-center gap-2"
          >
            {loading ? (
              <Activity className="w-4 h-4 animate-spin" />
            ) : mode === "login" ? (
              <LogIn className="w-4 h-4" />
            ) : (
              <UserPlus className="w-4 h-4" />
            )}
            {mode === "login" ? t("login.signIn") : t("login.createAccount")}
          </button>

          <div className="text-center">
            <button
              type="button"
              onClick={() => {
                setMode(mode === "login" ? "register" : "login");
                setError("");
              }}
              className="text-xs font-medium text-slate-500 hover:text-blue-600 transition-colors"
            >
              {mode === "login"
                ? t("login.noAccount")
                : t("login.hasAccount")}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
