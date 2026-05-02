"use client";

import { useState, useRef, useEffect } from "react";
import {
  Activity, Bot, Brain, ChevronDown, FileText, ImageIcon, Lightbulb,
  MessageSquare, Paperclip, Plus, Send, Sparkles, Trash2, User, X, Settings2,
} from "lucide-react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { askStream, listSessions, deleteSession, getSession, listPersonas } from "@/lib/api";
import PersonaModal from "@/components/PersonaModal";
import type { SessionSummary, Persona } from "@/lib/types";
import { useLanguage } from "@/i18n";

interface Message {
  role: "user" | "assistant";
  content: string;
  thinking?: string;
  thinkingStartedAt?: number;
}

export default function ChatPage() {
  const { t } = useLanguage();
  const [sessions, setSessions] = useState<SessionSummary[]>([]);
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [convId, setConvId] = useState<string | null>(null);
  const [selectedModel, setSelectedModel] = useState(() => {
    if (typeof window !== "undefined") return localStorage.getItem("nbus_chat_model") || "gemini-2.5-flash";
    return "gemini-2.5-flash";
  });
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [personaId, setPersonaId] = useState<number | null>(null);
  const [personaOpen, setPersonaOpen] = useState(false);
  const [attachedFiles, setAttachedFiles] = useState<File[]>([]);
  const [dragOver, setDragOver] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    loadSessions();
    listPersonas().then(setPersonas).catch(() => {});
  }, []);

  useEffect(() => {
    const input = fileInputRef.current;
    if (!input) return;
    const handler = () => handleFiles(input.files);
    input.addEventListener("change", handler);
    return () => input.removeEventListener("change", handler);
  }, []);

  useEffect(() => {
    scrollRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  async function loadSessions() {
    try {
      const s = await listSessions("chat");
      setSessions(s);
    } catch { /* ignore */ }
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
    } catch { /* ignore */ }
  }

  async function handleDeleteSession(id: string, e: React.MouseEvent) {
    e.stopPropagation();
    await deleteSession(id);
    setSessions((prev) => prev.filter((s) => s.id !== id));
    if (convId === id) {
      setConvId(null);
      setMessages([]);
    }
  }

  function newChat() {
    setConvId(null);
    setMessages([]);
  }

  function openFilePicker() {
    fileInputRef.current?.click();
  }

  function handleFiles(fs: FileList | null) {
    if (!fs || fs.length === 0) return;
    setAttachedFiles((prev) => [...prev, ...Array.from(fs)]);
  }

  function removeFile(i: number) {
    setAttachedFiles((prev) => prev.filter((_, idx) => idx !== i));
  }

  function handleDragOver(e: React.DragEvent) {
    e.preventDefault();
    e.stopPropagation();
    setDragOver(true);
  }

  function handleDragLeave(e: React.DragEvent) {
    e.preventDefault();
    e.stopPropagation();
    setDragOver(false);
  }

  function handleDrop(e: React.DragEvent) {
    e.preventDefault();
    e.stopPropagation();
    setDragOver(false);
    handleFiles(e.dataTransfer.files);
  }

  function handlePaste(e: React.ClipboardEvent) {
    const items = e.clipboardData?.items;
    if (!items) return;
    const fs: File[] = [];
    for (let i = 0; i < items.length; i++) {
      const f = items[i].getAsFile();
      if (f) fs.push(f);
    }
    if (fs.length > 0) {
      e.preventDefault();
      setAttachedFiles((prev) => [...prev, ...fs]);
    }
  }

  function fileIcon(file: File) {
    if (file.type.startsWith("image/")) return <ImageIcon className="w-2.5 h-2.5" />;
    return <FileText className="w-2.5 h-2.5" />;
  }

  async function send(text?: string) {
    const q = (text || input).trim();
    if ((!q && attachedFiles.length === 0) || loading) return;
    if (!text) setInput("");
    setMessages((prev) => [...prev, { role: "user", content: q }]);
    setLoading(true);

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

    const filesToSend = attachedFiles.length > 0 ? [...attachedFiles] : undefined;
    if (attachedFiles.length > 0) setAttachedFiles([]);

    try {
      for await (const chunk of askStream(q, convId || undefined, undefined, selectedModel, filesToSend)) {
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
        if (chunk.conversation_id && !convId) {
          setConvId(chunk.conversation_id);
          loadSessions(); // refresh sidebar
        }
        if (chunk.error) {
          fullText = `**Error**: ${chunk.error}`;
          updateAssistant(fullText, thinkingText);
        }
        if (chunk.done && !fullText.trim() && !thinkingText.trim()) {
          updateAssistant(t("chat.emptyResponse"));
        }
      }
    } catch (e) {
      fullText = `**${t("generic.connectionFailed")}**: ${e instanceof Error ? e.message : t("generic.unknownError")}`;
      updateAssistant(fullText, thinkingText);
    } finally {
      setLoading(false);
    }
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      send();
    }
  }

  const activeSession = sessions.find((s) => s.id === convId);

  return (
    <div className="flex h-[calc(100vh-0px)]">
      {/* Left Sidebar */}
      <aside className="w-72 flex-shrink-0 bg-white border-r border-slate-200 flex flex-col">
        <div className="p-4 border-b border-slate-100">
          <button
            onClick={newChat}
            className="btn-gradient w-full rounded-xl px-4 py-2.5 text-sm flex items-center justify-center gap-2"
          >
            <Plus className="w-4 h-4" />
            {t("chat.newChat")}
          </button>
        </div>

        {/* Persona selector */}
        <div className="px-4 py-2 border-b border-slate-100">
          <div className="flex items-center gap-2">
            <select
              value={personaId ?? ""}
              onChange={(e) => setPersonaId(e.target.value ? Number(e.target.value) : null)}
              className="flex-1 text-xs rounded-lg px-2 py-1.5 border border-slate-200 outline-none text-slate-600"
            >
              <option value="">{t("chat.defaultPersona")}</option>
              {personas.map((p) => (
                <option key={p.id} value={p.id}>{p.name}</option>
              ))}
            </select>
            <button
              onClick={() => setPersonaOpen(true)}
              className="p-1.5 rounded-lg hover:bg-slate-100 text-slate-500"
              title={t("chat.managePersonas")}
            >
              <Settings2 className="w-4 h-4" />
            </button>
          </div>
        </div>

        {/* Session list */}
        <div className="flex-1 overflow-y-auto">
          {sessions.length === 0 && (
            <p className="text-xs text-slate-400 text-center py-8 px-4">
              {t("chat.noChats")}
            </p>
          )}
          {sessions.map((s) => (
            <div
              key={s.id}
              role="button"
              tabIndex={0}
              onClick={() => loadSession(s.id)}
              onKeyDown={(e) => e.key === "Enter" && loadSession(s.id)}
              className={`w-full text-left px-4 py-3 hover:bg-slate-50 transition-colors group cursor-pointer ${
                convId === s.id ? "bg-violet-50 border-l-2 border-violet-500" : "border-l-2 border-transparent"
              }`}
            >
              <div className="flex items-center justify-between">
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-slate-800 truncate">
                    {s.title || t("chat.untitledChat")}
                  </p>
                  <p className="text-[10px] text-slate-400 mt-0.5">
                    {s.message_count} {t("table.messages")} · {s.last_access ? new Date(s.last_access).toLocaleDateString() : ""}
                  </p>
                </div>
                <button
                  onClick={(e) => handleDeleteSession(s.id, e)}
                  className="p-1 rounded-lg opacity-0 group-hover:opacity-100 hover:bg-red-100 transition-all"
                >
                  <Trash2 className="w-3 h-3 text-red-500" />
                </button>
              </div>
            </div>
          ))}
        </div>
      </aside>

      {/* Main Chat Area */}
      <div
        className="flex-1 flex flex-col bg-[#f8fafc] relative"
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
      >
        {/* Header */}
        <div className="px-6 py-4 bg-white border-b border-slate-200 flex items-center gap-4">
          <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-violet-500 to-fuchsia-500 flex items-center justify-center shadow-sm">
            <MessageSquare className="w-4.5 h-4.5 text-white" />
          </div>
          <div className="flex-1">
            <h1 className="text-lg font-bold text-slate-900">
              {activeSession?.title || t("chat.aiChat")}
            </h1>
            <p className="text-xs text-slate-500">
              {activeSession ? `${activeSession.message_count} ${t("table.messages")}` : t("chat.generalConversation")}
            </p>
          </div>
          <select
            value={selectedModel}
            onChange={(e) => { setSelectedModel(e.target.value); localStorage.setItem("nbus_chat_model", e.target.value); }}
            className="bg-slate-100 border border-slate-200 text-slate-700 text-xs font-bold rounded-xl px-3 py-2 outline-none"
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

        {/* Messages */}
        <div className="flex-1 overflow-y-auto px-6 py-4 space-y-4">
          {messages.length === 0 && (
            <div className="text-center py-16 animate-fade-in">
              <div className="w-16 h-16 rounded-3xl bg-gradient-to-br from-violet-500/20 to-fuchsia-500/20 flex items-center justify-center mx-auto mb-4">
                <MessageSquare className="w-8 h-8 text-violet/60" />
              </div>
              <p className="text-slate-500 text-sm font-medium">{t("chat.startConversation")}</p>
              <p className="text-slate-400 text-xs mt-1">{t("chat.chatCasualPrompt")}</p>
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
                    : "bg-white border border-slate-200 shadow-sm"
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
                              <th className="border border-slate-200 px-2 py-1 text-left text-slate-500 font-medium">{children}</th>
                            ),
                            td: ({ children }) => (
                              <td className="border border-slate-200/50 px-2 py-1 font-mono text-slate-700">{children}</td>
                            ),
                            code: ({ className, children, ...props }: React.ComponentPropsWithoutRef<"code"> & { className?: string }) => {
                              const isInline = !className;
                              if (isInline) {
                                return <code className="bg-slate-100 text-blue-600 rounded px-1.5 py-0.5 text-xs" {...props}>{children}</code>;
                              }
                              return <code className="block bg-slate-900 border border-slate-700 rounded-xl p-3 text-xs overflow-x-auto my-2 text-slate-200" {...props}>{children}</code>;
                            },
                            p: ({ children }) => <p className="text-slate-700 leading-relaxed mb-2 last:mb-0">{children}</p>,
                            strong: ({ children }) => <strong className="text-slate-900 font-semibold">{children}</strong>,
                            ul: ({ children }) => <ul className="list-disc list-inside space-y-1 text-slate-700">{children}</ul>,
                            ol: ({ children }) => <ol className="list-decimal list-inside space-y-1 text-slate-700">{children}</ol>,
                            h3: ({ children }) => <h3 className="text-slate-900 font-bold text-sm mt-3 mb-1">{children}</h3>,
                            h2: ({ children }) => <h2 className="text-slate-900 font-bold text-base mt-4 mb-2">{children}</h2>,
                            h1: ({ children }) => <h1 className="text-slate-900 font-black text-lg mt-4 mb-2">{children}</h1>,
                          }}
                        >
                          {m.content.replace(/```json[\s\S]*?```/g, "").trim()}
                        </ReactMarkdown>
                      )}
                    </>
                  ) : (
                    loading && i === messages.length - 1 && (
                      <div className="flex items-center gap-2 text-slate-400">
                        <div className="flex gap-1">
                          <div className="w-1.5 h-1.5 bg-violet-400 rounded-full animate-bounce" style={{ animationDelay: "0ms" }} />
                          <div className="w-1.5 h-1.5 bg-violet-400 rounded-full animate-bounce" style={{ animationDelay: "150ms" }} />
                          <div className="w-1.5 h-1.5 bg-violet-400 rounded-full animate-bounce" style={{ animationDelay: "300ms" }} />
                        </div>
                        <span className="text-xs">{t("chat.thinking")}...</span>
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

        {/* File preview chips */}
        {attachedFiles.length > 0 && (
          <div className="px-6 pt-3 flex flex-wrap gap-2">
            {attachedFiles.map((f, i) => (
              <div key={i} className="flex items-center gap-1.5 bg-violet-50 border border-violet-200 rounded-xl px-3 py-1.5 text-xs text-violet-700">
                <span className="flex-shrink-0">{fileIcon(f)}</span>
                <span className="truncate max-w-[160px] font-medium">{f.name}</span>
                <span className="text-violet-400">({(f.size / 1024).toFixed(0)} KB)</span>
                <button
                  onClick={() => removeFile(i)}
                  className="ml-0.5 p-0.5 rounded-lg hover:bg-violet-200 transition-colors"
                  title={t("chat.removeFile")}
                >
                  <X className="w-3 h-3" />
                </button>
              </div>
            ))}
          </div>
        )}

        {/* Input */}
        <div className="px-6 py-4 bg-white border-t border-slate-200">
          <div className="flex gap-3">
            <input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              onPaste={handlePaste}
              placeholder={t("chat.placeholder")}
              disabled={loading}
              className="flex-1 rounded-2xl px-5 py-3 text-sm border border-slate-200 bg-slate-50 outline-none focus:ring-2 focus:ring-violet-500/20 disabled:opacity-50"
            />
            <button
              onClick={openFilePicker}
              disabled={loading}
              className="p-3 rounded-2xl border border-slate-200 bg-slate-50 text-slate-500 hover:bg-violet-50 hover:text-violet-600 hover:border-violet-200 transition-colors"
              title={t("chat.attachFile")}
            >
              <Paperclip className="w-4 h-4" />
            </button>
            <button
              onClick={() => send()}
              disabled={loading || (!input.trim() && attachedFiles.length === 0)}
              className="btn-gradient rounded-2xl px-5 py-3 text-sm"
            >
              {loading ? <Activity className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
            </button>
          </div>
        </div>

        {/* Drop overlay */}
        {dragOver && (
          <div className="absolute inset-0 z-50 flex items-center justify-center bg-violet-500/10 backdrop-blur-sm border-2 border-dashed border-violet-400 rounded-xl m-2">
            <div className="bg-white rounded-2xl px-6 py-4 shadow-xl text-center">
              <Paperclip className="w-8 h-8 text-violet-500 mx-auto mb-2" />
              <p className="text-sm font-bold text-slate-700">{t("chat.dropFiles")}</p>
            </div>
          </div>
        )}
      </div>

      <input
        ref={fileInputRef}
        type="file"
        multiple
        accept=".pdf,.csv,.txt,.md,.json,.yaml,.png,.jpg,.jpeg,.webp,.gif"
        className="absolute left-[-9999px] top-0"
      />

      <PersonaModal open={personaOpen} onClose={() => {
        setPersonaOpen(false);
        listPersonas().then(setPersonas).catch(() => {});
      }} />
    </div>
  );
}

function ThinkingBox({ thinking, hasContent, startedAt }: { thinking: string; hasContent: boolean; startedAt?: number }) {
  const { t } = useLanguage();
  const [open, setOpen] = useState(true);
  const prevHasContent = useRef(false);
  const [elapsed, setElapsed] = useState(0);
  const finalElapsed = useRef(0);

  useEffect(() => {
    if (hasContent && !prevHasContent.current) {
      setOpen(false);
      prevHasContent.current = true;
      finalElapsed.current = startedAt ? (Date.now() - startedAt) / 1000 : 0;
    }
  }, [hasContent, startedAt]);

  useEffect(() => {
    if (!startedAt || hasContent) return;
    const update = () => setElapsed((Date.now() - startedAt) / 1000);
    update();
    const id = setInterval(update, 200);
    return () => clearInterval(id);
  }, [startedAt, hasContent]);

  if (!thinking) return null;

  const elapsedStr = hasContent
    ? `${finalElapsed.current.toFixed(1)}s`
    : `${elapsed.toFixed(1)}s`;

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
