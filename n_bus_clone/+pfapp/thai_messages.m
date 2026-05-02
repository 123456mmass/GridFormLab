function msg = thai_messages(key)
%THAI_MESSAGES Thai language error messages and UI strings.
%   msg = thai_messages(key) returns the Thai translation for key.
%   Falls back to English if key not found.

messages = containers.Map();
messages('ready')                = 'พร้อมทำงาน';
messages('running')              = 'กำลังคำนวณ...';
messages('converged')            = 'ลู่เข้า';
messages('not_converged')        = 'ไม่ลู่เข้า';
messages('iterations')           = 'จำนวนรอบ';
messages('export_done')          = 'ส่งออกเรียบร้อยแล้ว';
messages('export_failed')        = 'การส่งออกล้มเหลว';
messages('nothing_to_export')    = 'ยังไม่มีผลลัพธ์ให้ส่งออก กรุณารันก่อน';
messages('error_prefix')         = 'ข้อผิดพลาด';
messages('run_failed')           = 'การคำนวณล้มเหลว';
messages('plot_error')           = 'เกิดข้อผิดพลาดในการสร้างกราฟ';
messages('case_not_found')       = 'ไม่พบกรณีศึกษา';
messages('method_not_supported') = 'ไม่รองรับวิธีนี้';
messages('invalid_input')        = 'ข้อมูลนำเข้าไม่ถูกต้อง';
messages('q_limit_violation')    = 'ละเมิดขีดจำกัดกำลังรีแอกทีฟ';
messages('low_voltage')          = 'แรงดันไฟฟ้าต่ำ';
messages('high_losses')          = 'กำลังสูญเสียสูง';
messages('nose_detected')        = 'ตรวจพบจุดnose';
messages('voltage_collapse')     = 'ความเสี่ยงแรงดันไฟฟ้าล่มสลาย';
messages('optimal_dispatch')     = 'การจัดสรรเหมาะสมที่สุด';
messages('binding_limit')        = 'ขีดจำกัดที่มีผล';
messages('preferences_saved')    = 'บันทึกการตั้งค่าแล้ว';
messages('preferences_loaded')   = 'โหลดการตั้งค่าแล้ว';
messages('theme_changed')        = 'เปลี่ยนธีมแล้ว';
messages('report_generated')     = 'สร้างรายงานเรียบร้อยแล้ว';
messages('benchmark_complete')   = 'การเปรียบเทียบเสร็จสมบูรณ์';
messages('tests_passed')         = 'การทดสอบผ่านทั้งหมด';
messages('tests_failed')         = 'การทดสอบล้มเหลว';

if isKey(messages, key)
    msg = messages(key);
else
    msg = key;  % Fallback to English key
end
end
