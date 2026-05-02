import os
import glob

content_dir = r"c:\Users\qwert\OneDrive\Desktop\api\n_bus_py\frontend\src\content\methodologies"

refs_en = {
    "newton-raphson": "\n\n## References\n- Saadat, H. (1999). *Power System Analysis*. WCB/McGraw-Hill. (Chapter 6: Power Flow Analysis)\n- Tinney, W. F., & Hart, C. E. (1967). Power flow solution by Newton's method. *IEEE Transactions on Power Apparatus and Systems*.",
    "gauss-seidel": "\n\n## References\n- Saadat, H. (1999). *Power System Analysis*. WCB/McGraw-Hill. (Chapter 6: Power Flow Analysis)\n- Grainger, J. J., & Stevenson, W. D. (1994). *Power System Analysis*. McGraw-Hill.",
    "fast-decoupled": "\n\n## References\n- Stott, B., & Alsac, O. (1974). Fast Decoupled Load Flow. *IEEE Transactions on Power Apparatus and Systems*.\n- Saadat, H. (1999). *Power System Analysis*. WCB/McGraw-Hill. (Chapter 6.5: Fast Decoupled Power Flow)",
    "dc-power-flow": "\n\n## References\n- Wood, A. J., Wollenberg, B. F., & Sheblé, G. B. (2013). *Power Generation, Operation, and Control*. John Wiley & Sons.\n- Zimmerman, R. D., Murillo-Sanchez, C. E., & Thomas, R. J. (2011). MATPOWER: Steady-State Operations, Planning, and Analysis Tools for Power Systems Research.",
    "dnr": "\n\n## References\n- Tinney, W. F., & Hart, C. E. (1967). Power flow solution by Newton's method. *IEEE Transactions on Power Apparatus and Systems*.\n- Zimmerman, R. D. et al. (2011). MATPOWER Documentation.",
    "helm": "\n\n## References\n- Triis, A. (2012). The Holomorphic Embedding Load Flow Method. *IEEE PES Innovative Smart Grid Technologies (ISGT)*.\n- Rao, S., et al. (2016). Holomorphic Embedding Method Applied to Power System Analysis.",
    "h-nr": "\n\n## References\n- Triis, A. (2012). The Holomorphic Embedding Load Flow Method. (Combining robust HELM initialization with fast Newton-Raphson convergence.)",
    "homotopy": "\n\n## References\n- Ajjarapu, V., & Christy, C. (1992). The continuation power flow: a tool for steady state voltage stability analysis. *IEEE Transactions on Power Systems*.",
    "cpf_pc": "\n\n## References\n- Ajjarapu, V., & Christy, C. (1992). The continuation power flow: a tool for steady state voltage stability analysis. *IEEE Transactions on Power Systems*.\n- Milano, F. (2010). *Power System Modelling and Scripting*. Springer."
}

refs_th = {
    "newton-raphson": "\n\n## เอกสารอ้างอิง (References)\n- Saadat, H. (1999). *Power System Analysis*. WCB/McGraw-Hill. (บทที่ 6: Power Flow Analysis)\n- Tinney, W. F., & Hart, C. E. (1967). Power flow solution by Newton's method. *IEEE Transactions on Power Apparatus and Systems*.",
    "gauss-seidel": "\n\n## เอกสารอ้างอิง (References)\n- Saadat, H. (1999). *Power System Analysis*. WCB/McGraw-Hill. (บทที่ 6: Power Flow Analysis)\n- Grainger, J. J., & Stevenson, W. D. (1994). *Power System Analysis*. McGraw-Hill.",
    "fast-decoupled": "\n\n## เอกสารอ้างอิง (References)\n- Stott, B., & Alsac, O. (1974). Fast Decoupled Load Flow. *IEEE Transactions on Power Apparatus and Systems*.\n- Saadat, H. (1999). *Power System Analysis*. WCB/McGraw-Hill. (บทที่ 6.5: Fast Decoupled Power Flow)",
    "dc-power-flow": "\n\n## เอกสารอ้างอิง (References)\n- Wood, A. J., Wollenberg, B. F., & Sheblé, G. B. (2013). *Power Generation, Operation, and Control*. John Wiley & Sons.\n- Zimmerman, R. D., Murillo-Sanchez, C. E., & Thomas, R. J. (2011). MATPOWER: Steady-State Operations, Planning, and Analysis Tools.",
    "dnr": "\n\n## เอกสารอ้างอิง (References)\n- Tinney, W. F., & Hart, C. E. (1967). Power flow solution by Newton's method. *IEEE Transactions on Power Apparatus and Systems*.\n- Zimmerman, R. D. et al. (2011). MATPOWER Documentation.",
    "helm": "\n\n## เอกสารอ้างอิง (References)\n- Triis, A. (2012). The Holomorphic Embedding Load Flow Method. *IEEE PES Innovative Smart Grid Technologies (ISGT)*.\n- Rao, S., et al. (2016). Holomorphic Embedding Method Applied to Power System Analysis.",
    "h-nr": "\n\n## เอกสารอ้างอิง (References)\n- Triis, A. (2012). The Holomorphic Embedding Load Flow Method.",
    "homotopy": "\n\n## เอกสารอ้างอิง (References)\n- Ajjarapu, V., & Christy, C. (1992). The continuation power flow: a tool for steady state voltage stability analysis. *IEEE Transactions on Power Systems*.",
    "cpf_pc": "\n\n## เอกสารอ้างอิง (References)\n- Ajjarapu, V., & Christy, C. (1992). The continuation power flow: a tool for steady state voltage stability analysis. *IEEE Transactions on Power Systems*.\n- Milano, F. (2010). *Power System Modelling and Scripting*. Springer."
}

# Apply missing references
methods = ["newton-raphson", "gauss-seidel", "fast-decoupled", "dc-power-flow", "dnr", "helm", "h-nr", "homotopy", "cpf_pc"]
for m in methods:
    en_path = os.path.join(content_dir, m, "en.md")
    th_path = os.path.join(content_dir, m, "th.md")
    
    # Read and append to EN
    if os.path.exists(en_path):
        with open(en_path, "r", encoding="utf-8") as f:
            en_content = f.read()
        if "## References" not in en_content:
            with open(en_path, "a", encoding="utf-8") as f:
                f.write(refs_en[m])
                
    # Read and append to TH
    if os.path.exists(th_path):
        with open(th_path, "r", encoding="utf-8") as f:
            th_content = f.read()
        if "## เอกสารอ้างอิง" not in th_content:
            with open(th_path, "a", encoding="utf-8") as f:
                f.write(refs_th[m])

print("Appended references successfully.")
