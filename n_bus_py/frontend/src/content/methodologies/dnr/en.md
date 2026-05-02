# Dishonest Newton-Raphson (DNR)

The **Dishonest Newton-Raphson** (or Modified Newton-Raphson) method is a variant of the standard NR algorithm. Instead of recalculating and factoring the Jacobian matrix at every single iteration, DNR holds the Jacobian constant for $k$ iterations before rebuilding it.

## Concept

In standard NR, the most computationally expensive step is calculating $J^{-1}$. Since the system approaches a linear state near the solution, $J$ does not change significantly between late iterations. 

By freezing the Jacobian, we trade off the number of iterations for faster execution time per iteration:
$$ \Delta x = J_{frozen}^{-1} \begin{bmatrix} \Delta P \\ \Delta Q \end{bmatrix} $$

> **Pros**: Faster per-iteration time, good for systems where building the Jacobian is very costly.
> **Cons**: More iterations required to converge. May fail if the initial guess is far from the solution.





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
