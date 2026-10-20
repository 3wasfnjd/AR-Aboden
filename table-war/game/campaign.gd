class_name Campaign
extends RefCounted
## «عملية الدرع الأزرق» (Operation Blue Shield): the story campaign.
##
## A fictional armed network, «الأفعى» (the Viper), has taken over an archipelago with
## civilians living on it and turned the islands into arms depots, smuggling routes and,
## later, an enrichment site. The player commands the battleship and its strike team and
## takes the network apart island by island WITHOUT harming the people who live there.
##
## Chapters (فصول) of five stages (مراحل). Chapter 0 is training (free), chapter 1 is free,
## chapters 2-4 are sold (Store.owns(chapter)); `built` false = not playable yet (shown as
## "in development"). Stage order: a stage opens when the one before it is won.
##
## Stage fields:
##   id, chapter, n            identity and order (n = 1..5 inside the chapter)
##   ar, en                    names;  goal_ar, goal_en   the objective line
##   kinds / cats / pct        objective: structure kinds, target categories (IslandProps.TARGETS)
##                             or a destruction percentage
##   time                      seconds
##   civ_fail                  civilian casualties that fail the stage (default CIV_FAIL)
##   sam                       live SAM sites intercept incoming missiles
##   coastal                   seconds between enemy anti-ship missiles at the battleship (0: none)
##   brief                     briefing lines [speaker, ar, en] before the stage
##   won, failed               the commander's debrief lines [ar, en]
##   focus                     island-local point the briefing marks (the target area)
## Pure data + lookups: tested headless (tests/test_headless.gd).

const CIV_FAIL := 6

## The strike team: id -> [ar name, en name, role ar, role en, colour].
const TEAM := {
	"salem": ["العقيد سالم", "Col. Salem", "قائد الأسطول", "Fleet commander", Color(0.95, 0.78, 0.35)],
	"reem": ["النقيب ريم", "Capt. Reem", "الاستخبارات", "Intelligence", Color(0.45, 0.85, 1.0)],
	"nasser": ["الملازم ناصر", "Lt. Nasser", "مشغّل المسيّرات", "Drone operator", Color(0.55, 1.0, 0.6)],
	"saqr": ["صقر", "Saqr", "قائد القوات الخاصة", "Special forces lead", Color(1.0, 0.55, 0.45)],
}

const CHAPTERS := [
	{"n": 0, "ar": "التدريب", "en": "Training", "sub_ar": "مهمات تدريب على جزيرة الاختبار", "sub_en": "Drills on the test island",
		"free": true, "built": true},
	{"n": 1, "ar": "الوصول", "en": "Arrival", "sub_ar": "جزيرة السبخة: أول مواقع الأفعى", "sub_en": "Sabkha Island: the Viper's first sites",
		"free": true, "built": true},
	{"n": 2, "ar": "خطوط الإمداد", "en": "Supply Lines", "sub_ar": "قوافل وصفقات ومنصات متنقلة", "sub_en": "Convoys, deals and mobile launchers",
		"free": false, "built": false},
	{"n": 3, "ar": "المختبر", "en": "The Laboratory", "sub_ar": "منشأة التخصيب تحت الجبل", "sub_en": "The enrichment site under the mountain",
		"free": false, "built": false},
	{"n": 4, "ar": "رأس الأفعى", "en": "The Viper's Head", "sub_ar": "القائد والقلعة الأخيرة", "sub_en": "The leader and the last fortress",
		"free": false, "built": false},
]

