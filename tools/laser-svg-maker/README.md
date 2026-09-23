# Laser SVG Maker

أداة داخلية مؤقتة لتجهيز مسارات SVG لتجربة الليزر في AR-Aboden.

## الهدف

- توليد مسارات vector متصلة باستخدام SandSkrit.
- معاينة المسار قبل تحويله إلى ILDA.
- تصدير SVG نظيف للاستخدام في مرحلة التحويل اللاحقة.
- عدم ربط الأداة بالصفحة الرئيسية أو بطاقات التجارب.

## التشغيل

بعد نشر GitHub Pages افتح المسار مباشرة:

`/AR-Aboden/tools/laser-svg-maker/`

الأداة تعمل بالكامل داخل المتصفح باستخدام JavaScript مباشر بدون Pyodide أو Python، لتكون أخف وأكثر ثباتًا على iPhone/Safari. تصميم المسارات أحادية الخط مستلهم من SandSkrit.

## ما تدعمه النسخة الأولى

- نصوص A–Z والأرقام 0–9 وبعض الرموز الأساسية بخط vector أحادي.
- Spiral.
- Circle.
- تبسيط عدد النقاط قبل التصدير.
- اختيار لون SVG.
- تصدير ملف SVG.

## غير داخل النطاق حاليًا

- لا يوجد ربط بـ `index.html`.
- لا يتم تعديل `laser.html`.
- لا يتم تعديل ملفات `assets/laser/*.ild`.
- لا يوجد تحويل SVG → ILD في هذه المرحلة؛ كل stroke يُصدر كـ SVG path مستقل تمهيدًا لإضافة blanking أثناء التحويل.
- العربية تحتاج مسارات custom single-line خاصة بها؛ لن نحولها إلى font outlines مملوءة.

## المصدر

SandSkrit by UnintelligibleMaker, MIT License.

SandSkrit remains the design reference and attribution source; the browser runtime no longer downloads or executes its Python code.
