# Optimal Power Flow (OPF)

**Optimal Power Flow (OPF)** extends Economic Dispatch by combining it with the full AC Power Flow equations. It optimizes a specific objective (like minimizing cost or losses) while ensuring that no physical limits of the network are violated.

## Concept
OPF is a large-scale non-linear programming (NLP) problem.

**Objective Function:**
$$ \min F(x, u) $$
(e.g., total fuel cost, total active power loss).

**Equality Constraints (Power Flow Equations):**
$$ g(x, u) = 0 $$
Active and reactive power balance at every bus (this is exactly the AC power flow constraints).

**Inequality Constraints (Security Limits):**
$$ h_{min} \le h(x, u) \le h_{max} $$
Includes generator limits ($P_{min}, P_{max}, Q_{min}, Q_{max}$), bus voltage limits ($V_{min}, V_{max}$), and line flow thermal limits ($S_{line} \le S_{max}$).

## Solution Methods
OPF can be solved using various advanced mathematical optimization techniques such as:
- Interior Point Method (IPM)
- Sequential Quadratic Programming (SQP)
- Particle Swarm Optimization (PSO)





## Calculation Example

Consider a highly simplified 2-bus system to demonstrate the basic computational flow of this methodology.

**System Parameters:**
- Bus 1: Slack Bus, $V_1 = 1.0 \angle 0^\circ$ pu
- Bus 2: PQ Bus (Load), $P_D = 0.5$ pu, $Q_D = 0.2$ pu
- Line Admittance: $Y_{12} = -j10$ pu

**Step 1: Formulate the Matrix**
The admittance matrix ($Y_{bus}$) is formed directly from the line parameters:
$$
Y_{bus} = \begin{bmatrix} -j10 & j10 \\ j10 & -j10 \end{bmatrix}
$$

**Step 2: Initialization**
Set the initial guess for the unknown voltage at Bus 2:
$V_2^{(0)} = 1.0 \angle 0^\circ$

**Step 3: Execute Iteration Logic**
Following the algorithm's formulation, we calculate the active power mismatch at Bus 2:
$$ P_{2, calc} = |V_2| |V_1| |Y_{21}| \cos(\theta_{21} - \delta_2 + \delta_1) + |V_2|^2 |Y_{22}| \cos(\theta_{22}) $$

With the flat start ($V_2 = 1.0$), $P_{2, calc} = 0$, leading to a mismatch $\Delta P_2 = -0.5 - 0 = -0.5$ pu.

**Step 4: Update State**
Using the solver's specific update mechanism (e.g., Jacobian inversion for NR, or sequential substitution for GS), we find the next voltage state:
$V_2^{(1)} \approx 0.98 \angle -2.8^\circ$

**Step 5: Convergence Check**
Since the mismatch is still greater than the tolerance $\epsilon$ ($10^{-4}$), the process repeats. In a typical scenario, it converges completely within 3-5 iterations.
