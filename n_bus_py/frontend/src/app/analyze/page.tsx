"use client";

import { Suspense, useState, useRef, useEffect } from "react";
import { useSearchParams } from "next/navigation";
import { Activity, Bot, Brain, ChevronDown, History, Lightbulb, Plus, Send, Sparkles, User, X, Database } from "lucide-react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { askStream, listSessions, getSession } from "@/lib/api";
import type { SolverResult, SessionSummary } from "@/lib/types";
import { useLanguage } from "@/i18n";

interface Message {
  role: "user" | "assistant";
  content: string;
  thinking?: string;
  thinkingStartedAt?: number;
}

const CASUAL_PROMPTS = [
  { icon: Sparkles, text: "Hello! What can you help me with?", i18n: "prompt.casual.0" },
  { icon: Lightbulb, text: "Explain power flow analysis in simple terms", i18n: "prompt.casual.1" },
  { icon: Sparkles, text: "What's the difference between NR and Gauss-Seidel?", i18n: "prompt.casual.2" },
  { icon: Lightbulb, text: "Tell me a fun fact about electricity", i18n: "prompt.casual.3" },
];

const CONTEXT_PROMPTS = [
  { icon: Lightbulb, text: "Analyze these power flow results", i18n: "prompt.context.0" },
  { icon: Sparkles, text: "Are there any voltage issues I should worry about?", i18n: "prompt.context.1" },
  { icon: Lightbulb, text: "Summarize the key findings from these results", i18n: "prompt.context.2" },
  { icon: Sparkles, text: "What recommendations do you have based on this data?", i18n: "prompt.context.3" },
];

function stripJsonBlocks(text: string): string {
  return text.replace(/```json[\s\S]*?```/g, "").trim();
}

const CONTEXT_KEY = "nbus_analyze_context";

export default function AnalyzePage() {
  const { t } = useLanguage();
  return (
    <Suspense fallback={<div className="p-8 text-sm font-semibold text-slate-500">{t("analyze.loading")}</div>}>
      <AnalyzeClient />
    </Suspense>
  );
}

