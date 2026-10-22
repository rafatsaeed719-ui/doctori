import 'l10n.dart';

/// A bilingual option: stored by [key], shown in the user's language.
class Opt {
  const Opt(this.key, this.ar, this.en);
  final String key;
  final String ar;
  final String en;
  String get label => tr(ar, en);
}

/// A numeric measurement the doctor records (weight, height, blood pressure…).
class Measure {
  const Measure(this.key, this.ar, this.en, this.unit, {this.lowerIsBetter});
  final String key;
  final String ar;
  final String en;
  final String unit;

  /// For progress colours: true = going down is good (weight in a slimming plan, pain, sugar…).
  final bool? lowerIsBetter;
  String get label => tr(ar, en);
}

/// How the doctor marks where the problem is.
enum MapKind { body, teeth, chips, none }

/// The «الحالة» form for one specialty.
class CaseTemplate {
  const CaseTemplate({
    required this.key,
    required this.ar,
    required this.en,
    required this.problems,
    required this.goals,
    required this.measures,
    this.map = MapKind.body,
    this.regionChips = const [],
    this.weeks = 6,
    this.sessions = 12,
    this.sessionAr = 'جلسة',
    this.sessionEn = 'session',
  });
  final String key;
  final String ar;
  final String en;
  final List<Opt> problems;
  final List<Opt> goals;
  final List<Measure> measures;
  final MapKind map;
  final List<Opt> regionChips;
  final int weeks;
  final int sessions;
  final String sessionAr;
  final String sessionEn;
  String get title => tr(ar, en);
  String get sessionWord => tr(sessionAr, sessionEn);
}

// ---------------------------------------------------------------------------
// Shared measurements
// ---------------------------------------------------------------------------
const _weight = Measure('weight', 'الوزن', 'Weight', 'kg');
const _height = Measure('height', 'الطول', 'Height', 'cm');
const _waist = Measure('waist', 'محيط الوسط', 'Waist', 'cm', lowerIsBetter: true);
const _pain = Measure('pain', 'شدة الألم (0-10)', 'Pain (0-10)', '/10', lowerIsBetter: true);
const _sys = Measure('bp_sys', 'الضغط الانقباضي', 'Systolic BP', 'mmHg', lowerIsBetter: true);
const _dia = Measure('bp_dia', 'الضغط الانبساطي', 'Diastolic BP', 'mmHg', lowerIsBetter: true);
const _pulse = Measure('pulse', 'النبض', 'Pulse', '/min');
const _sugar = Measure('sugar_fasting', 'سكر صائم', 'Fasting sugar', 'mg/dL', lowerIsBetter: true);
const _hba1c = Measure('hba1c', 'السكر التراكمي', 'HbA1c', '%', lowerIsBetter: true);
const _chol = Measure('cholesterol', 'الكوليسترول', 'Cholesterol', 'mg/dL', lowerIsBetter: true);
const _temp = Measure('temp', 'الحرارة', 'Temperature', '°C');

// ---------------------------------------------------------------------------
// Templates
// ---------------------------------------------------------------------------
const physioTemplate = CaseTemplate(
  key: 'physio',
  ar: 'علاج طبيعي وتأهيل',
  en: 'Physiotherapy & rehab',
  problems: [
    Opt('low_back', 'آلام أسفل الظهر', 'Low back pain'),
    Opt('disc', 'انزلاق غضروفي', 'Disc herniation'),
    Opt('neck', 'آلام الرقبة', 'Neck pain'),
    Opt('knee_oa', 'خشونة الركبة', 'Knee osteoarthritis'),
    Opt('frozen_shoulder', 'تيبس الكتف', 'Frozen shoulder'),
    Opt('sports', 'إصابة ملاعب', 'Sports injury'),
    Opt('post_op', 'تأهيل بعد عملية', 'Post-surgery rehab'),
    Opt('stroke', 'جلطة / شلل نصفي', 'Stroke / hemiplegia'),
    Opt('sprain', 'التواء / شد عضلي', 'Sprain / strain'),
    Opt('posture', 'مشاكل القوام', 'Posture problems'),
    Opt('weight', 'سمنة / وزن', 'Weight problem'),
    Opt('weakness', 'ضعف عضلات', 'Muscle weakness'),
  ],
  goals: [
    Opt('lose_weight', 'تخسيس', 'Lose weight'),
    Opt('gain_weight', 'زيادة وزن', 'Gain weight'),
    Opt('pain_relief', 'تخفيف الألم', 'Pain relief'),
    Opt('mobility', 'استعادة الحركة', 'Restore movement'),
    Opt('strength', 'تقوية العضلات', 'Build strength'),
    Opt('return_sport', 'الرجوع للرياضة', 'Return to sport'),
    Opt('posture', 'تحسين القوام', 'Better posture'),
  ],
  measures: [_weight, _height, _waist, _pain],
  weeks: 6,
  sessions: 12,
);