const STAGES := [
	# --- chapter 1: Arrival ---------------------------------------------------------
	{"id": "c1s1", "chapter": 1, "n": 1, "ar": "عين الأفعى", "en": "The Viper's Eye",
		"goal_ar": "دمّر قبة الرادار الساحلي", "goal_en": "Destroy the coastal radar dome",
		"kinds": ["radar_sphere"], "time": 120.0, "sam": false, "coastal": 0.0,
		"focus": Vector3(-0.056, 0.0, -0.160),
		"brief": [
			["salem", "وصلنا مياه الأرخبيل. الأفعى تراقب البحر من رادار على الساحل الجنوبي.", "We are in the archipelago's waters. The Viper watches the sea from a radar on the south coast."],
			["reem", "القبة البيضاء قرب المعسكر. البيوت بعيدة عنها، بس انتبه لحلقة التصويب: إذا صارت صفراء فيه مدنيين.", "The white dome by the camp. The houses are far, but watch the aiming ring: yellow means civilians."],
			["salem", "ضربة واحدة نظيفة. أعمِ عين الأفعى.", "One clean strike. Blind the Viper."],
		],
		"won": ["الرادار طاح. صار البحر لنا.", "The radar is down. The sea is ours."],
		"failed": ["ما يصير كذا. نعيد التخطيط ونرجع.", "Not like this. We replan and go again."]},
	{"id": "c1s2", "chapter": 1, "n": 2, "ar": "زوارق الإمداد", "en": "Supply Boats",
		"goal_ar": "أغرق الفرقاطتين في الخليج", "goal_en": "Sink the two frigates in the bay",
		"kinds": ["frigate"], "time": 150.0, "sam": false, "coastal": 0.0,
		"focus": Vector3(-0.065, 0.0, 0.005),
		"brief": [
			["nasser", "المسيّرة تشوف فرقاطتين للأفعى راسيتين في الخليج جنب المدينة.", "The drone sees two Viper frigates anchored in the bay by the town."],
			["reem", "قوارب الصيد حولهم مدنية. أي قارب يغرق يحسب عليك.", "The fishing boats around them are civilian. Every boat you sink counts against you."],
			["salem", "صاروخ مضاد للسفن يطير ملاصق للبحر. استعمله.", "The anti-ship missile skims the sea. Use it."],
		],
		"won": ["الخليج نظيف. الصيادين بخير.", "The bay is clear. The fishermen are safe."],
		"failed": ["الفرقاطات لسه هناك. نرجع لها.", "The frigates are still there. We go back."]},
	{"id": "c1s3", "chapter": 1, "n": 3, "ar": "مستودع الذخيرة", "en": "The Ammo Depot",
		"goal_ar": "دمّر مستودعَي الذخيرة في الميناء", "goal_en": "Destroy the two ammunition warehouses at the port",
		"kinds": ["warehouse"], "time": 150.0, "sam": false, "coastal": 0.0,
		"focus": Vector3(0.126, 0.0, 0.182),
		"brief": [
			["reem", "الأفعى تخزّن الذخيرة في مستودعين في الميناء، والمدينة ملاصقة لهم.", "The Viper keeps its ammunition in two port warehouses, right against the town."],
			["salem", "الانفجار الكبير يعني ضحايا. سلاح دقيق وانفجار صغير.", "A big blast means casualties. A precise weapon and a small blast."],
			["nasser", "السيارات تعدّي من الشارع جنبهم. انتظر لين يفضى.", "Cars use the street beside them. Wait for it to clear."],
		],
		"won": ["المستودعات انتهت والمدينة سليمة. شغل محترف.", "The depots are gone and the town is intact. Professional work."],
		"failed": ["المهمة فشلت. المدينة أهم من أي هدف.", "Mission failed. The town matters more than any target."]},
	{"id": "c1s4", "chapter": 1, "n": 4, "ar": "مظلة النار", "en": "The Fire Umbrella",
		"goal_ar": "دمّر بطاريات الدفاع الجوي والمخابئ", "goal_en": "Destroy the air-defence batteries and the bunkers",
		"kinds": ["sam", "bunker"], "time": 180.0, "sam": true, "coastal": 0.0,
		"focus": Vector3(-0.030, 0.0, -0.154),
		"brief": [
			["reem", "الأفعى عرفت إننا هنا. شغّلوا الدفاع الجوي: ثلاث بطاريات تعترض صواريخنا.", "The Viper knows we are here. Their air defence is on: three batteries intercepting our missiles."],
			["nasser", "البطيء يسقطونه بسهولة: المسيّرة والكروز. الفرط صوتي صعب يلحقونه.", "Slow ones are easy for them: the drone and the cruise. The hypersonic is hard to catch."],
			["salem", "دمّر البطاريات أول، وبعدها المخابئ.", "Take out the batteries first, then the bunkers."],
		],
		"won": ["السماء مفتوحة. ما عاد يقدرون يوقفونا.", "The sky is open. They can't stop us now."],
		"failed": ["الدفاعات صامدة. نغيّر الأسلحة ونرجع.", "The defences hold. We change weapons and go back."]},
	{"id": "c1s5", "chapter": 1, "n": 5, "ar": "وكر الأفعى", "en": "The Viper's Den",
		"goal_ar": "دمّر القاعدة الجوية: الطائرات والملاجئ والبرج والمنصات", "goal_en": "Destroy the air base: jets, shelters, tower and launchers",
		"kinds": ["jet", "has", "ctower", "launcher_truck", "silo", "silo_open"], "time": 240.0, "sam": true, "coastal": 25.0,
		"focus": Vector3(-0.220, 0.0, -0.093),
		"brief": [
			["salem", "هذا وكرهم في الجزيرة. قاعدة جوية ومنصات صواريخ.", "This is their den on the island. An air base and missile launchers."],
			["reem", "منصاتهم الساحلية بتطلق على البارجة. المدفع يعترض بعضها، بس مو كلها.", "Their coastal launchers will fire at the battleship. Our gun intercepts some, not all."],
			["saqr", "دمّر المنصات بسرعة قبل ما يغرّقونا. وبعدها القاعدة كلها.", "Kill the launchers fast before they sink us. Then the whole base."],
		],
		"won": ["الجزيرة تحررت. الأفعى هربت للجزر الثانية، ونلحقها.", "The island is free. The Viper fled to the other islands; we follow."],
		"failed": ["البارجة ما تتحمل أكثر. ننسحب ونعيد.", "The ship can't take more. We pull back and retry."]},
	# --- chapter 2: Supply Lines (in development) -------------------------------------
	{"id": "c2s1", "chapter": 2, "n": 1, "ar": "القافلة", "en": "The Convoy", "goal_ar": "دمّر قافلة التهريب بين السيارات المدنية", "goal_en": "Destroy the smuggling convoy among civilian cars"},
	{"id": "c2s2", "chapter": 2, "n": 2, "ar": "المنصات المتنقلة", "en": "Mobile Launchers", "goal_ar": "اصطد منصات الصواريخ قبل ما تتحرك", "goal_en": "Catch the launchers before they move"},
	{"id": "c2s3", "chapter": 2, "n": 3, "ar": "الصفقة", "en": "The Deal", "goal_ar": "اضرب صفقة السلاح قبل ما يفترقون", "goal_en": "Hit the arms deal before they split up"},
	{"id": "c2s4", "chapter": 2, "n": 4, "ar": "الوقود والماء", "en": "Fuel and Water", "goal_ar": "دمّر مخزن الوقود واحمِ محطة التحلية", "goal_en": "Destroy the fuel store, spare the desalination plant"},
	{"id": "c2s5", "chapter": 2, "n": 5, "ar": "الهجوم المضاد", "en": "Counter-attack", "goal_ar": "اعترض الهجوم على البارجة", "goal_en": "Survive the attack on the battleship"},
	# --- chapter 3: The Laboratory (in development) -----------------------------------
	{"id": "c3s1", "chapter": 3, "n": 1, "ar": "الاستطلاع", "en": "Recon", "goal_ar": "اكشف مداخل المنشأة بالمسيّرة", "goal_en": "Find the site's entrances with the drone"},
	{"id": "c3s2", "chapter": 3, "n": 2, "ar": "الظلام", "en": "Lights Out", "goal_ar": "اقطع كهرباء المنشأة لا المدينة", "goal_en": "Cut the site's power, not the town's"},
	{"id": "c3s3", "chapter": 3, "n": 3, "ar": "دفاعات الجبل", "en": "Mountain Defences", "goal_ar": "دمّر الرادارات والقواذف في الأنفاق", "goal_en": "Destroy the radars and launchers in the tunnels"},
	{"id": "c3s4", "chapter": 3, "n": 4, "ar": "قاعة الطرد", "en": "The Centrifuge Hall", "goal_ar": "اخترق القاعة بخارق التحصينات", "goal_en": "Breach the hall with the bunker buster"},
	{"id": "c3s5", "chapter": 3, "n": 5, "ar": "الهروب", "en": "The Escape", "goal_ar": "أوقف الشاحنات قبل ما تهرب بالمعدات", "goal_en": "Stop the trucks escaping with the equipment"},
	# --- chapter 4: The Viper's Head (in development) ---------------------------------
	{"id": "c4s1", "chapter": 4, "n": 1, "ar": "الاتصالات", "en": "Communications", "goal_ar": "دمّر مقر الاتصالات", "goal_en": "Destroy the communications HQ"},
	{"id": "c4s2", "chapter": 4, "n": 2, "ar": "الهدف الثمين", "en": "High-Value Target", "goal_ar": "اضرب موكب القائد في اللحظة الصح", "goal_en": "Strike the leader's convoy at the right moment"},
	{"id": "c4s3", "chapter": 4, "n": 3, "ar": "غطاء صقر", "en": "Cover Saqr", "goal_ar": "احمِ إنزال القوات الخاصة", "goal_en": "Cover the special forces landing"},
	{"id": "c4s4", "chapter": 4, "n": 4, "ar": "القلعة", "en": "The Fortress", "goal_ar": "اكسر القلعة الأخيرة", "goal_en": "Break the last fortress"},
	{"id": "c4s5", "chapter": 4, "n": 5, "ar": "الحسم", "en": "The Reckoning", "goal_ar": "المعركة الأخيرة على الأرخبيل", "goal_en": "The final battle for the archipelago"},
]


