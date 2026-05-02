# DC Power Flow

The **DC Power Flow** method is a highly simplified, linear approximation of the AC power flow problem. It focuses exclusively on active power ($P$) flows and voltage angles ($\delta$), completely ignoring reactive power ($Q$) and assuming all voltage magnitudes are nominal ($1.0$ pu).

## 1. Core Concept

The DC Power Flow makes three major assumptions to linearize the power flow equations:

1. **Line resistance is negligible** ($R \ll X$). Therefore, the branch admittance is purely reactive: $Y = \frac{1}{jX} = -jB$.
2. **Voltage angles are very small**. This means the difference in angle between two adjacent buses ($\delta_i - \delta_j$) is small, allowing the approximations: 
   - $\sin(\delta_i - \delta_j) \approx \delta_i - \delta_j$
   - $\cos(\delta_i - \delta_j) \approx 1$
3. **Voltage magnitudes are flat**. The magnitude of voltage at every bus is assumed to be strictly $1.0$ pu ($|V_i| \approx 1.0$).

## 2. Linear Formulation

Applying these three assumptions to the standard active power flow equation:

$$
P_i = |V_i| \sum_{j=1}^{N} |V_j| |Y_{ij}| \cos(\theta_{ij} - \delta_i + \delta_j)
$$

The equation simplifies dramatically into a set of linear equations:

$$
P = B_{bus} \cdot \Delta \delta
$$

Where:
- $P$ is the vector of net active power injections.
- $B_{bus}$ is the susceptance matrix (derived from the $Y_{bus}$ matrix by ignoring resistances).
- $\Delta \delta$ is the vector of bus voltage angles.

## 3. Solving the System

Since the equation $P = B_{bus} \delta$ is strictly linear, the solution is non-iterative and extremely fast:

$$
\delta = B_{bus}^{-1} \cdot P
$$

Once the angles $\delta$ are found, the real power flow across any transmission line from bus $i$ to bus $j$ is calculated as:

$$
P_{ij} = \frac{\delta_i - \delta_j}{X_{ij}}
$$

## 4. Characteristics

> **Pros**: **Extremely fast** (non-iterative matrix inversion), always converges (guaranteed solution), and highly predictable. It is heavily used in electricity market clearing (e.g., Locational Marginal Pricing), security-constrained economic dispatch (SCED), and real-time contingency analysis.
> **Cons**: Ignores reactive power and voltage magnitude completely. It is only an approximation, meaning it cannot detect voltage collapse or reactive limit violations. Generally has an error margin of about 5% compared to AC power flow.






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