const nutritionTemplate = CaseTemplate(
  key: 'nutrition',
  ar: 'تغذية علاجية',
  en: 'Clinical nutrition',
  problems: [
    Opt('obesity', 'سمنة', 'Obesity'),
    Opt('underweight', 'نحافة', 'Underweight'),
    Opt('diabetes', 'سكر', 'Diabetes'),
    Opt('hypertension', 'ضغط', 'Hypertension'),
    Opt('cholesterol', 'كوليسترول ودهون', 'High cholesterol'),
    Opt('pcos', 'تكيس مبايض', 'PCOS'),
    Opt('gout', 'نقرس', 'Gout'),
    Opt('anemia', 'أنيميا', 'Anemia'),
    Opt('pregnancy', 'تغذية حمل ورضاعة', 'Pregnancy nutrition'),
    Opt('athlete', 'تغذية رياضيين', 'Sports nutrition'),
  ],
  goals: [
    Opt('lose_weight', 'تخسيس', 'Lose weight'),
    Opt('gain_weight', 'زيادة وزن', 'Gain weight'),
    Opt('maintain', 'تثبيت الوزن', 'Maintain weight'),
    Opt('muscle', 'بناء عضل', 'Build muscle'),
    Opt('disease_diet', 'نظام مناسب للمرض', 'Disease-specific diet'),
  ],
  measures: [
    _weight,
    _height,
    Measure('target_weight', 'الوزن المستهدف', 'Target weight', 'kg'),
    _waist,
    Measure('hip', 'محيط الأرداف', 'Hips', 'cm'),
    Measure('body_fat', 'نسبة الدهون', 'Body fat', '%', lowerIsBetter: true),
  ],
  map: MapKind.none,
  weeks: 12,
  sessions: 12,
  sessionAr: 'متابعة',
  sessionEn: 'follow-up',
);

const orthoTemplate = CaseTemplate(
  key: 'ortho',
  ar: 'عظام',
  en: 'Orthopedics',
  problems: [
    Opt('fracture', 'كسر', 'Fracture'),
    Opt('oa', 'خشونة مفاصل', 'Osteoarthritis'),
    Opt('disc', 'غضروف', 'Disc problem'),
    Opt('acl', 'رباط صليبي', 'ACL injury'),
    Opt('meniscus', 'غضروف هلالي', 'Meniscus tear'),
    Opt('tendinitis', 'التهاب أوتار', 'Tendinitis'),
    Opt('osteoporosis', 'هشاشة عظام', 'Osteoporosis'),
    Opt('carpal', 'تنميل اليد (الرسغ)', 'Carpal tunnel'),
    Opt('deformity', 'تشوهات', 'Deformity'),
  ],
  goals: [
    Opt('healing', 'التئام الكسر', 'Fracture healing'),
    Opt('pain_relief', 'تخفيف الألم', 'Pain relief'),
    Opt('mobility', 'استعادة الحركة', 'Restore movement'),
    Opt('pre_op', 'تجهيز لعملية', 'Prepare for surgery'),
    Opt('post_op', 'متابعة بعد عملية', 'Post-surgery follow-up'),
  ],
  measures: [_weight, _height, _pain],
  weeks: 6,
  sessions: 6,
  sessionAr: 'متابعة',
  sessionEn: 'follow-up',
);

