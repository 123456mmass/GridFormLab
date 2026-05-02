# Economic Dispatch (ED)

**Economic Dispatch (ED)** is an optimization problem that determines the most cost-effective power output for each generator in a system to meet the total load demand, ignoring the transmission network limits.

## Concept
The objective is to minimize the total generation cost $F_T$:
$$ \min F_T = \sum_{i=1}^{N_g} F_i(P_{gi}) $$
where $F_i(P_{gi})$ is the cost function of generator $i$, typically modeled as a quadratic polynomial: $F_i(P_{gi}) = a_i + b_i P_{gi} + c_i P_{gi}^2$.

### Equality Constraint
The total generation must exactly equal the total load plus losses (in standard ED, losses are often ignored or approximated using B-coefficients):
$$ \sum_{i=1}^{N_g} P_{gi} = P_{load} + P_{loss} $$

### Solution via KKT Conditions
Using Lagrange multipliers ($\lambda$), the condition for optimal dispatch without hitting limits is that the incremental cost of all active generators must be equal:
$$ rac{dF_1}{dP_{g1}} = rac{dF_2}{dP_{g2}} = \dots = \lambda $$





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
