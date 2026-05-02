# Homotopy Continuation

**Homotopy Continuation** is an advanced numerical technique used for finding all isolated roots of polynomial systems, heavily used in power systems to trace the P-V curves up to the point of voltage collapse.

## Concept

Similar to HELM, Homotopy creates a continuous deformation from a known, solved system (the starting system $G(x)=0$) to the target system we want to solve ($F(x)=0$).

This deformation is defined by a Homotopy function $H(x, \lambda)$, where $\lambda$ goes from $0$ to $1$:
$$ H(x, \lambda) = (1-\lambda)G(x) + \lambda F(x) = 0 $$

The solver starts at $\lambda = 0$ and traces the path by incrementally increasing $\lambda$ and solving for $x$ using a predictor-corrector method, until $\lambda = 1$.

> **Pros**: Incredibly robust. Capable of finding multiple solutions (including low-voltage unstable roots).
> **Cons**: Extremely slow. Path tracing requires numerous matrix inversions along the curve.





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
