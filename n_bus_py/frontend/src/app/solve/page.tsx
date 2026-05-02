import { Suspense } from "react";
import SolveClient from "./SolveClient";

export default function SolvePage() {
  return (
    <Suspense fallback={<div className="p-10 text-sm text-slate-500">Loading solver studio...</div>}>
      <SolveClient />
    </Suspense>
  );
}