function AnalyzeClient() {
  const { t } = useLanguage();
  const searchParams = useSearchParams();
  const fromSolve = searchParams.get("from") === "solve";

  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [convId, setConvId] = useState<string | null>(null);
  const [resultContext, setResultContext] = useState<SolverResult | null>(null);
  const [selectedModel, setSelectedModel] = useState("gemini-2.5-flash");
  const [sessions, setSessions] = useState<SessionSummary[]>([]);
  const scrollRef = useRef<HTMLDivElement>(null);

  // Load context from sessionStorage (passed from solve page)
  useEffect(() => {
    try {
      const stored = sessionStorage.getItem(CONTEXT_KEY);
      if (stored) {
        const parsed = JSON.parse(stored) as SolverResult;
        sessionStorage.removeItem(CONTEXT_KEY);
        setTimeout(() => setResultContext(parsed), 0);
      }
    } catch { /* ignore */ }
  }, []);

  // Load analysis sessions
  useEffect(() => {
    listSessions("analysis").then(setSessions).catch(() => {});
  }, []);

  useEffect(() => {
    scrollRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  function clearContext() {
    setResultContext(null);
  }

  async function loadSession(id: string) {
    try {
      const s = await getSession(id);
      setConvId(id);
      const msgs = (s.messages || []).map((m: { role: string; content: string }) => ({
        role: m.role as "user" | "assistant",
        content: m.content,
      }));
      setMessages(msgs);
      if (s.analysis_context) {
        setResultContext(s.analysis_context as unknown as SolverResult);
      }
    } catch { /* ignore */ }
  }

  function newAnalysis() {
    setConvId(null);
    setMessages([]);
    setResultContext(null);
  }

  async function send(text?: string) {
    const q = (text || input).trim();
    if (!q || loading) return;
    if (!text) setInput("");
    setMessages((prev) => [...prev, { role: "user", content: q }]);
    setLoading(true);

    const resultsJson = resultContext ? JSON.stringify(resultContext) : undefined;
    let fullText = "";
    let thinkingText = "";
    let thinkingStarted = false;
    let thinkingStartTime = 0;
    setMessages((prev) => [...prev, { role: "assistant", content: "", thinking: "" }]);

    const updateAssistant = (content: string, thinking?: string, startTime?: number) => {
      setMessages((prev) => {
        const next = [...prev];
        const last = next[next.length - 1];
        next[next.length - 1] = {
          role: "assistant",
          content,
          thinking: thinking ?? last.thinking,
          thinkingStartedAt: startTime ?? last.thinkingStartedAt,
        };
        return next;
      });
    };

    try {
      for await (const chunk of askStream(q, convId || undefined, resultsJson, selectedModel)) {
        if (chunk.thinking) {
          if (!thinkingStarted) {
            thinkingStarted = true;
            thinkingStartTime = Date.now();
          }
          thinkingText += chunk.thinking;
          updateAssistant(fullText, thinkingText, thinkingStartTime);
        }
        if (chunk.token) {
          fullText += chunk.token;
          updateAssistant(fullText, thinkingText, thinkingStartTime);
        }
        if (chunk.conversation_id) {
          setConvId(chunk.conversation_id);
          listSessions("analysis").then(setSessions).catch(() => {});
        }
        if (chunk.error) {
          fullText = `**Error**: ${chunk.error}`;
          updateAssistant(fullText, thinkingText);
        }
        if (chunk.done && !fullText.trim() && !thinkingText.trim()) {
          updateAssistant(t("analyze.emptyResponse"));
        }
      }
    } catch (e) {
      fullText = `**${t("generic.connectionFailed")}**: ${e instanceof Error ? e.message : t("generic.unknownError")}`;
      updateAssistant(fullText, thinkingText);
    } finally {
      setLoading(false);
    }
  }

  const prompts = resultContext ? CONTEXT_PROMPTS : CASUAL_PROMPTS;

  return (
    <div className="p-8 max-w-4xl mx-auto flex flex-col h-[calc(100vh-0px)]">
      {/* Header */}
      <div className="mb-6 animate-fade-in">
        <div className="flex items-center gap-3 mb-2">
          <div className="w-10 h-10 rounded-2xl bg-gradient-to-br from-violet-500 to-fuchsia-500 flex items-center justify-center shadow-lg shadow-violet-500/20">
            <Bot className="w-5 h-5 text-white" />
          </div>
          <div className="flex-1">
            <div className="flex items-center gap-3">
              <h1 className="text-3xl font-black tracking-tight">
                <span className="text-gradient">{t("analyze.title")}</span>
              </h1>
              <select
                value={selectedModel}
                onChange={(e) => setSelectedModel(e.target.value)}
                className="bg-slate-100 border border-slate-200 text-slate-700 text-xs font-bold rounded-xl px-3 py-1.5 outline-none focus:ring-2 focus:ring-violet-500/20"
              >
                <option value="gemini-2.5-flash">Gemini 2.5 Flash</option>
                <option value="deepseek-v4-flash">DeepSeek V4 Flash</option>
                <option value="deepseek-v4-pro">DeepSeek V4 Pro</option>
                <option value="deepseek-reasoner">DeepSeek R1 (Reasoner)</option>
                <option value="mercury-2">Mercury 2</option>
                <option value="openai/gpt-oss-120b">NVIDIA GPT-OSS 120B</option>
                <option value="nvidia/nemotron-3-nano-omni-30b-a3b-reasoning">NVIDIA Nemotron 30B</option>
                <option value="qwen/qwen3.5-122b-a10b">Qwen 3.5 122B (NVIDIA)</option>
              </select>
            </div>
            <p className="text-text-dim text-xs mt-0.5">
              {resultContext
                ? `${t("analyze.contextLoaded")} — ${resultContext.method}, ${resultContext.buses.length} ${t("analyze.buses")}`
                : t("analyze.chatCasual")}
            </p>
          </div>
        </div>

        {/* Session picker + new button */}
        {sessions.length > 0 && (
          <div className="mt-2 flex items-center gap-2">
            <History className="w-3.5 h-3.5 text-slate-400 flex-shrink-0" />
            <select
              value={convId ?? ""}
              onChange={(e) => {
                const v = e.target.value;
                if (v) loadSession(v);
              }}
              className="flex-1 text-xs rounded-lg px-2 py-1.5 border border-slate-200 outline-none text-slate-600 bg-white max-w-xs"
            >
              <option value="">{t("analyze.newAnalysis")}</option>
              {sessions.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.title || t("generic.untitled")} · {s.message_count} msgs
                </option>
              ))}
            </select>
            {convId && (
              <button
                onClick={newAnalysis}
                className="flex items-center gap-1 text-xs font-semibold text-violet-600 hover:text-violet-800 rounded-lg px-2 py-1.5 hover:bg-violet-50 transition-colors"
              >
                <Plus className="w-3 h-3" />
                {t("analyze.new")}
              </button>
            )}
          </div>
        )}

        {/* Context badge */}
        {resultContext && (
          <div className="mt-3 flex items-center gap-2">
            <div className="flex items-center gap-1.5 bg-violet-50 border border-violet-200 rounded-xl px-3 py-1.5 text-xs font-semibold text-violet-700">
              <Database className="w-3.5 h-3.5" />
              <span>{resultContext.method} — {resultContext.system_name}</span>
              <button
                onClick={clearContext}
                className="ml-1 p-0.5 rounded-lg hover:bg-violet-200 transition-colors"
                title={t("analyze.clearContext")}
              >
                <X className="w-3 h-3" />
              </button>
            </div>
            {fromSolve && (
              <span className="text-xs text-slate-400 font-medium">{t("analyze.resultsFromSolver")}</span>
            )}
          </div>
        )}
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto space-y-4 mb-4 pr-2">
        {messages.length === 0 && (
          <div className="text-center py-12 space-y-6 animate-fade-in">
            <div className="w-16 h-16 rounded-3xl bg-gradient-to-br from-violet-500/20 to-fuchsia-500/20 flex items-center justify-center mx-auto">
              <Bot className="w-8 h-8 text-violet/60" />
            </div>
            <div>
              <p className="text-text-dim text-sm font-medium">
                {resultContext ? t("analyze.resultsLoaded") : t("analyze.askMe")}
              </p>
              <p className="text-text-muted text-xs mt-1">
                {resultContext
                  ? t("analyze.tryPrompts")
                  : t("analyze.chatAnything")}
              </p>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 max-w-lg mx-auto">
              {prompts.map((p, i) => (
                <button
                  key={i}
                  onClick={() => send(p.text)}
                  className="card-glass card-glass-hover text-left text-xs text-text-dim group flex items-center gap-2 py-3 px-4"
                >
                  <p.icon className="w-3.5 h-3.5 text-violet/60 group-hover:text-violet flex-shrink-0" />
                  <span className="group-hover:text-text transition-colors">{t(p.i18n)}</span>
                </button>
              ))}
            </div>
          </div>
        )}
        {messages.map((m, i) => (
          <div
            key={i}
            className={`flex gap-3 animate-fade-in ${m.role === "user" ? "justify-end" : ""}`}
          >
            {m.role === "assistant" && (
              <div className="w-7 h-7 rounded-xl bg-gradient-to-br from-violet-500 to-fuchsia-500 flex items-center justify-center flex-shrink-0 mt-0.5 shadow-sm">
                <Bot className="w-3.5 h-3.5 text-white" />
              </div>
            )}
            <div
              className={`max-w-[80%] rounded-2xl px-4 py-3 text-sm leading-relaxed ${
                m.role === "user"
                  ? "bg-gradient-to-br from-blue-600 to-indigo-600 text-white shadow-lg shadow-blue-500/15"
                  : "card-glass"
              }`}
            >
              {m.role === "assistant" ? (
                m.content || m.thinking ? (
                  <>
                    {m.thinking && (
                      <ThinkingBox thinking={m.thinking} hasContent={!!m.content} startedAt={m.thinkingStartedAt} />
                    )}
                    {m.content && (
                      <ReactMarkdown
                    remarkPlugins={[remarkGfm]}
                    components={{
                      table: ({ children }) => (
                        <div className="overflow-x-auto my-2">
                          <table className="min-w-full text-xs border-collapse">{children}</table>
                        </div>
                      ),
                      th: ({ children }) => (
                        <th className="border border-border px-2 py-1 text-left text-text-dim font-medium">{children}</th>
                      ),
                      td: ({ children }) => (
                        <td className="border border-border/50 px-2 py-1 font-mono text-text">{children}</td>
                      ),
                      code: ({ className, children, ...props }: React.ComponentPropsWithoutRef<"code"> & { className?: string }) => {
                        const isInline = !className;
                        if (isInline) {
                          return <code className="bg-surface-alt text-primary rounded px-1.5 py-0.5 text-xs" {...props}>{children}</code>;
                        }
                        return <code className="block bg-[rgba(6,10,19,0.8)] border border-border rounded-xl p-3 text-xs overflow-x-auto my-2" {...props}>{children}</code>;
                      },
                      p: ({ children }) => <p className="text-text leading-relaxed mb-2 last:mb-0">{children}</p>,
                      strong: ({ children }) => <strong className="text-text font-semibold">{children}</strong>,
                      ul: ({ children }) => <ul className="list-disc list-inside space-y-1 text-text">{children}</ul>,
                      ol: ({ children }) => <ol className="list-decimal list-inside space-y-1 text-text">{children}</ol>,
                      h3: ({ children }) => <h3 className="text-text font-bold text-sm mt-3 mb-1">{children}</h3>,
                      h4: ({ children }) => <h4 className="text-text-dim font-semibold text-xs mt-2 mb-1">{children}</h4>,
                      h2: ({ children }) => <h2 className="text-text font-bold text-base mt-4 mb-2">{children}</h2>,
                      h1: ({ children }) => <h1 className="text-text font-black text-lg mt-4 mb-2">{children}</h1>,
                    }}
                  >
                      {stripJsonBlocks(m.content)}
                    </ReactMarkdown>
                    )}
                  </>
                ) : (
                  loading && i === messages.length - 1 && (
                    <div className="flex items-center gap-2 text-text-muted">
                      <div className="flex gap-1">
                        <div className="w-1.5 h-1.5 bg-violet rounded-full animate-bounce" style={{ animationDelay: "0ms" }} />
                        <div className="w-1.5 h-1.5 bg-violet rounded-full animate-bounce" style={{ animationDelay: "150ms" }} />
                        <div className="w-1.5 h-1.5 bg-violet rounded-full animate-bounce" style={{ animationDelay: "300ms" }} />
                      </div>
                      <span className="text-xs">Thinking…</span>
                    </div>
                  )
                )
              ) : (
                <div className="whitespace-pre-wrap">{m.content}</div>
              )}
            </div>
            {m.role === "user" && (
              <div className="w-7 h-7 rounded-xl bg-gradient-to-br from-slate-600 to-slate-700 flex items-center justify-center flex-shrink-0 mt-0.5">
                <User className="w-3.5 h-3.5 text-slate-200" />
              </div>
            )}
          </div>
        ))}
        <div ref={scrollRef} />
      </div>

      {/* Input */}
      <div className="flex gap-3 animate-slide-up">
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && send()}
          placeholder={resultContext ? t("analyze.placeholderResults") : t("analyze.placeholder")}
          disabled={loading}
          className="input-premium flex-1 rounded-2xl px-5 py-3 text-sm disabled:opacity-50"
        />
        <button
          onClick={() => send()}
          disabled={loading || !input.trim()}
          className="btn-gradient btn-gradient-hover rounded-2xl px-5 py-3 text-sm"
        >
          {loading ? (
            <Activity className="w-4 h-4 animate-spin" />
          ) : (
            <Send className="w-4 h-4" />
          )}
        </button>
      </div>
    </div>
  );
}

