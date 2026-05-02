import { NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

interface MethodologyRouteContext {
  params: Promise<{ method: string }>;
}

export async function GET(
  _request: Request,
  { params }: MethodologyRouteContext
) {
  const resolvedParams = await params;
  let method = resolvedParams.method.toLowerCase();
  
  const mapping: Record<string, string> = {
    'newton-raphson': 'newton-raphson',
    'nr': 'newton-raphson',
    'gauss-seidel': 'gauss-seidel',
    'gs': 'gauss-seidel',
    'fast decoupled': 'fast-decoupled',
    'fdlf': 'fast-decoupled',
    'dc power flow': 'dc-power-flow',
    'dc': 'dc-power-flow',
    'dnr': 'dnr',
    'helm': 'helm',
    'h-nr': 'h-nr',
    'homotopy': 'homotopy',
    'cpf pc': 'cpf_pc',
    'cpf_pc': 'cpf_pc',
    'cpf ls': 'cpf_ls',
    'cpf_ls': 'cpf_ls',
    'ed': 'ed',
    'opf': 'opf'
  };

  if (mapping[method]) {
    method = mapping[method];
  }

  const contentDir = path.join(process.cwd(), 'src/content/methodologies', method);
  
  let enContent = "";
  let thContent = "";
  
  try {
    enContent = fs.readFileSync(path.join(contentDir, 'en.md'), 'utf-8');
  } catch {
    enContent = `# ${method.toUpperCase()}\n\nDetailed methodology documentation is currently being written. Please check back later.`;
  }

  try {
    thContent = fs.readFileSync(path.join(contentDir, 'th.md'), 'utf-8');
  } catch {
    thContent = `# ${method.toUpperCase()}\n\nกำลังจัดทำเอกสารอธิบายอัลกอริทึมนี้ โปรดกลับมาตรวจสอบอีกครั้งในภายหลัง`;
  }

  return NextResponse.json({ en: enContent, th: thContent });
}