const dentalTemplate = CaseTemplate(
  key: 'dental',
  ar: 'أسنان',
  en: 'Dentistry',
  problems: [
    Opt('caries', 'تسوس', 'Caries'),
    Opt('root_canal', 'حشو عصب', 'Root canal'),
    Opt('extraction', 'خلع', 'Extraction'),
    Opt('wisdom', 'ضرس عقل', 'Wisdom tooth'),
    Opt('ortho', 'تقويم', 'Braces'),
    Opt('crown', 'تركيبات', 'Crowns / bridges'),
    Opt('implant', 'زراعة', 'Implant'),
    Opt('scaling', 'تنظيف جير', 'Scaling'),
    Opt('whitening', 'تبييض', 'Whitening'),
    Opt('gums', 'التهاب لثة', 'Gum disease'),
  ],
  goals: [
    Opt('pain_relief', 'علاج الألم', 'Relieve pain'),
    Opt('smile', 'تجميل الابتسامة', 'Cosmetic smile'),
    Opt('alignment', 'تقويم الأسنان', 'Straighten teeth'),
    Opt('chewing', 'استعادة المضغ', 'Restore chewing'),
    Opt('prevention', 'وقاية', 'Prevention'),
  ],
  measures: [_pain],
  map: MapKind.teeth,
  weeks: 4,
  sessions: 4,
);

const cardioTemplate = CaseTemplate(
  key: 'cardio',
  ar: 'قلب وأوعية دموية',
  en: 'Cardiology',
  problems: [
    Opt('htn', 'ضغط مرتفع', 'Hypertension'),
    Opt('cad', 'قصور الشريان التاجي', 'Coronary disease'),
    Opt('angina', 'ذبحة صدرية', 'Angina'),
    Opt('arrhythmia', 'عدم انتظام ضربات القلب', 'Arrhythmia'),
    Opt('hf', 'ضعف عضلة القلب', 'Heart failure'),
    Opt('valves', 'صمامات', 'Valve disease'),
    Opt('lipids', 'كوليسترول ودهون', 'High cholesterol'),
    Opt('post_cath', 'بعد قسطرة / دعامة', 'After stent'),
  ],
  goals: [
    Opt('bp_control', 'ضبط الضغط', 'Control BP'),
    Opt('lipids', 'ضبط الكوليسترول', 'Control cholesterol'),
    Opt('fitness', 'تحسين اللياقة', 'Improve fitness'),
    Opt('lose_weight', 'تخسيس', 'Lose weight'),
    Opt('prevent', 'منع المضاعفات', 'Prevent complications'),
  ],
  measures: [_sys, _dia, _pulse, _weight, _chol],
  map: MapKind.none,
  weeks: 12,
  sessions: 4,
  sessionAr: 'متابعة',
  sessionEn: 'follow-up',
);

const endoTemplate = CaseTemplate(
  key: 'endo',
  ar: 'سكر وغدد',
  en: 'Diabetes & endocrine',
  problems: [
    Opt('dm1', 'سكر نوع أول', 'Type 1 diabetes'),
    Opt('dm2', 'سكر نوع تاني', 'Type 2 diabetes'),
    Opt('gdm', 'سكر حمل', 'Gestational diabetes'),
    Opt('hypo', 'خمول الغدة الدرقية', 'Hypothyroidism'),
    Opt('hyper', 'نشاط الغدة الدرقية', 'Hyperthyroidism'),
    Opt('pcos', 'تكيس مبايض', 'PCOS'),
    Opt('obesity', 'سمنة', 'Obesity'),
  ],
  goals: [
    Opt('sugar_control', 'ضبط السكر', 'Control sugar'),
    Opt('thyroid', 'ضبط الغدة', 'Control thyroid'),
    Opt('lose_weight', 'تخسيس', 'Lose weight'),
    Opt('prevent', 'منع المضاعفات', 'Prevent complications'),
  ],
  measures: [_sugar, _hba1c, _weight, _height, Measure('tsh', 'هرمون الغدة TSH', 'TSH', 'mIU/L')],
  map: MapKind.none,
  weeks: 12,
  sessions: 4,
  sessionAr: 'متابعة',
  sessionEn: 'follow-up',
);

