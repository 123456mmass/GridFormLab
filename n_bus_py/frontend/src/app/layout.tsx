"use client";

import Link from "next/link";
import { Inter } from "next/font/google";
import { usePathname, useRouter } from "next/navigation";
import {
  Activity,
  BarChart3,
  Bot,
  ChevronLeft,
  ChevronRight,
  GitCompare,
  Home,
  LogOut,
  MessageSquare,
  Settings2,
  TrendingUp,
  User,
  Zap,
} from "lucide-react";
import { useEffect, useState } from "react";
import type { ReactNode } from "react";
import { StatusIndicator } from "@/components/StatusIndicator";
import { LanguageSwitcher } from "@/components/LanguageSwitcher";
import { isLoggedIn, logout, getUserInfo } from "@/lib/auth";
import { LanguageProvider, useLanguage } from "@/i18n";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  display: "swap",
});

const NAV_KEYS = [
  { href: "/", key: "nav.dashboard", icon: Home, color: "text-blue-500" },
  { href: "/solve?group=pf", key: "nav.powerFlow", icon: Zap, color: "text-amber-500" },
  { href: "/solve?group=cpf", key: "nav.cpfStability", icon: TrendingUp, color: "text-cyan-500" },
  { href: "/solve?group=opt", key: "nav.optimization", icon: Settings2, color: "text-emerald-500" },
  { href: "/compare", key: "nav.compare", icon: GitCompare, color: "text-emerald-500" },
  { href: "/benchmark", key: "nav.benchmark", icon: BarChart3, color: "text-violet-500" },
  { href: "/chat", key: "nav.aiChat", icon: MessageSquare, color: "text-violet-500" },
  { href: "/analyze", key: "nav.aiAnalyze", icon: Bot, color: "text-fuchsia-500" },
];

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <title>N-Bus Power Flow Studio</title>
      </head>
      <body className={`${inter.className} min-h-screen flex bg-slate-50 text-slate-900`} suppressHydrationWarning>
        <LanguageProvider>
          <LayoutInner>{children}</LayoutInner>
        </LanguageProvider>
      </body>
    </html>
  );
}

function LayoutInner({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const [currentGroup, setCurrentGroup] = useState("pf");
  const [collapsed, setCollapsed] = useState(false);
  const [username, setUsername] = useState<string | null>(null);
  const { t } = useLanguage();

  const isLoginPage = pathname === "/login";

  useEffect(() => {
    if (isLoginPage) return;
    if (!isLoggedIn()) {
      router.replace("/login");
      return;
    }
    getUserInfo().then((u) => {
      if (u) setUsername(u.username);
    });
  }, [pathname, isLoginPage, router]);

  useEffect(() => {
    if (pathname !== "/solve") return;
    const id = window.setTimeout(() => {
      setCurrentGroup(new URLSearchParams(window.location.search).get("group") ?? "pf");
    }, 0);
    return () => window.clearTimeout(id);
  }, [pathname]);

  return (
    <>
      {/* Sidebar */}
      {!pathname.startsWith("/methodology") && !isLoginPage && (
        <aside
          className={`${
            collapsed ? "w-20" : "w-64"
          } flex-shrink-0 bg-white border-r border-slate-200 flex flex-col transition-all duration-300 ease-in-out z-20 shadow-sm`}
        >
          {/* Logo */}
          <div className="px-6 py-8 flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-blue-600 flex items-center justify-center flex-shrink-0 shadow-lg shadow-blue-200">
              <Activity className="w-5 h-5 text-white" />
            </div>
            {!collapsed && (
              <div className="animate-fade-in">
                <span className="font-extrabold text-lg tracking-tight text-slate-900">
                  N-Bus <span className="text-blue-600">PF</span>
                </span>
              </div>
            )}
          </div>

          {/* Navigation */}
          <nav className="flex-1 px-3 space-y-1">
            {NAV_KEYS.map(({ href, key, icon: Icon, color }) => {
              const [hrefPath, hrefQuery] = href.split("?");
              const hrefGroup = new URLSearchParams(hrefQuery ?? "").get("group");
              const active =
                hrefPath === "/solve"
                  ? pathname === "/solve" && currentGroup === hrefGroup
                  : pathname === hrefPath ||
                (hrefPath !== "/" && pathname.startsWith(hrefPath));
              return (
                <Link
                  key={href}
                  href={href}
                  onClick={() => {
                    if (hrefPath === "/solve" && hrefGroup) setCurrentGroup(hrefGroup);
                  }}
                  className={`flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-semibold transition-all duration-200 group ${
                    active
                      ? "bg-blue-50 text-blue-700"
                      : "text-slate-500 hover:bg-slate-50 hover:text-slate-900"
                  }`}
                >
                  <Icon
                    className={`w-5 h-5 flex-shrink-0 ${
                      active ? "text-blue-600" : color
                    } transition-colors`}
                  />
                  {!collapsed && (
                    <span className="animate-fade-in">{t(key)}</span>
                  )}
                </Link>
              );
            })}
          </nav>

          {/* Footer Area */}
          <div className="p-4 border-t border-slate-100 bg-slate-50/50">
            <StatusIndicator />
            {!collapsed && (
              <div className="mt-3 flex justify-center">
                <LanguageSwitcher />
              </div>
            )}
            {username && !collapsed && (
              <div className="mt-3 flex items-center gap-2 text-xs text-slate-500 px-2">
                <User className="w-3.5 h-3.5" />
                <span className="truncate">{username}</span>
              </div>
            )}
            {!collapsed && (
              <button
                onClick={() => {
                  logout();
                }}
                className="mt-2 flex items-center gap-2 text-xs font-bold text-slate-400 hover:text-red-500 transition-colors w-full px-2"
              >
                <LogOut className="w-3.5 h-3.5" />
                <span>{t("nav.logout")}</span>
              </button>
            )}
            {!collapsed && (
              <button
                onClick={() => setCollapsed(true)}
                className="mt-4 flex items-center gap-2 text-xs font-bold text-slate-400 hover:text-slate-600 transition-colors w-full px-2"
              >
                <ChevronLeft className="w-4 h-4" />
                <span>{t("nav.collapseMenu")}</span>
              </button>
            )}
            {collapsed && (
              <button
                onClick={() => setCollapsed(false)}
                className="mt-4 flex items-center justify-center text-slate-400 hover:text-slate-600 transition-colors w-full"
              >
                <ChevronRight className="w-4 h-4" />
              </button>
            )}
          </div>
        </aside>
      )}

      {/* Main content */}
      <main className="flex-1 overflow-auto bg-[#f8fafc]">
        <div className="p-0 animate-fade-in">
          {children}
        </div>
      </main>
    </>
  );
}
