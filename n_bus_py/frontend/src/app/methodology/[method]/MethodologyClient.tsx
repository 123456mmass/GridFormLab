"use client";

import React, { useState, useEffect, useMemo } from "react";
import type { ComponentPropsWithoutRef, ReactNode } from "react";
import ReactMarkdown from "react-markdown";
import remarkMath from "remark-math";
import rehypeKatex from "rehype-katex";
import remarkGfm from "remark-gfm";
import { ArrowLeft, BookOpen, ListTree } from "lucide-react";
import { useLanguage } from "@/i18n";
import "katex/dist/katex.min.css";

interface Props {
  enContent: string;
  thContent: string;
}

interface HeadingItem {
  level: number;
  text: string;
  id: string;
}

function slugify(text: string) {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

function extractHeadings(markdown: string): HeadingItem[] {
  const headingRegex = /^(#{1,3})\s+(.+)$/gm;
  const headings: HeadingItem[] = [];
  let match: RegExpExecArray | null;
  while ((match = headingRegex.exec(markdown)) !== null) {
    const level = match[1].length;
    const text = match[2].trim();
    const id = slugify(text);
    headings.push({ level, text, id });
  }
  return headings;
}

function flattenNode(node: ReactNode): string {
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (!React.isValidElement<{ children?: ReactNode }>(node)) return "";
  return React.Children.toArray(node.props.children).map(flattenNode).join("");
}

function createHeadingRenderer(level: 1 | 2 | 3 | 4 | 5 | 6) {
  return function HeadingRenderer({
    children,
    ...props
  }: ComponentPropsWithoutRef<`h${typeof level}`>) {
    const text = React.Children.toArray(children).map(flattenNode).join("");
    return React.createElement(`h${level}`, { ...props, id: slugify(text) }, children);
  };
}

export default function MethodologyClient({ enContent, thContent }: Props) {
  const { t } = useLanguage();
  const [lang, setLang] = useState<"TH" | "EN">("TH");
  const [scrollProgress, setScrollProgress] = useState(0);
  const [activeId, setActiveId] = useState<string>("");

  const content = lang === "TH" ? thContent : enContent;
  const headings = useMemo(() => extractHeadings(content), [content]);

  useEffect(() => {
    const handleScroll = () => {
      // Progress bar
      const totalScroll = document.documentElement.scrollTop;
      const windowHeight = document.documentElement.scrollHeight - document.documentElement.clientHeight;
      const scroll = windowHeight > 0 ? `${totalScroll / windowHeight}` : "0";
      setScrollProgress(Number(scroll));

      // ScrollSpy for TOC
      const headingElements = headings.map(h => document.getElementById(h.id));
      const scrollPosition = window.scrollY + 100; // offset

      let currentId = "";
      for (const el of headingElements) {
        if (el && el.offsetTop <= scrollPosition) {
          currentId = el.id;
        }
      }
      if (currentId) setActiveId(currentId);
    };

    window.addEventListener('scroll', handleScroll);
    handleScroll(); // initialize
    return () => window.removeEventListener('scroll', handleScroll);
  }, [headings]);

  const scrollToSection = (id: string) => {
    const el = document.getElementById(id);
    if (el) {
      window.scrollTo({
        top: el.offsetTop - 80,
        behavior: 'smooth'
      });
    }
  };

  return (
    <div className="min-h-screen bg-white text-slate-900 selection:bg-blue-200 flex flex-col">
      {/* Scroll Progress Bar */}
      <div 
        className="fixed top-0 left-0 h-1 bg-blue-600 z-50 transition-all duration-150 ease-out"
        style={{ width: `${scrollProgress * 100}%` }}
      />

      {/* Sticky Header */}
      <header className="sticky top-0 z-40 bg-white/80 backdrop-blur-xl border-b border-slate-200/60">
        <div className="max-w-7xl mx-auto px-6 h-16 flex items-center justify-between">
          <button 
            onClick={() => window.close()}
            className="flex items-center gap-2 text-slate-500 hover:text-slate-900 transition-colors font-medium text-sm"
          >
            <ArrowLeft className="w-4 h-4" />
            {t("methodology.closeWindow")}
          </button>

          <div className="flex items-center gap-2 bg-slate-100 p-1 rounded-full border border-slate-200/50 shadow-inner">
            <button
              onClick={() => setLang("EN")}
              className={`px-4 py-1 text-xs font-bold rounded-full transition-all duration-300 ${
                lang === "EN" 
                  ? "bg-white text-blue-600 shadow-sm ring-1 ring-slate-200" 
                  : "text-slate-500 hover:text-slate-700"
              }`}
            >
              EN
            </button>
            <button
              onClick={() => setLang("TH")}
              className={`px-4 py-1 text-xs font-bold rounded-full transition-all duration-300 ${
                lang === "TH" 
                  ? "bg-white text-blue-600 shadow-sm ring-1 ring-slate-200" 
                  : "text-slate-500 hover:text-slate-700"
              }`}
            >
              TH
            </button>
          </div>
        </div>
      </header>

      {/* Main Layout with Sidebar */}
      <div className="flex-1 max-w-7xl mx-auto w-full px-6 flex items-start gap-12">
        
        {/* Left Sidebar: Table of Contents */}
        <aside className="hidden lg:block w-64 sticky top-24 max-h-[calc(100vh-8rem)] overflow-y-auto py-8">
          <div className="flex items-center gap-2 mb-6 text-slate-800 font-bold">
            <ListTree className="w-5 h-5 text-blue-600" />
            <span>{t("methodology.toc")}</span>
          </div>
          <nav className="space-y-1 border-l-2 border-slate-100">
            {headings.map((h, i) => (
              <button
                key={i}
                onClick={() => scrollToSection(h.id)}
                className={`block w-full text-left py-2 px-4 text-sm transition-colors border-l-2 -ml-[2px] ${
                  activeId === h.id 
                    ? "border-blue-600 text-blue-700 font-bold bg-blue-50/50 rounded-r-lg" 
                    : "border-transparent text-slate-500 hover:text-slate-900 hover:border-slate-300"
                } ${h.level === 1 ? "font-semibold text-slate-800" : h.level === 3 ? "pl-8 text-xs" : "pl-6"}`}
              >
                {h.text}
              </button>
            ))}
          </nav>
        </aside>

        {/* Main Content Container */}
        <main className="flex-1 max-w-3xl py-12 lg:py-20">
          
          {/* Decorator */}
          <div className="flex items-center gap-3 mb-10">
            <div className="p-3 bg-blue-50 text-blue-600 rounded-2xl border border-blue-100/50 shadow-sm">
              <BookOpen className="w-6 h-6" />
            </div>
            <span className="text-sm font-bold tracking-widest uppercase text-blue-600">
              {t("methodology.reference")}
            </span>
          </div>

          {/* Markdown Render */}
          <article className="prose prose-slate max-w-none 
            prose-headings:text-slate-900 prose-headings:tracking-tight scroll-mt-24
            prose-h1:text-4xl lg:prose-h1:text-5xl prose-h1:font-black prose-h1:mb-8 prose-h1:leading-tight
            prose-h2:text-2xl prose-h2:font-bold prose-h2:mt-16 prose-h2:mb-6 prose-h2:pb-4 prose-h2:border-b prose-h2:border-slate-100
            prose-h3:text-xl prose-h3:font-semibold
            prose-p:text-slate-600 prose-p:leading-relaxed prose-p:text-[1.05rem]
            prose-li:text-slate-600 prose-li:text-[1.05rem] prose-li:leading-relaxed
            prose-a:text-blue-600 prose-a:font-medium hover:prose-a:text-blue-700 hover:prose-a:underline-offset-4
            prose-strong:text-slate-900 prose-strong:font-bold
            prose-blockquote:border-l-4 prose-blockquote:border-blue-500 prose-blockquote:bg-gradient-to-r prose-blockquote:from-blue-50/50 prose-blockquote:to-transparent prose-blockquote:py-2 prose-blockquote:px-6 prose-blockquote:rounded-r-2xl prose-blockquote:not-italic prose-blockquote:text-slate-700
            
            /* Katex Container Styling */
            [&_.math-display]:overflow-x-auto [&_.math-display]:py-6 [&_.math-display]:my-8 [&_.math-display]:bg-slate-50 [&_.math-display]:rounded-3xl [&_.math-display]:border [&_.math-display]:border-slate-100 [&_.math-display]:flex [&_.math-display]:justify-center [&_.math-display]:shadow-inner
          ">
            <ReactMarkdown
              remarkPlugins={[remarkMath, remarkGfm]}
              rehypePlugins={[rehypeKatex]}
              components={{
                a: ({ node, ...props }) => {
                  void node;
                  return <a {...props} target="_blank" rel="noopener noreferrer" />;
                },
                h1: createHeadingRenderer(1),
                h2: createHeadingRenderer(2),
                h3: createHeadingRenderer(3),
                h4: createHeadingRenderer(4),
                h5: createHeadingRenderer(5),
                h6: createHeadingRenderer(6),
              }}
            >
              {content}
            </ReactMarkdown>
          </article>

          {/* Footer */}
          <footer className="mt-32 pt-8 border-t border-slate-200/60 text-center text-slate-400 text-sm font-medium">
            <p>N-Bus Power Flow Studio &copy; {new Date().getFullYear()}</p>
          </footer>

        </main>
      </div>
    </div>
  );
}