static func chapter(n: int) -> Dictionary:
	for c in CHAPTERS:
		if int(c.n) == n:
			return c
	return {}


## The stages of chapter `n`, in order. Chapter 0 is the training list (Missions.LIST),
## turned into stage entries.
static func stages_of(n: int) -> Array:
	if n == 0:
		return training()
	var out: Array = []
	for s in STAGES:
		if int(s.chapter) == n:
			out.append(s)
	return out


static func training() -> Array:
	var out: Array = []
	var k := 1
	for m in Missions.LIST:
		var s: Dictionary = (m as Dictionary).duplicate()
		s["chapter"] = 0
		s["n"] = k
		s["sam"] = false
		s["coastal"] = 0.0
		s["civ_fail"] = 9999
		k += 1
		out.append(s)
	return out


static func get_stage(id: String) -> Dictionary:
	for s in STAGES:
		if s.id == id:
			return s
	for s in training():
		if s.id == id:
			return s
	return {}


## A stage can be played: its chapter is built and its stage entry has an objective.
static func is_built(s: Dictionary) -> bool:
	return bool(chapter(int(s.get("chapter", -1))).get("built", false)) and (s.has("kinds") or s.has("cats") or s.has("pct"))


static func speaker(id: String) -> Array:
	return TEAM.get(id, ["", "", "", "", Color.WHITE])