const dermaTemplate = CaseTemplate(
  key: 'derma',
  ar: 'جلدية وتجميل',
  en: 'Dermatology',
  problems: [
    Opt('acne', 'حب شباب', 'Acne'),
    Opt('eczema', 'إكزيما', 'Eczema'),
    Opt('psoriasis', 'صدفية', 'Psoriasis'),
    Opt('vitiligo', 'بهاق', 'Vitiligo'),
    Opt('hair_loss', 'تساقط شعر', 'Hair loss'),
    Opt('melasma', 'كلف ونمش', 'Melasma'),
    Opt('fungal', 'فطريات', 'Fungal infection'),
    Opt('warts', 'سنط / ثآليل', 'Warts'),
    Opt('allergy', 'حساسية جلد', 'Skin allergy'),
    Opt('scars', 'ندبات وآثار', 'Scars'),
  ],
  goals: [
    Opt('cure', 'علاج كامل', 'Full cure'),
    Opt('control', 'السيطرة على الأعراض', 'Control symptoms'),
    Opt('cosmetic', 'تحسين المظهر', 'Cosmetic improvement'),
    Opt('prevent', 'منع الانتكاس', 'Prevent relapse'),
  ],
  measures: [Measure('affected', 'المساحة المصابة', 'Affected area', '%', lowerIsBetter: true)],
  weeks: 8,
  sessions: 6,
);

const pedsTemplate = CaseTemplate(
  key: 'peds',
  ar: 'أطفال',
  en: 'Pediatrics',
  problems: [
    Opt('vaccines', 'تطعيمات', 'Vaccinations'),
    Opt('cold', 'نزلة برد / كحة', 'Cold / cough'),
    Opt('gastro', 'نزلة معوية', 'Gastroenteritis'),
    Opt('growth', 'تأخر نمو', 'Growth delay'),
    Opt('anemia', 'أنيميا', 'Anemia'),
    Opt('asthma', 'حساسية صدر', 'Asthma'),
    Opt('malnutrition', 'سوء تغذية', 'Malnutrition'),
    Opt('fever', 'سخونية متكررة', 'Recurrent fever'),
  ],
  goals: [
    Opt('growth', 'متابعة النمو', 'Monitor growth'),
    Opt('gain_weight', 'زيادة وزن', 'Gain weight'),
    Opt('cure', 'علاج', 'Treatment'),
    Opt('vaccines', 'استكمال التطعيمات', 'Complete vaccines'),
  ],
  measures: [_weight, _height, Measure('head', 'محيط الرأس', 'Head circumference', 'cm'), _temp],
  weeks: 4,
  sessions: 3,
  sessionAr: 'متابعة',
  sessionEn: 'follow-up',
);

const psychTemplate = CaseTemplate(
  key: 'psych',
  ar: 'نفسية',
  en: 'Psychiatry',
  problems: [
    Opt('anxiety', 'قلق', 'Anxiety'),
    Opt('depression', 'اكتئاب', 'Depression'),
    Opt('insomnia', 'أرق', 'Insomnia'),
    Opt('ocd', 'وسواس قهري', 'OCD'),
    Opt('stress', 'ضغط نفسي', 'Stress'),
    Opt('bipolar', 'اضطراب ثنائي القطب', 'Bipolar disorder'),
    Opt('panic', 'نوبات هلع', 'Panic attacks'),
    Opt('adhd', 'فرط حركة وتشتت', 'ADHD'),
  ],
  goals: [
    Opt('sleep', 'تحسين النوم', 'Better sleep'),
    Opt('anxiety', 'تقليل القلق', 'Less anxiety'),
    Opt('mood', 'تحسين المزاج', 'Better mood'),
    Opt('adherence', 'الالتزام بالعلاج', 'Treatment adherence'),
    Opt('function', 'الرجوع للحياة الطبيعية', 'Return to normal life'),
  ],
  measures: [
    Measure('mood', 'المزاج (0-10)', 'Mood (0-10)', '/10'),
    Measure('anxiety', 'القلق (0-10)', 'Anxiety (0-10)', '/10', lowerIsBetter: true),
    Measure('sleep_hours', 'ساعات النوم', 'Sleep hours', 'h'),
  ],
  map: MapKind.none,
  weeks: 8,
  sessions: 8,
);

