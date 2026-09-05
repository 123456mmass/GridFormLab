"""Fix the three prose spots the f_Bus9 panel (d) left stale.

Runs on the renamed v3 -- docs/source/Forming Framework for
Inverter-Based Resources.docx -- in place, touching only the runs named here.
The owner's layout is not rebuilt; nothing else moves.

    python tmp/docx/fix_bus9_prose.py            # writes in place
    python tmp/docx/fix_bus9_prose.py --dry      # report only, write nothing

WHAT IT CHANGES (body indices verified on the renamed file, 330 children)

  b247  The paragraph under equation 56. It still says panel (d) is the
        converter-measured frequency, that the locked-GFL trace is empty
        because the policy has no such quantity, and that nothing is
        substituted to keep the line continuous. All three claims are false
        since panel (d) became f_Bus9: both arms derive it from their own bus-9
        voltage angle, and the grey trace is broken, not absent. Rewritten to
        say that, with the measured reason (20 ms output grid, |dtheta| >= pi/2
        steps undrawn) instead of the old absence story.
  b249  The figure-8 caption. '(d) ... f_conv' -> '(d) ... f_Bus9': one text
        run and one subscript run, same sizes as before.
  b253  The closing paragraph. It still says the two policies' frequency bands
        cannot be compared and limits the figure's claim to V/P plus the sync
        gate. Rewritten with the measured island bands -- adaptive 59.27-63.62
        Hz, locked GFL 47.58-72.50 Hz -- so the claim covers f_9 as well.

ENCODING

  Text runs are rebuilt with docx_build.run at the same sz the paragraph
  already uses (32). Inline math is compiled with oxml_math.inline. Two
  paragraphs in this file carry inline oMath with NO w:sz at all (b247's
  runs); b253's numbers carry sz 22. The script matches each: b247 math is
  used as compiled, b253 math gets w:sz/w:szCs 22 injected into every m:r
  (never into ctrlPr, which the delivered file leaves sz-free).
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import docx                      # noqa: E402
import docx_build as B           # noqa: E402
import oxml_math as om           # noqa: E402

W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
M = '{http://schemas.openxmlformats.org/officeDocument/2006/math}'
DST = ('docs/source/Forming Framework for Inverter-Based Resources.docx')

DRY = '--dry' in sys.argv
_log = []


def note(fmt, *a):
    _log.append(fmt % a if a else fmt)


# The run-level font tag the compiler emits for a plain math run. Prefixing
# with <m:r> keeps the replacement off the sSubPr ctrlPr, which the delivered
# file leaves sz-free.
_RUN_FONTS = ('<m:r><w:rPr><w:rFonts w:ascii="Cambria Math" '
              'w:hAnsi="Cambria Math"/></w:rPr>')


def inline_sz(src, sz):
    """Compile src and pin every math run to sz (half-points, as w:sz)."""
    xml = om.inline(src)
    if sz is None:
        return xml
    tag = ('<w:sz w:val="%d"/><w:szCs w:val="%d"/>' % (sz, sz))
    return xml.replace(
        _RUN_FONTS,
        _RUN_FONTS.replace('</w:rPr>', tag + '</w:rPr>'))


def rebuild_para(p, parts):
    """Replace a paragraph's runs/oMaths with built parts, keeping its pPr.

    parts is a list of (kind, value): kind 't' is a Thai text run at sz 32,
    kind 'm' is a compiled inline-math XML string. pPr (spacing, indent,
    justification) is untouched.
    """
    pPr = p.find(W + 'pPr')
    for ch in list(p):
        if ch is not pPr:
            p.remove(ch)
    xml = ''.join(B.run(v, sz=32) if k == 't' else v for k, v in parts)
    for el in B._els(xml):
        p.append(el)


def fix_b247(kids):
    """Panel-(d) explainer: converter frequency -> bus-9 frequency."""
    p = kids[247]
    w = ' '.join(t.text or '' for t in p.iter(W + 't'))
    if 'แผงที่ (d)' not in w or 'คอนเวอร์เตอร์วัดได้เอง' not in w:
        raise RuntimeError('b247 is not the panel-(d) paragraph')
    parts = [
        ('t', 'แผงที่ (d) เป็นความถี่ที่บัส 9 เอง '),
        ('m', inline_sz(
            r'f_9(t)=f_0+\frac{1}{2\pi}\frac{d\theta_9}{dt}', None)),
        ('t', (' จากมุมแรงดันของบัสนั้นซึ่งเป็นตัวแปรพีชคณิตที่รันแก้ได้ '
               'ไม่ใช่ความถี่เฉลี่ยถ่วงด้วยโมเมนต์ความเฉื่อย '
               'เพราะบัส 9 ไม่มีอุปกรณ์ต่ออยู่จึงไม่มีความถี่เป็น state '
               'ที่บัสนั้น '
               'การคิดจากมุมบัสเดียวกันทำให้แผงนี้เทียบกันได้บนปริมาณเดียวกันทั้งสองแขนง '
               'เส้นของแขนงตรึง GFL ขาดเป็นช่วง ไม่ใช่เพราะข้อมูลขาด '
               'แต่เพราะกริดขาออก 20 ms ของแขนงนั้นแยกไม่ออกว่าฟลีตขยับมุมบัสเร็วแค่ไหน '
               'ก้าวที่ ')),
        ('m', inline_sz(r'\abs{\Delta\theta}', None)),
        ('t', ' ถึง '),
        ('m', inline_sz(r'\pi/2', None)),
        ('t', (' จึงไม่วาด '
               'เพราะเกินกว่าที่ความชันซีแคนต์บนก้าวนั้นจะแสดงได้')),
    ]
    rebuild_para(p, parts)
    note('b247 rewritten for f_Bus9')


def fix_b249(kids):
    """Figure-8 caption: f_conv -> f_Bus9, same sizes."""
    p = kids[249]
    runs = [c for c in p if c.tag == W + 'r']
    if not runs or not (runs[0].find(W + 't') is not None
                        and 'รูปที่ 8' in (runs[0].find(W + 't').text or '')):
        raise RuntimeError('b249 is not the figure-8 caption')
    hit_t = hit_m = False
    for r in runs:
        t = r.find(W + 't')
        if t is not None and t.text and 'ความถี่ที่คอนเวอร์เตอร์วัดได้' in t.text:
            t.text = t.text.replace('ความถี่ที่คอนเวอร์เตอร์วัดได้',
                                    'ความถี่ที่บัส 9')
            hit_t = True
    for t in p.iter(M + 't'):
        if t.text == 'conv':
            t.text = 'Bus9'
            hit_m = True
    if not (hit_t and hit_m):
        raise RuntimeError('b249 caption runs not found (t=%s m=%s)'
                           % (hit_t, hit_m))
    note('b249 caption: f_conv -> f_Bus9')


def fix_b253(kids):
    """Closing paragraph: the bands ARE comparable now, with numbers."""
    p = kids[253]
    w = ' '.join(t.text or '' for t in p.iter(W + 't'))
    if 'เทียบแถบความถี่ของสองนโยบาย' not in w:
        raise RuntimeError('b253 is not the closing paragraph')
    parts = [
        ('t', 'ความถี่ที่บัส 9 ในช่วงเกาะของแขนงสลับโหมดอยู่ในแถบ '),
        ('m', inline_sz('59.27', 22)),
        ('t', '–'),
        ('m', inline_sz('63.62', 22)),
        ('t', ' Hz ส่วนแขนงตรึง GFL อยู่ในแถบ '),
        ('m', inline_sz('47.58', 22)),
        ('t', '–'),
        ('m', inline_sz('72.50', 22)),
        ('t', (' Hz ซึ่งกว้างกว่าหลายเท่า '
               'เทียบจากกราฟได้ตรงตัวว่าแขนงสลับโหมดยืนทั้งแรงดัน '
               'กำลัง และความถี่ที่โหลดบัสได้ดีกว่า '
               'สิ่งที่รูปนี้อ้างจึงครอบคลุมแรงดันและกำลังที่บัส 9 '
               'ความถี่ที่บัส 9 กับผลของเกตซิงโครนิซึม')),
    ]
    rebuild_para(p, parts)
    note('b253 rewritten with measured bands')


def main():
    if not os.path.exists(DST):
        sys.exit('missing: ' + DST)
    doc = docx.Document(DST)
    body = doc.element.body
    kids = list(body)
    if len(kids) != 330:
        sys.exit('expected 330 body children, found %d -- aborting'
                 % len(kids))

    fix_b247(kids)
    fix_b249(kids)
    fix_b253(kids)

    if not DRY:
        for ch in list(body):
            body.remove(ch)
        for ch in kids:
            body.append(ch)
        doc.save(DST)
        note('saved: %s', DST)
    for line in _log:
        print(line)


if __name__ == '__main__':
    main()