function ThinkingBox({ thinking, hasContent, startedAt }: { thinking: string; hasContent: boolean; startedAt?: number }) {
  const [open, setOpen] = useState(true);
  const prevHasContent = useRef(false);
  const [elapsed, setElapsed] = useState(0);

  useEffect(() => {
    if (hasContent && !prevHasContent.current) {
      setOpen(false);
      prevHasContent.current = true;
    }
  }, [hasContent]);

  useEffect(() => {
    if (!startedAt || hasContent) return;
    const update = () => setElapsed((Date.now() - startedAt) / 1000);
    update();
    const id = setInterval(update, 200);
    return () => clearInterval(id);
  }, [startedAt, hasContent]);

  if (!thinking) return null;

  const elapsedStr = `${elapsed.toFixed(1)}s`;

  return (
    <div className="mb-3 rounded-xl border border-violet-200 bg-gradient-to-r from-violet-50 to-fuchsia-50 overflow-hidden">
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-center gap-1.5 px-4 py-2 text-xs font-bold text-violet-600 hover:bg-violet-100/30 transition-colors select-none"
      >
        <Brain className="w-3.5 h-3.5" />
        <span>{t("chat.thinking")} ({elapsedStr})</span>
        <ChevronDown className={`w-3.5 h-3.5 ml-auto transition-transform duration-200 ${open ? "rotate-180" : ""}`} />
      </button>
      {open && (
        <div className="px-4 pb-3 pt-1 border-t border-violet-100 text-xs text-slate-600 leading-relaxed whitespace-pre-wrap max-h-[300px] overflow-y-auto">
          {thinking}
        </div>
      )}
    </div>
  );
}