const gynTemplate = CaseTemplate(
  key: 'gyn',
  ar: 'نساء وتوليد',
  en: 'Obstetrics & gynecology',
  problems: [
    Opt('pregnancy', 'متابعة حمل', 'Pregnancy follow-up'),
    Opt('pcos', 'تكيس مبايض', 'PCOS'),
    Opt('infertility', 'تأخر إنجاب', 'Infertility'),
    Opt('cycle', 'اضطراب الدورة', 'Irregular cycle'),
    Opt('infection', 'التهابات', 'Infections'),
    Opt('menopause', 'انقطاع الطمث', 'Menopause'),
    Opt('fibroids', 'ألياف رحمية', 'Fibroids'),
  ],
  goals: [
    Opt('safe_pregnancy', 'حمل وولادة آمنة', 'Safe pregnancy'),
    Opt('cycle', 'تنظيم الدورة', 'Regular cycle'),
    Opt('fertility', 'الإنجاب', 'Conceive'),
    Opt('cure', 'علاج', 'Treatment'),
  ],
  measures: [_weight, _sys, _dia, Measure('preg_week', 'أسبوع الحمل', 'Pregnancy week', 'wk')],
  map: MapKind.none,
  weeks: 36,
  sessions: 12,
  sessionAr: 'متابعة',
  sessionEn: 'follow-up',
);

const eyeTemplate = CaseTemplate(
  key: 'eye',
  ar: 'رمد وعيون',
  en: 'Ophthalmology',
  problems: [
    Opt('myopia', 'قصر نظر', 'Myopia'),
    Opt('hyperopia', 'طول نظر', 'Hyperopia'),
    Opt('astig', 'استجماتيزم', 'Astigmatism'),
    Opt('cataract', 'مياه بيضاء', 'Cataract'),
    Opt('glaucoma', 'مياه زرقاء', 'Glaucoma'),
    Opt('dry_eye', 'جفاف العين', 'Dry eye'),
    Opt('conjunctivitis', 'التهاب ملتحمة', 'Conjunctivitis'),
    Opt('retina', 'شبكية (سكر/ضغط)', 'Retinopathy'),
    Opt('lazy', 'كسل عين', 'Lazy eye'),
  ],
  goals: [
    Opt('vision', 'تحسين النظر', 'Better vision'),
    Opt('pre_op', 'تجهيز لعملية', 'Prepare for surgery'),
    Opt('pressure', 'ضبط ضغط العين', 'Control eye pressure'),
    Opt('cure', 'علاج الالتهاب', 'Treat inflammation'),
  ],
  measures: [
    Measure('iop_r', 'ضغط العين اليمنى', 'Right eye pressure', 'mmHg', lowerIsBetter: true),
    Measure('iop_l', 'ضغط العين اليسرى', 'Left eye pressure', 'mmHg', lowerIsBetter: true),
  ],
  map: MapKind.chips,
  regionChips: [
    Opt('eye_r', 'العين اليمنى', 'Right eye'),
    Opt('eye_l', 'العين اليسرى', 'Left eye'),
  ],
  weeks: 4,
  sessions: 3,
  sessionAr: 'متابعة',
  sessionEn: 'follow-up',
);

