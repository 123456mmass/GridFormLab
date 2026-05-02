"use client";

import type { BusResult, LineResult } from "@/lib/types";

interface NetworkDiagramProps {
  buses: BusResult[];
  lines: LineResult[];
  className?: string;
}

const BUS_POSITIONS: Record<number, { x: number; y: number }> = {
  1: { x: 150, y: 50 },
  2: { x: 400, y: 50 },
  3: { x: 100, y: 200 },
  4: { x: 300, y: 200 },
  5: { x: 450, y: 200 },
};

function voltageColor(v: number): string {
  if (v < 0.95) return "#ef4444";
  if (v < 0.98) return "#f59e0b";
  return "#10b981";
}

export function NetworkDiagram({ buses, lines, className = "" }: NetworkDiagramProps) {
  const width = 560;
  const height = 280;

  return (
    <div className="w-full bg-white rounded-[2rem] border border-slate-100 p-6 shadow-sm mt-4">
      <svg viewBox={`0 0 ${width} ${height}`} className={`w-full ${className}`} style={{ maxHeight: 280 }}>
        {/* Lines */}
        {lines.map((l, i) => {
          const from = BUS_POSITIONS[l.from_bus];
          const to = BUS_POSITIONS[l.to_bus];
          if (!from || !to) return null;
          return (
            <line
              key={i}
              x1={from.x} y1={from.y} x2={to.x} y2={to.y}
              stroke="#e2e8f0" strokeWidth={2}
              strokeLinecap="round"
            />
          );
        })}

        {/* Buses */}
        {buses.map((b) => {
          const pos = BUS_POSITIONS[b.bus_id];
          if (!pos) return null;
          const color = voltageColor(b.voltage_pu);
          return (
            <g key={b.bus_id}>
              <circle
                cx={pos.x} cy={pos.y} r={22}
                fill="#ffffff"
                stroke={color} strokeWidth={3}
                className="shadow-sm"
              />
              <text
                x={pos.x} y={pos.y}
                textAnchor="middle" dominantBaseline="middle"
                fill="#1e293b" fontSize="11" fontWeight="800"
              >
                {b.bus_id}
              </text>
              <text
                x={pos.x} y={pos.y + 35}
                textAnchor="middle" fill={color} fontSize="10" fontWeight="700"
                fontFamily="monospace"
              >
                {b.voltage_pu.toFixed(4)}
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
}
