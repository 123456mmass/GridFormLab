import fs from 'fs';
import path from 'path';
import MethodologyClient from './MethodologyClient';

interface MethodologyPageProps {
  params: Promise<{ method: string }>;
}

export default async function MethodologyPage({ params }: MethodologyPageProps) {
  const resolvedParams = await params;
  let method = decodeURIComponent(resolvedParams.method).toLowerCase();
  const mapping: Record<string, string> = {
    'newton-raphson': 'newton-raphson',
    'gauss-seidel': 'gauss-seidel',
    'fast-decoupled': 'fast-decoupled',
    'dc-power-flow': 'dc-power-flow',
    'dishonest-nr': 'dnr',
    'helm': 'helm',
    'helm-nr-hybrid': 'h-nr',
    'dynamic-homotopy': 'homotopy',
    'cpf-pc': 'cpf_pc',
    'cpf-ls': 'cpf_ls',
    'economic-dispatch': 'ed',
    'ac-opf': 'opf',
    // Extra aliases
    'nr': 'newton-raphson',
    'gs': 'gauss-seidel',
    'fdlf': 'fast-decoupled',
    'dc': 'dc-power-flow',
    'dnr': 'dnr',
    'h-nr': 'h-nr',
    'homotopy': 'homotopy',
    'cpf_pc': 'cpf_pc',
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
    thContent = fs.readFileSync(path.join(contentDir, 'th.md'), 'utf-8');
  } catch {
    enContent = `# ${method.toUpperCase()}\n\nDetailed methodology documentation is currently being written. Please check back later.`;
    thContent = `# ${method.toUpperCase()}\n\nกำลังจัดทำเอกสารอธิบายอัลกอริทึมนี้ โปรดกลับมาตรวจสอบอีกครั้งในภายหลัง`;
  }

  return (
    <div className="min-h-screen bg-slate-50 py-12 px-6">
      <div className="max-w-4xl mx-auto">
        <MethodologyClient enContent={enContent} thContent={thContent} />
      </div>
    </div>
  );
}
