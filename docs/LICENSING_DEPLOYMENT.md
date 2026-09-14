# إعداد وتشغيل الترخيص

لا يُوزع بناء الترخيص قبل إدخال الإعدادات العامة. البناء غير المعد يعمل بأمان مع وظائف الأداة متوقفة.

## 1. Supabase
أنشئ مشروعًا جديدًا. شغل `backend/schema.sql` مرة واحدة في SQL Editor. استخدم مشروعًا تجريبيًا أولًا. احفظ Project URL وservice_role API key أو مفتاح متوافق مع REST service_role في إعدادات السيرفر فقط. لا تضع أي مفتاح إدارة في الديلوب أو الواجهة أو GitHub repository variables العامة.

## 2. مفاتيح التوقيع
على جهاز موثوق شغل:
```
node backend/scripts/generate-keys.mjs /PRIVATE/DIRECTORY/OUTSIDE/REPOSITORY
```
السكربت لا يكتب فوق مفاتيح موجودة. احفظ lease-private-key.txt وserver-secrets.txt في مدير أسرار. lease-public-key.txt فقط هو المفتاح العام المطلوب لبناء الديلوب. احتفظ بالـpepper ثابتًا؛ تغييره يبطل مطابقة الأكواد الموجودة. تغيير مفتاح توقيع السيرفر يحتاج إصدار ديلوب بمفتاحه العام الجديد.

## 3. Vercel (خيار الاستضافة)
اربط مستودع AZ-GPS-PRO وفرع `licensing/system`. Root Directory: `backend`. Framework Preset: Other. يستخدم vercel.json الموجود بناء الأصول الثابتة وNode Function للـAPI. اضبط المتغيرات التالية لبيئة Production وPreview التجريبية:
- SUPABASE_URL
- SUPABASE_SERVICE_ROLE_KEY
- LICENSE_KEY_PEPPER
- LEASE_PRIVATE_KEY_PKCS8_B64 (محتوى الملف الخاص)
- ADMIN_TOKEN (القيمة المولدة)
- LEASE_SECONDS=120

انشر ثم افتح رابط المشروع، وأدخل ADMIN_TOKEN في لوحة الإدارة. رابط API المستخدم في المكتبة هو نفس HTTPS origin وينتهي `/`. اضبط حماية لوحة الإدارة وrate limiting قبل إصدار أكواد تجارية. اجعل API الخاص بالديلوب قابلًا للوصول دون بوابة دخول Vercel للمستخدم؛ الإدارة تعتمد المصادقة الخاصة بها. لا تعرض secrets في screenshots أو السجلات.

## 4. Cloudflare Workers (بديل)
من `backend` شغل `npx wrangler login`. أدخل كل سر من القائمة باستخدام `npx wrangler secret put NAME`. ثم `npx wrangler deploy`. wrangler.toml يربط نفس ملفات لوحة الإدارة والـAPI. لا تحتاج تشغيل Vercel وCloudflare معًا.

## 5. إعداد بناء iOS
في Settings → Secrets and variables → Actions → Variables لمستودع AZ-GPS-PRO:
- AZ_LICENSE_API_URL: مثل `https://YOUR_PROJECT.vercel.app/`
- AZ_LICENSE_PUBLIC_KEY_B64: محتوى lease-public-key.txt، وليس المفتاح الخاص.

شغل Build AZ.GPS.PRO على فرع licensing/system. حمّل AZ.GPS.PRO-arm64-ios12 وفك الضغط ثم أدرج الديلوب وأعد توقيع التطبيق. Keychain يحتاج توقيعًا وصلاحيات صحيحة للتطبيق المضيف.

للبناء macOS محليًا اضبط متغيري البيئة العامين ثم `make test` و`make`.

## 6. فحص الربط
أنشئ كودًا تجريبيًا، تحقق أن تاريخي التفعيل والانتهاء فارغان، وفعله داخل تطبيق اختباري. افحص أن أول تفعيل بدأ المدة. أعد فتح التطبيق: لا GPS UI قبل اختصار الصوت. جرب تطبيقًا ثانيًا بكود نفسه ويجب رفضه. اختبر التمديد والإيقاف والإلغاء وتعطل السيرفر على التطبيق المضيف قبل دمج الفرع مع main.