const entTemplate = CaseTemplate(
  key: 'ent',
  ar: 'أنف وأذن وحنجرة',
  en: 'ENT',
  problems: [
    Opt('tonsils', 'التهاب لوز', 'Tonsillitis'),
    Opt('sinusitis', 'جيوب أنفية', 'Sinusitis'),
    Opt('septum', 'انحراف الحاجز', 'Deviated septum'),
    Opt('otitis', 'التهاب أذن', 'Ear infection'),
    Opt('hearing', 'ضعف سمع', 'Hearing loss'),
    Opt('tinnitus', 'طنين', 'Tinnitus'),
    Opt('vertigo', 'دوخة / دوار', 'Vertigo'),
    Opt('snoring', 'شخير', 'Snoring'),
    Opt('adenoids', 'لحمية', 'Adenoids'),
  ],
  goals: [
    Opt('cure', 'علاج الالتهاب', 'Treat infection'),
    Opt('breathing', 'تحسين التنفس', 'Better breathing'),
    Opt('hearing', 'تحسين السمع', 'Better hearing'),
    Opt('pre_op', 'تجهيز لعملية', 'Prepare for surgery'),
  ],
  measures: [_temp],
  map: MapKind.chips,
  regionChips: [
    Opt('ear_r', 'الأذن اليمنى', 'Right ear'),
    Opt('ear_l', 'الأذن اليسرى', 'Left ear'),
    Opt('nose', 'الأنف', 'Nose'),
    Opt('sinuses', 'الجيوب الأنفية', 'Sinuses'),
    Opt('throat', 'الحلق', 'Throat'),
    Opt('tonsils', 'اللوزتين', 'Tonsils'),
    Opt('larynx', 'الحنجرة', 'Larynx'),
  ],
  weeks: 2,
  sessions: 2,
  sessionAr: 'متابعة',
  sessionEn: 'follow-up',
);

const neuroTemplate = CaseTemplate(
  key: 'neuro',
  ar: 'مخ وأعصاب',
  en: 'Neurology',
  problems: [
    Opt('migraine', 'صداع نصفي', 'Migraine'),
    Opt('stroke', 'جلطة', 'Stroke'),
    Opt('epilepsy', 'صرع', 'Epilepsy'),
    Opt('neuropathy', 'تنميل / اعتلال أعصاب', 'Neuropathy'),
    Opt('sciatica', 'عرق النسا', 'Sciatica'),
    Opt('bell', 'شلل الوجه', 'Bell’s palsy'),
    Opt('parkinson', 'باركنسون', 'Parkinson’s'),
  ],
  goals: [
    Opt('pain_relief', 'تخفيف الألم', 'Pain relief'),
    Opt('control', 'السيطرة على النوبات', 'Control attacks'),
    Opt('mobility', 'استعادة الحركة', 'Restore movement'),
  ],
  measures: [_pain, _sys, _dia],
  weeks: 8,
  sessions: 4,
  sessionAr: 'متابعة',
  sessionEn: 'follow-up',
);

const generalTemplate = CaseTemplate(
  key: 'general',
  ar: 'متابعة عامة',
  en: 'General follow-up',
  problems: [
    Opt('acute', 'حالة حادة', 'Acute illness'),
    Opt('chronic', 'مرض مزمن', 'Chronic disease'),
    Opt('checkup', 'كشف دوري', 'Check-up'),
    Opt('post_op', 'متابعة بعد عملية', 'Post-surgery'),
    Opt('infection', 'عدوى / التهاب', 'Infection'),
  ],
  goals: [
    Opt('cure', 'علاج كامل', 'Full cure'),
    Opt('control', 'تخفيف الأعراض', 'Control symptoms'),
    Opt('monitor', 'متابعة دورية', 'Regular monitoring'),
    Opt('lose_weight', 'تخسيس', 'Lose weight'),
  ],
  measures: [_weight, _height, _sys, _dia, _sugar],
  weeks: 4,
  sessions: 4,
  sessionAr: 'متابعة',
  sessionEn: 'follow-up',
);

const allTemplates = [
  physioTemplate, nutritionTemplate, orthoTemplate, dentalTemplate, cardioTemplate, endoTemplate, dermaTemplate,
  pedsTemplate, psychTemplate, gynTemplate, eyeTemplate, entTemplate, neuroTemplate, generalTemplate,
];

CaseTemplate templateByKey(String? key) =>
    allTemplates.firstWhere((t) => t.key == key, orElse: () => generalTemplate);

/// Picks the form by the doctor's English specialty name (same matching as the specialty backgrounds).
CaseTemplate templateForSpecialty(String? specialtyEn) {
  final s = (specialtyEn ?? '').toLowerCase();
  bool has(String k) => s.contains(k);
  if (has('physical') || has('physio') || has('rehab')) return physioTemplate;
  if (has('nutrition') || has('diet')) return nutritionTemplate;
  if (has('ortho') || has('bone')) return orthoTemplate;
  if (has('dent')) return dentalTemplate;
  if (has('cardio') || has('heart')) return cardioTemplate;
  if (has('endocr') || has('diabet')) return endoTemplate;
  if (has('dermat') || has('skin')) return dermaTemplate;
  if (has('pediatric') || has('child')) return pedsTemplate;
  if (has('psychiat') || has('mental')) return psychTemplate;
  if (has('gyn') || has('obstet')) return gynTemplate;
  if (has('ophthal') || has('eye')) return eyeTemplate;
  if (s == 'ent' || has('ear') || has('throat')) return entTemplate;
  if (has('neuro')) return neuroTemplate;
  return generalTemplate;
}

