# HELM-NR (H-NR)

The **HELM-NR** method is a hybrid algorithm that combines the robustness of HELM with the blistering quadratic convergence speed of the Newton-Raphson method.

## Concept

Newton-Raphson is incredibly fast but heavily dependent on a good initial guess (flat start is usually fine, but fails for highly stressed systems). HELM does not require an initial guess but is computationally heavy for the final refinement steps.

**H-NR** uses HELM to calculate a "Warm Start" — getting the system voltages very close to the actual solution. Then, it switches to Newton-Raphson for the final 1-2 iterations to rapidly snap to the exact tolerance limit.

> **Pros**: The best of both worlds. Unfailing robustness even in stressed systems, combined with ultra-fast final convergence.
> **Cons**: More complex implementation as it requires both solvers to be integrated.





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
