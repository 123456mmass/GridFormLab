import os
import re
import yaml

MATLAB_DIR = r"c:\Users\qwert\OneDrive\Desktop\api\n_bus_clone\+cases"
TARGET_DIR = r"c:\Users\qwert\OneDrive\Desktop\api\n_bus_py\backend\cases"

def extract_matrix(content, var_name):
    pattern = rf"{var_name}\s*=\s*\[(.*?)\];"
    match = re.search(pattern, content, re.DOTALL)
    if not match:
        return []
    
    matrix_str = match.group(1)
    lines = matrix_str.split(';')
    data = []
    for line in lines:
        # Remove comments
        line = line.split('%')[0].strip()
        if not line:
            continue
        # Split by whitespace
        parts = line.replace(',', ' ').split()
        if parts:
            try:
                row = [float(p) for p in parts]
                data.append(row)
            except ValueError:
                pass
    return data

def convert_all():
    os.makedirs(TARGET_DIR, exist_ok=True)
    
    for filename in os.listdir(MATLAB_DIR):
        if not filename.endswith(".m") or not filename.startswith("case_"):
            continue
            
        case_name = filename.replace("case_", "").replace(".m", "")
        # specifically if it's case_matpower_ieee30bus, rename to ieee30bus for our app
        if case_name == "matpower_ieee30bus":
            case_name = "ieee30bus"
            
        filepath = os.path.join(MATLAB_DIR, filename)
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
            
        bus_data = extract_matrix(content, r"case_data\.bus_data")
        line_data = extract_matrix(content, r"case_data\.line_data")
        
        if not bus_data or not line_data:
            continue
            
        # Format bus data
        final_bus_data = []
        for row in bus_data:
            # IEEE 14-bus has 10 columns: [BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload Gsh Bsh]
            # MATPOWER IEEE 30-bus has 12 columns: [BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload Gsh Bsh Qmin Qmax]
            
            # ensure it has 12 columns by padding
            if len(row) == 10:
                row.extend([-999.0, 999.0])
            elif len(row) > 12:
                row = row[:12]
                
            # Convert ints
            row[0] = int(row[0])
            row[1] = int(row[1])
            final_bus_data.append(row)
            
        final_line_data = []
        for row in line_data:
            row[0] = int(row[0])
            row[1] = int(row[1])
            final_line_data.append(row)
            
        yaml_data = {
            "system_name": f"{case_name.upper()} System",
            "base_values": {
                "S_base_MVA": 100.0,
                "V_base_kV": 135.0 if "30" in case_name else 230.0, # Guessing defaults
                "frequency_Hz": 60.0
            },
            "bus_data": final_bus_data,
            "line_data": final_line_data
        }
        
        target_path = os.path.join(TARGET_DIR, f"{case_name}.yaml")
        with open(target_path, "w", encoding="utf-8") as f:
            yaml.dump(yaml_data, f, default_flow_style=None, sort_keys=False)
            
        print(f"Converted {filename} to {case_name}.yaml ({len(bus_data)} buses, {len(line_data)} lines)")

if __name__ == "__main__":
    convert_all()
