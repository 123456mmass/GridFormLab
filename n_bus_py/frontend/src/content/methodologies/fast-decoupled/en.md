# Fast Decoupled Load Flow (FDLF)

The **Fast Decoupled Load Flow (FDLF)** method is a simplified version of the Newton-Raphson method, optimized for speed and reduced memory usage. It takes advantage of the physical properties of typical power transmission systems.

## 1. Core Concept

In a typical transmission network, the following physical properties are observed:
1. **Strong coupling** between Active Power ($P$) and Voltage Angle ($\delta$).
2. **Strong coupling** between Reactive Power ($Q$) and Voltage Magnitude ($|V|$).
3. **Weak coupling** between $P$ and $|V|$, and between $Q$ and $\delta$.

FDLF capitalizes on this by ignoring the weak coupling elements in the Jacobian matrix ($J_{12}$ and $J_{21}$).

## 2. Decoupling the Jacobian

The standard Newton-Raphson equation:

$$
\begin{bmatrix} \Delta P \\ \Delta Q \end{bmatrix} = \begin{bmatrix} J_{11} & J_{12} \\ J_{21} & J_{22} \end{bmatrix} \begin{bmatrix} \Delta \delta \\ \Delta |V| \end{bmatrix}
$$

Is decoupled by assuming $J_{12} \approx 0$ and $J_{21} \approx 0$:

$$
\Delta P = J_{11} \Delta \delta
$$
$$
\Delta Q = J_{22} \Delta |V|
$$

## 3. The XB and BX Schemes

Further approximations are made, assuming $\cos(\theta) \approx 1$, $G_{ij} \ll B_{ij}$, and $|V_i| \approx 1.0$ pu. The Jacobian matrices are replaced by constant admittance matrices $B'$ and $B''$:

$$
\frac{\Delta P}{|V|} = -B' \Delta \delta
$$
$$
\frac{\Delta Q}{|V|} = -B'' \Delta |V|
$$

The matrices $B'$ and $B''$ are constant and only need to be triangulated (factorized) **once** before the iterative process begins, drastically reducing the computational time per iteration.

## 4. Iteration Process

1. **Calculate** $\Delta P$ and $\Delta Q$.
2. **Solve** for $\Delta \delta$ using the constant $B'$ matrix: $\Delta \delta = -[B']^{-1} (\frac{\Delta P}{|V|})$.
3. **Update** angles $\delta$.
4. **Solve** for $\Delta |V|$ using the constant $B''$ matrix: $\Delta |V| = -[B'']^{-1} (\frac{\Delta Q}{|V|})$.
5. **Update** magnitudes $|V|$.
6. Repeat until convergence.

> **Pros**: Extremely fast per iteration. Less memory required to store matrices. Great for contingency analysis.
> **Cons**: Slower convergence rate (linear) compared to NR. May fail to converge in systems with high R/X ratios (e.g., distribution networks).






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
