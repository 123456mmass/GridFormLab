import svgwrite

def create_ieee14_visio_svg(filename="D:/Project/Power-flow/docs/source/figures/ieee14_dual_mode_ibr_diagram.svg"):
    # Canvas size: 1080 x 920 for generous margins and razor-sharp rendering
    dwg = svgwrite.Drawing(filename, size=("1080px", "920px"), viewBox="0 0 1080 920")

    # Font definitions
    dwg.defs.add(dwg.style("""
        @import url('https://fonts.googleapis.com/css2?family=Inter:ital,wght@0,400;0,600;0,700;1,600;1,700&display=swap');
        text { font-family: 'Inter', Arial, sans-serif; }
        .bus-num { font-size: 16px; font-weight: 700; fill: #000000; }
        .sg-text { font-size: 16px; font-weight: 700; font-style: italic; fill: #009646; }
        .sg-sub { font-size: 13px; font-weight: 400; font-style: normal; fill: #009646; }
        .ibr-text { font-size: 17px; font-weight: 700; font-style: italic; fill: #0066CC; }
        .ibr-sub { font-size: 13.5px; font-weight: 400; font-style: normal; fill: #0066CC; }
        .legend-title { font-size: 15px; font-weight: 700; }
        .storage-text { font-size: 11px; font-weight: 600; font-style: italic; fill: #000000; text-anchor: middle; }
    """))

    # Marker definitions (Arrowheads for loads)
    marker_load = dwg.marker(id='arrow-load', insert=(8, 4), size=(8, 8), orient='auto')
    marker_load.add(dwg.path(d='M 0 0 L 8 4 L 0 8 z', fill='#000000'))
    dwg.defs.add(marker_load)

    # Background
    dwg.add(dwg.rect(insert=(0, 0), size=(1080, 920), fill='#FFFFFF'))

    # =========================================================================
    # TOP LEGEND BOX
    # =========================================================================
    legend_g = dwg.g(id='legend-box')
    legend_g.add(dwg.rect(insert=(40, 35), size=(1000, 95), fill='#FFFFFF', stroke='#000000', stroke_width=1.6))

    # SG Legend
    legend_g.add(dwg.text("SG", insert=(105, 75), class_='sg-text', text_anchor='middle'))
    legend_g.add(dwg.text("(Slack)", insert=(105, 98), class_='sg-sub', text_anchor='middle'))
    legend_g.add(dwg.circle(center=(180, 82), r=25, fill='#FFE800', stroke='#000000', stroke_width=1.6))
    legend_g.add(dwg.text("~", insert=(173, 93), font_size='30px', font_weight='bold', fill='#000000'))

    # Load Legend
    legend_g.add(dwg.text("Load", insert=(270, 75), font_size='15px', font_weight='bold', font_style='italic', text_anchor='middle'))
    legend_g.add(dwg.text("(PQ)", insert=(270, 98), font_size='13px', text_anchor='middle'))
    legend_g.add(dwg.line(start=(320, 108), end=(320, 60), stroke='#000000', stroke_width=2.4, marker_end='url(#arrow-load)'))

    # IBR Legend
    legend_g.add(dwg.text("IBR (GFM: PV,", insert=(480, 75), class_='ibr-text', text_anchor='middle'))
    legend_g.add(dwg.text("GFL: PQ)", insert=(480, 98), class_='ibr-text', text_anchor='middle'))

    # Helper: Storage Box
    def draw_storage(g, center_x, center_y, width=126, height=48):
        x = center_x - width/2
        y = center_y - height/2
        g.add(dwg.rect(insert=(x, y), size=(width, height), fill='#E1F8E1', stroke='#329632', stroke_width=1.6, stroke_dasharray='6,3.5'))
        g.add(dwg.text("Energy Source", insert=(center_x, center_y - 2), class_='storage-text'))
        g.add(dwg.text("and/or Storge", insert=(center_x, center_y + 12), class_='storage-text'))

    # Helper: Converter Box (IGBT + Diode inside blue box)
    def draw_converter(g, center_x, center_y, size=52):
        x = center_x - size/2
        y = center_y - size/2
        g.add(dwg.rect(insert=(x, y), size=(size, size), fill='#CDE1FC', rx=3, ry=3, stroke='#78A5E6', stroke_width=1.4))
        # Diagonal line
        g.add(dwg.line(start=(x + 4, y + size - 4), end=(x + size - 4, y + 4), stroke='#000000', stroke_width=1.2))
        # Transistor (top-left)
        g.add(dwg.line(start=(center_x - 11, center_y - 14), end=(center_x - 11, center_y + 2), stroke='#000000', stroke_width=1.2))
        g.add(dwg.line(start=(center_x - 20, center_y - 6), end=(center_x - 11, center_y - 6), stroke='#000000', stroke_width=1.2))
        # Diode (bottom-right)
        g.add(dwg.line(start=(center_x + 5, center_y + 11), end=(center_x + 18, center_y + 11), stroke='#000000', stroke_width=1.2))
        g.add(dwg.polygon(points=[(center_x + 11, center_y + 5), (center_x + 11, center_y + 17), (center_x + 20, center_y + 11)], fill='#000000'))
        g.add(dwg.line(start=(center_x + 20, center_y + 5), end=(center_x + 20, center_y + 17), stroke='#000000', stroke_width=1.4))

    # Helper: Capacitor
    def draw_capacitor_h(g, cx, cy, span=28, gap=9):
        g.add(dwg.line(start=(cx - span/2, cy), end=(cx - gap/2, cy), stroke='#000000', stroke_width=1.3))
        g.add(dwg.line(start=(cx - gap/2, cy - 14), end=(cx - gap/2, cy + 14), stroke='#000000', stroke_width=2.0))
        g.add(dwg.line(start=(cx + gap/2, cy - 14), end=(cx + gap/2, cy + 14), stroke='#000000', stroke_width=2.0))
        g.add(dwg.line(start=(cx + gap/2, cy), end=(cx + span/2, cy), stroke='#000000', stroke_width=1.3))

    def draw_capacitor_v(g, cx, cy, span=28, gap=9):
        g.add(dwg.line(start=(cx, cy - span/2), end=(cx, cy - gap/2), stroke='#000000', stroke_width=1.3))
        g.add(dwg.line(start=(cx - 14, cy - gap/2), end=(cx + 14, cy - gap/2), stroke='#000000', stroke_width=2.0))
        g.add(dwg.line(start=(cx - 14, cy + gap/2), end=(cx + 14, cy + gap/2), stroke='#000000', stroke_width=2.0))
        g.add(dwg.line(start=(cx, cy + gap/2), end=(cx, cy + span/2), stroke='#000000', stroke_width=1.3))

    # Legend Storage + Cap + Converter
    draw_storage(legend_g, 720, 82)
    legend_g.add(dwg.line(start=(783, 82), end=(810, 82), stroke='#000000', stroke_width=1.3))
    draw_capacitor_h(legend_g, 825, 82)
    legend_g.add(dwg.line(start=(839, 82), end=(865, 82), stroke='#000000', stroke_width=1.3))
    draw_converter(legend_g, 892, 82)

    dwg.add(legend_g)

    # =========================================================================
    # COORDINATES MAPPING
    # =========================================================================
    def tx(x): return 140 + x * 80
    def ty(y): return 870 - y * 74

    bus_g = dwg.g(id='busbars')
    buses = [
        (1, -0.3, 2.5, 0.6, 2.5, -0.55, 2.5, "1"),
        (2, 1.7, 1.3, 4.0, 1.3, 1.45, 1.3, "2"),
        (3, 5.7, 1.3, 10.1, 1.3, 5.45, 1.3, "3"),
        (4, 5.0, 2.7, 7.5, 2.7, 4.75, 2.7, "4"),
        (5, 1.6, 3.7, 3.0, 3.7, 1.35, 3.7, "5"),
        (6, 1.7, 5.2, 4.3, 5.2, 4.55, 5.2, "6"),
        (7, 6.2, 5.0, 8.0, 5.0, 8.25, 5.0, "7"),
        (8, 8.4, 4.6, 8.4, 5.6, 8.4, 5.9, "8"),
        (9, 5.3, 6.1, 7.6, 6.1, 7.85, 6.1, "9"),
        (10, 6.0, 7.5, 7.2, 7.5, 5.75, 7.5, "10"),
        (11, 3.6, 7.5, 5.2, 7.5, 4.4, 7.85, "11"),
        (12, 0.2, 7.5, 1.9, 7.5, -0.05, 7.5, "12"),
        (13, 2.3, 8.5, 3.8, 8.5, 2.05, 8.5, "13"),
        (14, 5.2, 8.5, 7.3, 8.5, 4.95, 8.5, "14"),
    ]

    for b_id, x1, y1, x2, y2, lx, ly, lbl in buses:
        bus_g.add(dwg.line(start=(tx(x1), ty(y1)), end=(tx(x2), ty(y2)), stroke='#000000', stroke_width=4.5, stroke_linecap='square'))
        bus_g.add(dwg.text(lbl, insert=(tx(lx), ty(ly) + 6), class_='bus-num', text_anchor='middle'))

    dwg.add(bus_g)

    # Transmission Lines
    lines_g = dwg.g(id='transmission-lines')
    def draw_path(pts):
        mapped = [(tx(p[0]), ty(p[1])) for p in pts]
        lines_g.add(dwg.polyline(points=mapped, fill='none', stroke='#000000', stroke_width=1.6))

    draw_path([(0.0, 2.5), (0.0, 1.7), (1.7, 1.7), (1.7, 1.3)])
    draw_path([(0.4, 2.5), (0.4, 3.3), (1.6, 3.3), (1.6, 3.7)])
    draw_path([(4.0, 1.45), (5.7, 1.45)])
    draw_path([(2.8, 1.3), (2.8, 2.1), (6.1, 2.1), (6.1, 2.7)])
    draw_path([(2.4, 1.3), (2.4, 3.7)])
    draw_path([(6.9, 1.3), (6.9, 2.7)])
    draw_path([(5.3, 2.7), (5.3, 3.4), (2.6, 3.4), (2.6, 3.7)])
    draw_path([(3.2, 5.2), (3.2, 6.3), (4.7, 6.3), (4.7, 7.5)])
    draw_path([(1.8, 5.2), (1.8, 6.8), (1.0, 6.8), (1.0, 7.5)])
    draw_path([(3.0, 5.2), (3.0, 8.5)])
    draw_path([(5.1, 7.5), (5.1, 7.15), (6.1, 7.15), (6.1, 7.5)])
    draw_path([(6.5, 6.1), (6.5, 7.5)])
    draw_path([(7.0, 6.1), (7.0, 8.5)])
    draw_path([(1.6, 7.5), (1.6, 8.0), (2.4, 8.0), (2.4, 8.5)])
    draw_path([(3.8, 8.5), (5.2, 8.5)])

    dwg.add(lines_g)

    # Transformers
    tx_g = dwg.g(id='transformers')
    def draw_tx_v(x, y1, y2):
        mid_y = (y1 + y2) / 2
        tx_g.add(dwg.line(start=(tx(x), ty(y1)), end=(tx(x), ty(mid_y - 0.31)), stroke='#000000', stroke_width=1.6))
        tx_g.add(dwg.line(start=(tx(x), ty(mid_y + 0.31)), end=(tx(x), ty(y2)), stroke='#000000', stroke_width=1.6))
        tx_g.add(dwg.circle(center=(tx(x), ty(mid_y - 0.15)), r=14, fill='#FFFFFF', stroke='#000000', stroke_width=1.6))
        tx_g.add(dwg.circle(center=(tx(x), ty(mid_y + 0.15)), r=14, fill='#FFFFFF', stroke='#000000', stroke_width=1.6))

    def draw_tx_h(x1, x2, y):
        mid_x = (x1 + x2) / 2
        tx_g.add(dwg.line(start=(tx(x1), ty(y)), end=(tx(mid_x - 0.31), ty(y)), stroke='#000000', stroke_width=1.6))
        tx_g.add(dwg.line(start=(tx(mid_x + 0.31), ty(y)), end=(tx(x2), ty(y)), stroke='#000000', stroke_width=1.6))
        tx_g.add(dwg.circle(center=(tx(mid_x - 0.15), ty(y)), r=14, fill='#FFFFFF', stroke='#000000', stroke_width=1.6))
        tx_g.add(dwg.circle(center=(tx(mid_x + 0.15), ty(y)), r=14, fill='#FFFFFF', stroke='#000000', stroke_width=1.6))

    draw_tx_v(2.0, 3.7, 5.2)
    draw_tx_v(5.8, 2.7, 6.1)
    draw_tx_v(6.6, 5.0, 6.1)
    draw_tx_v(7.0, 2.7, 5.0)
    draw_path([(7.7, 5.0), (7.7, 5.1), (7.75, 5.1)])
    draw_tx_h(7.75, 8.4, 5.1)

    dwg.add(tx_g)

    # SG1 & IBRs
    sources_g = dwg.g(id='sources')

    # SG1
    sg_cx, sg_cy = tx(0.15), ty(3.3)
    sources_g.add(dwg.line(start=(tx(0.15), ty(2.5)), end=(sg_cx, sg_cy + 25), stroke='#000000', stroke_width=1.6))
    sources_g.add(dwg.circle(center=(sg_cx, sg_cy), r=25, fill='#FFE800', stroke='#000000', stroke_width=1.6))
    sources_g.add(dwg.text("~", insert=(sg_cx - 7, sg_cy + 10), font_size='30px', font_weight='bold', fill='#000000'))
    sources_g.add(dwg.text("SG₁", insert=(sg_cx + 36, sg_cy - 4), class_='sg-text'))
    sources_g.add(dwg.text("(Slack)", insert=(sg_cx + 36, sg_cy + 18), class_='sg-sub'))

    # IBR1
    ibr1_cx, ibr1_cy = tx(2.2), ty(0.5)
    sources_g.add(dwg.line(start=(tx(2.2), ty(1.3)), end=(ibr1_cx, ibr1_cy - 26), stroke='#000000', stroke_width=1.6))
    draw_converter(sources_g, ibr1_cx, ibr1_cy)
    sources_g.add(dwg.line(start=(ibr1_cx - 26, ibr1_cy), end=(ibr1_cx - 48, ibr1_cy), stroke='#000000', stroke_width=1.3))
    draw_capacitor_h(sources_g, tx(1.33), ibr1_cy)
    sources_g.add(dwg.line(start=(tx(1.33) - 17, ibr1_cy), end=(tx(-0.2) + 63, ibr1_cy), stroke='#000000', stroke_width=1.3))
    draw_storage(sources_g, tx(-0.2), ibr1_cy)
    sources_g.add(dwg.text("IBR₁", insert=(ibr1_cx + 36, ibr1_cy - 4), class_='ibr-text'))
    sources_g.add(dwg.text("(PQ)", insert=(ibr1_cx + 36, ibr1_cy + 18), class_='ibr-sub'))

    # IBR2
    ibr2_cx, ibr2_cy = tx(7.2), ty(0.5)
    sources_g.add(dwg.line(start=(tx(7.2), ty(1.3)), end=(ibr2_cx, ibr2_cy - 26), stroke='#000000', stroke_width=1.6))
    draw_converter(sources_g, ibr2_cx, ibr2_cy)
    sources_g.add(dwg.line(start=(ibr2_cx - 26, ibr2_cy), end=(ibr2_cx - 48, ibr2_cy), stroke='#000000', stroke_width=1.3))
    draw_capacitor_h(sources_g, tx(6.33), ibr2_cy)
    sources_g.add(dwg.line(start=(tx(6.33) - 17, ibr2_cy), end=(tx(4.8) + 63, ibr2_cy), stroke='#000000', stroke_width=1.3))
    draw_storage(sources_g, tx(4.8), ibr2_cy)
    sources_g.add(dwg.text("IBR₂", insert=(ibr2_cx + 36, ibr2_cy - 4), class_='ibr-text'))
    sources_g.add(dwg.text("(PQ)", insert=(ibr2_cx + 36, ibr2_cy + 18), class_='ibr-sub'))

    # IBR3
    ibr3_cx, ibr3_cy = tx(2.3), ty(6.1)
    sources_g.add(dwg.line(start=(tx(2.3), ty(5.2)), end=(ibr3_cx, ibr3_cy + 26), stroke='#000000', stroke_width=1.6))
    draw_converter(sources_g, ibr3_cx, ibr3_cy)
    sources_g.add(dwg.line(start=(ibr3_cx - 26, ibr3_cy), end=(ibr3_cx - 48, ibr3_cy), stroke='#000000', stroke_width=1.3))
    draw_capacitor_h(sources_g, tx(1.43), ibr3_cy)
    sources_g.add(dwg.line(start=(tx(1.43) - 17, ibr3_cy), end=(tx(-0.1) + 63, ibr3_cy), stroke='#000000', stroke_width=1.3))
    draw_storage(sources_g, tx(-0.1), ibr3_cy)
    sources_g.add(dwg.text("IBR₃", insert=(ibr3_cx, ibr3_cy - 42), class_='ibr-text', text_anchor='middle'))
    sources_g.add(dwg.text("(PQ)", insert=(ibr3_cx, ibr3_cy - 24), class_='ibr-sub', text_anchor='middle'))

    # IBR4
    ibr4_cx, ibr4_cy = tx(9.3), ty(5.1)
    sources_g.add(dwg.line(start=(tx(8.4), ty(5.1)), end=(ibr4_cx - 26, ibr4_cy), stroke='#000000', stroke_width=1.6))
    draw_converter(sources_g, ibr4_cx, ibr4_cy)
    sources_g.add(dwg.line(start=(ibr4_cx, ibr4_cy + 26), end=(ibr4_cx, ibr4_cy + 46), stroke='#000000', stroke_width=1.3))
    draw_capacitor_v(sources_g, ibr4_cx, ty(4.23))
    sources_g.add(dwg.line(start=(ibr4_cx, ty(4.23) + 17), end=(ibr4_cx, ty(3.3) - 24), stroke='#000000', stroke_width=1.3))
    draw_storage(sources_g, ibr4_cx, ty(3.3))
    sources_g.add(dwg.text("IBR₄", insert=(ibr4_cx, ibr4_cy - 42), class_='ibr-text', text_anchor='middle'))
    sources_g.add(dwg.text("(PQ)", insert=(ibr4_cx, ibr4_cy - 24), class_='ibr-sub', text_anchor='middle'))

    dwg.add(sources_g)

    # Loads
    loads_g = dwg.g(id='system-loads')
    def draw_load_arr(x, y_start, y_end):
        loads_g.add(dwg.line(start=(tx(x), ty(y_start)), end=(tx(x), ty(y_end)), stroke='#000000', stroke_width=2.4, marker_end='url(#arrow-load)'))

    draw_load_arr(3.4, 1.3, 0.55)
    draw_load_arr(8.6, 1.3, 0.55)
    draw_load_arr(9.6, 1.3, 0.55)
    draw_load_arr(7.0, 2.7, 1.95)
    draw_load_arr(2.1, 3.7, 2.95)
    draw_load_arr(3.7, 5.2, 4.45)
    draw_load_arr(5.8, 6.1, 6.85)
    draw_load_arr(6.6, 7.5, 6.75)
    draw_load_arr(4.0, 7.5, 6.75)
    draw_load_arr(0.4, 7.5, 6.75)
    draw_load_arr(2.9, 8.5, 7.75)
    draw_load_arr(6.8, 8.5, 7.75)

    dwg.add(loads_g)

    dwg.save()
    print(f"High-quality Visio-compatible SVG created: {filename}")

if __name__ == "__main__":
    create_ieee14_visio_svg()
