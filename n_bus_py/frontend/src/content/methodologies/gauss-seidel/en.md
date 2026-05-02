# Gauss-Seidel Method

The **Gauss-Seidel (GS)** method is one of the oldest and simplest iterative techniques for solving the power flow problem. It works by updating the voltage of each bus sequentially, using the most recently calculated voltage values as soon as they become available.

## 1. Core Concept

The apparent power injected into bus $i$ is given by:

$$
S_i = P_i + jQ_i = V_i I_i^*
$$

Where the current injected into the bus is:

$$
I_i = \sum_{j=1}^{N} Y_{ij} V_j
$$

By substituting the current equation into the complex power equation and rearranging for $V_i$, we get the fundamental update equation for the Gauss-Seidel method:

$$
V_i^{(k+1)} = \frac{1}{Y_{ii}} \left[ \frac{P_i - jQ_i}{(V_i^{(k)})^*} - \sum_{j=1}^{i-1} Y_{ij} V_j^{(k+1)} - \sum_{j=i+1}^{N} Y_{ij} V_j^{(k)} \right]
$$

Notice that for buses $j < i$, the newly calculated voltage from the current iteration $k+1$ is used immediately, which improves the convergence rate compared to the standard Jacobi method.

## 2. Handling Different Bus Types

### PQ Buses (Load Buses)
For PQ buses, both $P$ and $Q$ are known. The equation above is used directly to find the new voltage phasor $V_i$.

### PV Buses (Generator Buses)
For PV buses, $P$ and the voltage magnitude $|V|$ are known, but $Q$ is unknown. 
1. First, $Q_i$ must be estimated using the current voltages:
   $$ Q_i^{(k+1)} = -\text{Im} \left\{ (V_i^{(k)})^* \sum_{j=1}^{N} Y_{ij} V_j^{(k)} \right\} $$
2. Check if $Q_i$ violates the generator's reactive power limits ($Q_{min} \le Q_i \le Q_{max}$). If it does, $Q_i$ is set to the limit, and the bus temporarily acts as a PQ bus.
3. Then, calculate the new voltage $V_i^{(k+1)}$ using the estimated $Q_i$.
4. Finally, force the magnitude of the new voltage back to the specified value $|V_{spec}|$, keeping only the newly calculated angle:
   $$ V_i^{(k+1)} = |V_{spec}| \angle \delta_i^{(k+1)} $$

## 3. Iteration Process

1. **Initialize:** Set all unknown voltages to a flat start (e.g., $1.0 + j0$ pu).
2. **Update sequentially:** For each bus $i = 2, 3, \dots, N$, compute the new voltage $V_i^{(k+1)}$.
3. **Check Convergence:** If the maximum change in voltage $|V_i^{(k+1)} - V_i^{(k)}| < \epsilon$ for all buses, stop.
4. **Acceleration (Optional):** Apply an acceleration factor $\alpha$ (typically 1.4 to 1.6) to speed up convergence:
   $$ V_i^{(k+1)} = V_i^{(k)} + \alpha (V_{i, calc}^{(k+1)} - V_i^{(k)}) $$
5. Repeat until convergence.

> **Pros**: Extremely simple to program, minimal memory requirements (no matrices to invert).
> **Cons**: Very slow convergence rate (linear). The number of iterations increases drastically as the system size grows. Seldom used for systems larger than a few hundred buses.






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
