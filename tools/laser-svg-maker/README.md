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

الأداة تعمل بالكامل داخل المتصفح. يتم تحميل Pyodide ثم تحميل ملفات SandSkrit من نسخة upstream مثبتة على commit محدد.

## ما تدعمه النسخة الأولى

- نصوص الحروف اللاتينية/الأرقام/الرموز التي يدعمها SandSkrit.
- Spiral.
- Circle.
- تبسيط عدد النقاط قبل التصدير.
- اختيار لون SVG.
- تصدير ملف SVG.

## غير داخل النطاق حاليًا

- لا يوجد ربط بـ `index.html`.
- لا يتم تعديل `laser.html`.
- لا يتم تعديل ملفات `assets/laser/*.ild`.
- لا يوجد تحويل SVG → ILD في هذه المرحلة.
- العربية تحتاج مسارات custom single-line خاصة بها؛ لن نحولها إلى font outlines مملوءة.

## المصدر

SandSkrit by UnintelligibleMaker, MIT License.

Pinned upstream commit:
`c770ac5a51c1b196f58f4e82d9c2859be9359f2a`
