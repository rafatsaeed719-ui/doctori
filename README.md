# دكتوري — Doctori

منصة متابعة علاجية تربط المرضى بأطبائهم. المرحلة الحالية: **المرحلة الأولى** — قاعدة البيانات وصلاحياتها (مختبرة: 74 اختبار) + تطبيق أندرويد (Flutter).

## محتوى المجلد

| الملف | الوظيفة |
| --- | --- |
| `supabase/migrations/0001_phase1_core.sql` | الجداول، الصلاحيات (RLS)، دوال الربط والتوثيق والبحث، وبيانات التخصصات والمحافظات |
| `supabase/migrations/0002_phase1_app_api.sql` | دوال القوائم الجاهزة لشاشات المريض والطبيب والمدير |
| `supabase/migrations/0003_phase1_storage.sql` | مساحة تخزين خاصة لمستندات توثيق الأطباء |
| `supabase/tests/*.sql` | 74 اختبار للصلاحيات وسير العمل + محاكاة محلية لـ Supabase (للاختبار فقط) |
| `app/` | تطبيق Flutter (مريض + طبيب + أدوات المدير) |
| `.github/workflows/build-apk.yml` | يبني ملف APK تلقائياً على GitHub مع كل تحديث |

## إعداد Supabase (مرة واحدة)

1. **SQL Editor** ← New query: شغّل الملفات الثلاثة بالترتيب `0001` ثم `0002` ثم `0003` (انسخ كل ملف واضغط Run).
2. **Authentication ← URL Configuration ← Redirect URLs**: أضف `com.doctori.app://login-callback` (عشان رابط تأكيد الإيميل وتغيير كلمة السر يفتح التطبيق).
3. **Authentication ← Sign In / Providers ← Email**: خلي Email مفعّل و«Confirm email» مفعّل.
4. سجّل حسابك أنت من التطبيق بإيميلك.
5. اجعل حسابك مديراً بتشغيل هذا السطر مرة واحدة في SQL Editor (بعد استبدال الإيميل):

```sql
update public.profiles set role = 'admin' where email = 'YOUR_EMAIL@gmail.com';
```

لا توجد طريقة لأي مستخدم أن يجعل نفسه مديراً من التطبيق؛ هذا السطر هو الطريق الوحيد.

## ما الذي تضمنه القاعدة

- التسجيل ينشئ تلقائياً ملف مريض أو طبيب حسب الاختيار (لا يمكن التسجيل كمدير).
- الطبيب لا يظهر في البحث ولا يستقبل طلبات قبل توثيقه من المدير.
- الطبيب لا يرى أي بيانات لمريض إلا بعد قبول طلب الانضمام، وفي حدود موافقة المريض.
- فك الارتباط يلغي الموافقة فوراً.
- تغيير رقم الترخيص بعد التوثيق يعيد الطبيب للمراجعة.
- كل عمليات القبول والرفض والتوثيق والتعليق وتغيير الموافقات تُسجَّل في سجل تدقيق لا يمكن تعديله أو حذفه.
- حدود ضد الإساءة: 10 طلبات معلقة كحد أقصى، و20 طلباً في اليوم.

## الدوال المتاحة للتطبيق

| الدالة | من يستخدمها |
| --- | --- |
| `search_doctors(...)` | المريض: بحث بالاسم/التخصص/المحافظة/المدينة/القرب/التقييم/يوم العمل |
| `get_doctor_public(doctor_id)` | المريض: بطاقة الطبيب وعياداته ومواعيدها |
| `request_join(doctor_id, clinic_id, message, scope)` | المريض |
| `cancel_join_request(request_id)` | المريض |
| `respond_join(request_id, accept, reason)` | الطبيب |
| `set_consent_scope(link_id, scope)` | المريض |
| `end_care_link(link_id)` | المريض أو الطبيب |
| `admin_review_doctor(doctor_id, decision, notes)` | المدير |
| `admin_set_suspended(user_id, suspended, reason)` | المدير |
| `doctor_access_scope(patient_id)` | تُستخدم في صلاحيات المرحلة الثانية (الملف الطبي) |

## تشغيل الاختبارات محلياً

```bash
createdb doctori_test
psql -d doctori_test -v ON_ERROR_STOP=1 \
  -f supabase/tests/00_local_supabase_shim.sql \
  -f supabase/migrations/0001_phase1_core.sql \
  -f supabase/migrations/0002_phase1_app_api.sql \
  -f supabase/tests/phase1_security_test.sql \
  -f supabase/tests/phase1_app_api_test.sql
```

النتيجة المتوقعة: `tests_passed = 55` و`app_api_tests_passed = 19`. أي قاعدة صلاحيات تنكسر توقف التشغيل وتطبع اسم الاختبار الفاشل.

## بناء ملف APK

1. انسخ `app/env/doctori.example.json` إلى `app/env/doctori.json` وضع فيه رابط المشروع والمفتاح العام (Publishable / anon). **لا تضع أبداً مفتاح service_role.**
2. أي تحديث على فرع `main` يشغّل البناء تلقائياً على GitHub (تبويب Actions).
3. الملف الجاهز يظهر في **Releases** باسم «دكتوري — نسخة N»، تنزّله من الموبايل وتثبّته.

الخريطة تستخدم OpenStreetMap مجاناً. قبل الإطلاق العام بأعداد كبيرة، يتم التحويل لمزوّد خرائط تجاري حسب سياسة الاستخدام.

## تنبيه

البيانات الصحية بيانات حساسة وفق القانون 151 لسنة 2020 ولائحته التنفيذية. لا تُستقبل بيانات مرضى حقيقية قبل المراجعة القانونية (راجع مستند التحليل).
