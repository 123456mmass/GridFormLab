# Newton-Raphson Method

The **Newton-Raphson (NR)** method is the industry standard for solving the non-linear power flow problem. It uses Taylor series expansion to iteratively solve for the voltage magnitudes and angles of the buses in the power system.

## 1. Core Concept

The power flow problem defines the mismatch between the specified power injections and the calculated power flowing into the network. For any bus $i$, the active ($P_i$) and reactive ($Q_i$) power can be written as:

$$
P_i = |V_i| \sum_{j=1}^{N} |V_j| |Y_{ij}| \cos(\theta_{ij} - \delta_i + \delta_j)
$$

$$
Q_i = -|V_i| \sum_{j=1}^{N} |V_j| |Y_{ij}| \sin(\theta_{ij} - \delta_i + \delta_j)
$$

where:
- $|V_i|, \delta_i$ are the voltage magnitude and angle at bus $i$.
- $|Y_{ij}|, \theta_{ij}$ are the magnitude and angle of the $Y_{bus}$ matrix element.

## 2. The Jacobian Matrix

The NR method formulates the problem as finding the roots of the mismatch equations $\Delta f(x) = 0$. In each iteration $k$, the state vector $\Delta x$ (containing $\Delta \delta$ and $\Delta |V|$) is updated by solving the linear system:

$$
\begin{bmatrix} \Delta P \\ \Delta Q \end{bmatrix} = \begin{bmatrix} J_{11} & J_{12} \\ J_{21} & J_{22} \end{bmatrix} \begin{bmatrix} \Delta \delta \\ \Delta |V| \end{bmatrix}
$$

The matrix $J$ is the **Jacobian Matrix**, containing partial derivatives of $P$ and $Q$ with respect to $\delta$ and $|V|$. 

## 3. Iteration Process

1. **Initialize** flat start voltages (e.g., $1.0 \angle 0^\circ$ for PQ buses).
2. **Calculate** the mismatches $\Delta P$ and $\Delta Q$.
3. **Check Convergence**: If $\max(|\Delta P|, |\Delta Q|) < \epsilon$, stop.
4. **Form the Jacobian**: Calculate partial derivatives at the current voltage estimates.
5. **Solve**: $\Delta x = J^{-1} \begin{bmatrix} \Delta P \\ \Delta Q \end{bmatrix}$.
6. **Update**: $x^{(k+1)} = x^{(k)} + \Delta x$.
7. Repeat from step 2.

> **Pros**: Quadratic convergence rate (very fast near the solution), highly robust for large networks.
> **Cons**: Computationally expensive to rebuild and invert the Jacobian matrix at every iteration.






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
