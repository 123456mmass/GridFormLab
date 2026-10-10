"""นำเข้าข้อมูล TAMU แบบไม่แก้ต้นฉบับ และไม่ทับไฟล์ที่มีอยู่แล้ว."""
from pathlib import Path
import csv
import hashlib
import re

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path('C:/Users/User/Downloads/New England IEEE 39-Bus System')


def fields(line):
    return next(csv.reader([line.split('/')[0]], quotechar="'", skipinitialspace=True))


def numbers(line):
    return [float(x.strip()) for x in fields(line)]


def matrix(name, rows):
    return name + ' = [\n' + ''.join('    ' + ' '.join(format(x, '.17g') for x in row) + ';\n' for row in rows) + '];\n'


def create(path, text):
    with path.open('x', encoding='utf-8', newline='\n') as f:
        f.write(text)


raw_path = SOURCE / 'PSSE/IEEE 39 bus.RAW'
lines = raw_path.read_text().splitlines()
base = float(fields(lines[0])[1])
sections = {}
section = 'BUS'
for line in lines[3:]:
    if line.strip().startswith('0 /'):
        match = re.search(r'BEGIN (.*?) DATA', line)
        section = match.group(1) if match else 'END'
        continue
    if line.strip() and line.strip() != 'Q':
        sections.setdefault(section, []).append(line)

bus = []
for line in sections['BUS']:
    a = fields(line)
    bus.append([float(a[0]), float(a[3]), 0, 0, 0, 0, float(a[4]),
                float(a[7]), float(a[8]), float(a[2]), float(a[5]), float(a[9]), float(a[10])])
for line in sections['LOAD']:
    a = fields(line)
    if int(a[2]) != 1:
        continue
    assert all(float(a[k]) == 0 for k in range(7, 11)), 'รองรับเฉพาะโหลด constant-PQ ของชุดนี้'
    b = bus[int(a[0]) - 1]
    b[2] += float(a[5]); b[3] += float(a[6])
shunts = [numbers(line.replace("' 1'", '1')) for line in sections['FIXED SHUNT']]
for a in shunts:
    if a[2] == 1:
        bus[int(a[0]) - 1][4] += a[3]
        bus[int(a[0]) - 1][5] += a[4]
gen = []
source_impedance = []
for line in sections['GENERATOR']:
    a = fields(line)
    row = [0.0] * 21
    row[:10] = [float(a[k]) for k in [0, 2, 3, 4, 5, 6, 8, 14, 16, 17]]
    gen.append(row)
    source_impedance.append([float(a[0]), float(a[9]), float(a[10])])
branch = []
for line in sections['BRANCH']:
    a = fields(line)
    assert all(float(a[k]) == 0 for k in range(9, 13))
    branch.append([float(a[k]) for k in [0, 1, 3, 4, 5, 6, 7, 8]] + [0, 0, float(a[13]), -360, 360])
transformers = sections['TRANSFORMER']
assert len(transformers) % 4 == 0
for k in range(0, len(transformers), 4):
    a = fields(transformers[k]); z = numbers(transformers[k+1])
    w1 = numbers(transformers[k+2]); w2 = numbers(transformers[k+3])
    assert int(a[2]) == 0 and [int(a[j]) for j in [4, 5, 6]] == [1, 1, 1]
    assert float(a[7]) == 0 and float(a[8]) == 0
    branch.append([float(a[0]), float(a[1]), z[0], z[1], 0,
                   w1[3], w1[4], w1[5], w1[0]/w2[0], w1[2], float(a[11]), -360, 360])
assert len(bus) == 39 and len(gen) == 10 and len(branch) == 46

files = ['PSSE/IEEE 39 bus.RAW', 'PSSE/IEEE 39 bus.dyr', 'PSLF/IEEE 39 bus.EPC', 'PSLF/IEEE 39 bus.dyd']
hashes = {f: hashlib.sha256((SOURCE/f).read_bytes()).hexdigest() for f in files}
provenance = "raw.source_file = 'TAMU local distribution, PSSE/IEEE 39 bus.RAW';\n"
provenance += "raw.source_sha256 = '" + hashes[files[0]] + "';\n"
provenance += "raw.source_url = 'https://electricgrids.engr.tamu.edu/electric-grid-test-cases/new-england-ieee-39-bus-system/';\n"
provenance += "raw.source_citation = 'Athay, Podmore and Virmani (1979); Pai (1989); TAMU/Ledesma distribution';\n"
provenance += "raw.source_files = struct('path', {" + ','.join("'"+f+"'" for f in files) + "}, 'sha256', {" + ','.join("'"+hashes[f]+"'" for f in files) + "});\n"
text = "function raw = ne39_tamu_raw()\n%NE39_TAMU_RAW ข้อมูล RAW ของ TAMU เก็บเป็น literals ไม่อ่าน Downloads ตอนรัน.\n% ค่า MBASE เป็นฐานแบบจำลอง ไม่ใช่หลักฐาน nameplate capacity.\n% PT=9999.9 และ RATEA/B=0 เป็นค่าที่ไม่ระบุ physical limit.\nraw = struct();\n" + provenance
text += f'raw.baseMVA = {base:g};\nraw.frequency_Hz = 60;\n'
text += matrix('raw.bus', bus) + matrix('raw.gen', gen) + matrix('raw.branch', branch)
text += matrix('raw.fixed_shunts', shunts) + matrix('raw.generator_source_impedance', source_impedance)
text += "raw.gencost = []; % ต้นทางไม่ระบุต้นทุน\nraw.gen_dynamic_status = 'GENROU_IEEEST_IN_DYR_EXST1_IN_DYD';\nraw.active_limit_status = 'UNSPECIFIED_SOURCE_SENTINEL';\nraw.branch_rating_status = 'UNSPECIFIED_SOURCE_DEFAULT';\nraw.basekv_status = 'SOURCE_NORMALIZED_1_KV_NOT_PHYSICAL_VOLTAGE';\nend\n"
create(ROOT / '+cases/ne39_tamu_raw.m', text)

