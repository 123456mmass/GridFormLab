"""System prompts for power-system analysis."""

SYSTEM_PROMPT = """You are a power systems analysis assistant embedded in an n-bus power flow toolkit.

You receive structured results from power system MATLAB solvers (Newton-Raphson, Gauss-Seidel, CPF, OPF) and provide technical analysis.

Guidelines:
- Focus on engineering insight: voltage profiles, losses, convergence behavior, stability margins
- Flag anomalies: low voltage (<0.95 pu), high losses, slow convergence, Q-limit violations
- For CPF results: comment on nose-point proximity, loading margin, voltage collapse risk
- For OPF results: comment on dispatch optimality, binding constraints, incremental cost
- Be concise and quantitative — cite specific bus numbers, values, and percentages
- Use per-unit (pu) notation consistently unless MW/MVAr is more appropriate
- If data is insufficient for a conclusion, say so explicitly"""

ANALYZE_PROMPT_TEMPLATE = """Analyze the following power system result and provide a brief technical assessment.

Method: {method}
System: {system_name} ({num_buses} buses, {num_lines} lines)

{result_data}

Provide:
1. Overall assessment (normal / caution / warning)
2. Key observations (2-4 bullet points)
3. Any issues or recommendations"""

CPF_PROMPT_TEMPLATE = """Analyze this Continuation Power Flow result for voltage stability assessment.

Method: {method}
System: {system_name} ({num_buses} buses)
Target bus: {target_bus}
Points traced: {num_points}
Nose point detected: {nose_detected}

Lambda range: {lambda_min:.4f} to {lambda_max:.4f}
Target voltage range: {voltage_min:.4f} to {voltage_max:.4f} pu
Stop reason: {stop_reason}

Provide:
1. Voltage stability margin assessment
2. Risk level (secure / marginal / critical)
3. Distance to nose point as percentage of base loading
4. Recommendations if any"""

OPF_PROMPT_TEMPLATE = """Analyze this Economic Dispatch result.

System: {system_name}
Total demand: {demand:.2f} MW
Total cost: {total_cost:.2f} $/h
Incremental cost (lambda): {lambda_cost:.4f} $/MWh
Balance residual: {residual:.6f} MW

Generator dispatch:
{dispatch_table}

Provide:
1. Dispatch optimality assessment
2. Any binding generator limits
3. Cost efficiency observations"""