// ---------------------------------------------------------------------------
// Body regions (front + back). Coordinates are fractions of the figure box.
// The figure faces the viewer, so the patient's right side is on the viewer's left.
// ---------------------------------------------------------------------------
class BodyRegion {
  const BodyRegion(this.key, this.ar, this.en, this.x, this.y, {this.back = false, this.front = true});
  final String key;
  final String ar;
  final String en;
  final double x;
  final double y;
  final bool front;
  final bool back;
  String get label => tr(ar, en);
}

const bodyRegions = [
  BodyRegion('head', 'الرأس', 'Head', 0.5, 0.06, back: true),
  BodyRegion('neck', 'الرقبة', 'Neck', 0.5, 0.135, back: true),
  BodyRegion('r_shoulder', 'الكتف الأيمن', 'Right shoulder', 0.30, 0.18, back: true),
  BodyRegion('l_shoulder', 'الكتف الأيسر', 'Left shoulder', 0.70, 0.18, back: true),
  BodyRegion('chest', 'الصدر', 'Chest', 0.5, 0.24),
  BodyRegion('abdomen', 'البطن', 'Abdomen', 0.5, 0.36),
  BodyRegion('upper_back', 'أعلى الظهر', 'Upper back', 0.5, 0.24, front: false, back: true),
  BodyRegion('lower_back', 'أسفل الظهر', 'Lower back', 0.5, 0.38, front: false, back: true),
  BodyRegion('r_elbow', 'الكوع الأيمن', 'Right elbow', 0.22, 0.33, back: true),
  BodyRegion('l_elbow', 'الكوع الأيسر', 'Left elbow', 0.78, 0.33, back: true),
  BodyRegion('r_hand', 'اليد اليمنى', 'Right hand', 0.15, 0.48, back: true),
  BodyRegion('l_hand', 'اليد اليسرى', 'Left hand', 0.85, 0.48, back: true),
  BodyRegion('pelvis', 'الحوض', 'Pelvis', 0.5, 0.46, back: true),
  BodyRegion('r_hip', 'الفخذ الأيمن', 'Right thigh', 0.40, 0.56, back: true),
  BodyRegion('l_hip', 'الفخذ الأيسر', 'Left thigh', 0.60, 0.56, back: true),
  BodyRegion('r_knee', 'الركبة اليمنى', 'Right knee', 0.40, 0.68, back: true),
  BodyRegion('l_knee', 'الركبة اليسرى', 'Left knee', 0.60, 0.68, back: true),
  BodyRegion('r_leg', 'الساق اليمنى', 'Right leg', 0.40, 0.79, back: true),
  BodyRegion('l_leg', 'الساق اليسرى', 'Left leg', 0.60, 0.79, back: true),
  BodyRegion('r_foot', 'القدم اليمنى', 'Right foot', 0.39, 0.94, back: true),
  BodyRegion('l_foot', 'القدم اليسرى', 'Left foot', 0.61, 0.94, back: true),
];

/// Human name of any stored region key (body part, tooth number, or a template chip).
String regionLabel(String key, [CaseTemplate? t]) {
  if (key.startsWith('tooth_')) return '${tr('سنة', 'Tooth')} ${key.substring(6)}';
  for (final r in bodyRegions) {
    if (r.key == key) return r.label;
  }
  for (final tpl in [if (t != null) t, ...allTemplates]) {
    for (final c in tpl.regionChips) {
      if (c.key == key) return c.label;
    }
  }
  return key;
}

String optLabel(List<Opt> list, String key) {
  for (final o in list) {
    if (o.key == key) return o.label;
  }
  return key;
}