records = []
for rec in (SOURCE/files[1]).read_text().split('/'):
    tokens = rec.split()
    if not tokens:
        continue
    b = int(tokens[0]); model = tokens[1].strip("'")
    records.append((b, model, tokens[2], [float(x) for x in tokens[3:]]))
genrou = [r for r in records if r[1] == 'GENROU']
pss = [r for r in records if r[1] == 'IEEEST']
assert len(genrou) == len(pss) == 10 and all(len(r[3]) == 14 for r in genrou)
assert all(len(r[3]) == 19 for r in pss)
exciter = []
for line in (SOURCE/files[3]).read_text().splitlines():
    if line.startswith('exst1 '):
        exciter.append([float(line.split()[1])] + [float(x) for x in line.split('#9')[1].split()])
text = "function p = ne39_tamu_machine_parameters()\n%NE39_TAMU_MACHINE_PARAMETERS ค่าต้นทาง GENROU และ reduction ที่ประกาศชัด.\n% H_sys=H_machine*MBASE/Sbase; X_sys=X_machine*Sbase/MBASE.\n% reduction classical ตรึง internal EMF และละ flux/damper/AVR/PSS dynamics;\n% ไม่ใช่การจำลอง GENROU เต็ม และไม่รับรอง fault-current waveform.\nraw = cases.ne39_tamu_raw();\np.source = raw.source_citation;\np.source_files = raw.source_files;\np.classification = 'PROJECT_DERIVED_CLASSICAL_REDUCTION_OF_SOURCE_GENROU';\n"
text += "p.genrou_fields = {'Tdo_prime','Tdo_doubleprime','Tqo_prime','Tqo_doubleprime','H','D','Xd','Xq','Xdp','Xqp','Xdpp','Xl','S1','S12'};\n"
text += matrix('p.genrou', [[r[0]] + r[3] for r in genrou])
text += matrix('p.ieeest_psse_raw', [[r[0]] + r[3] for r in pss])
text += matrix('p.exst1_pslf_raw', exciter)
text += "p.control_mapping_status = 'RAW_PARAMETERS_PRESERVED_NOT_IMPLEMENTED_IN_CLASSICAL';\np.H_base = 'MACHINE_MVA';\np.X_base = 'MACHINE_MVA';\np.system_base_MVA = raw.baseMVA;\np.unit = struct('gen_id', {}, 'bus', {}, 'H', {}, 'D', {}, 'Xdp', {}, 'Mbase', {}, 'H_system', {}, 'D_system', {}, 'Xdp_system', {}, 'source_type', {});\nfor k = 1:size(p.genrou,1)\n    b = p.genrou(k,1);\n    j = find(raw.gen(:,1)==b,1);\n    M = raw.gen(j,7);\n    p.unit(k) = struct('gen_id',sprintf('G%d',b), 'bus',b, ...\n        'H',p.genrou(k,6), 'D',p.genrou(k,7), 'Xdp',p.genrou(k,10), ...\n        'Mbase',M, 'H_system',p.genrou(k,6)*M/raw.baseMVA, ...\n        'D_system',p.genrou(k,7)*M/raw.baseMVA, ...\n        'Xdp_system',p.genrou(k,10)*raw.baseMVA/M, ...\n        'source_type','TAMU_GENROU_CLASSICAL_REDUCTION');\nend\np.reduction = struct('classification','PROJECT_DERIVED', ...\n    'model','classical_constant_emf_behind_Xdp', ...\n    'omitted_dynamics',{{'field_flux','q_axis_flux','subtransient_dampers','EXST1','IEEEST','governor'}}, ...\n    'source_equivalent',false);\nend\n"
create(ROOT / '+cases/ne39_tamu_machine_parameters.m', text)
for f, h in hashes.items():
    print(f, h)
print('Imported:', len(bus), 'buses,', len(gen), 'machines,', len(branch), 'branches')
