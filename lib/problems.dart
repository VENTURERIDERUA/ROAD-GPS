// Що програма не змогла прочитати чи зробити — і як це виправити. Тексти для людини, без жаргону.
// Сталі тексти перекладає ProblemCard (t() при показі); тексти з числами — t() тут, з підстановками.
import 'i18n.dart';

enum Severity { error, warning, info }

class Problem {
  final Severity severity;
  final String title;
  final String? detail;

  /// Конкретні кроки, що знімають проблему, — від найпростішого.
  final List<String> fixes;
  const Problem(this.severity, this.title, {this.detail, this.fixes = const []});
}

const _resaveDxf = 'AutoCAD чи Civil 3D: «Файл → Зберегти як» → тип «AutoCAD 2018 DXF (*.dxf)».';
const _odaConverter =
    'Без AutoCAD: безкоштовна програма ODA File Converter (opendesign.com) перетворює DWG на DXF на комп\'ютері.';
const _landXml = 'Вісь Civil 3D точніше передати файлом LandXML («Вивід → Експорт у LandXML») — '
    'разом із профілем.';
const _explode = 'Якщо лінії всередині блоків — розбийте блоки (EXPLODE / РАСЧЛЕНИТЬ, для атрибутів — BURST) '
    'і збережіть DXF знову.';
const _civilExport = 'Об\'єкти Civil 3D (вісь, коридор, лінії характерних точок): «Експорт у AutoCAD» '
    '(EXPORTTOAUTOCAD) — стануть звичайними лініями; тоді зберегти як DXF.';

/// Вибрано файл, який програма не читає, — за розширенням.
Problem? problemForFileName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'dxf' => null,
    // DWG програма не читає (рішення 10.11.2026: бібліотека LibreDWG — GPLv3, а програма — у відкритому доступі).
    'dwg' => const Problem(Severity.error, 'DWG не читається — збережіть як DXF',
        detail: 'AutoCAD / Civil 3D «Зберегти як» або безкоштовний ODA File Converter.',
        fixes: [
          _resaveDxf,
          _odaConverter,
          'Якщо AutoCAD пише «Drawing needs recovery»: команда RECOVER (ВОССТАНОВИТЬ), потім AUDIT (ПРОВЕРИТЬ), '
              'і лише тоді «Зберегти як DXF».',
          _landXml,
        ]),
    'pdf' => const Problem(Severity.error, 'Це PDF — з нього програма координат не бере',
        detail: 'У PDF креслення — картинка аркуша без державних координат; числа в ньому часто злипаються.',
        fixes: [
          'Попросіть у проєктувальника той самий аркуш у DXF (або DWG і збережіть як DXF).',
          'Немає векторного файлу — на головному екрані «Додати» → цей PDF: прив\'язка за точками й обведення осі.',
        ]),
    'mbtiles' || 'pmtiles' => const Problem(Severity.error, 'Це підкладка (карта) — її додають до об’єкта',
        fixes: ['Відкрийте об’єкт → кнопка шарів угорі → «Додати ортофото чи карту».']),
    'tif' || 'tiff' => const Problem(Severity.error, 'Це TIFF — ортофото чи скан креслення',
        fixes: [
          'Ортофото: наріжте в MBTiles (QGIS «Створити XYZ-плитки (MBTiles)») і додайте як підкладку об’єкта.',
          'Скан креслення з віссю — збережіть як PNG чи JPG і додайте на головному екрані: прив\'язка й обведення осі; точніше — DXF від проєктувальника.',
        ]),
    'jpg' || 'jpeg' || 'png' || 'bmp' => const Problem(Severity.error,
        'Це зображення (скан чи фото) — його треба векторизувати',
        fixes: [
          'Пошукайте векторний оригінал (DXF) у проєктувальника — це найточніше.',
          'Або додайте цей скан на головному екрані: прив\'язка за точками й обведення осі пером.',
        ]),
    'xml' || 'landxml' => null,
    'csv' || 'txt' => const Problem(Severity.error, 'Це відомість — її додають до вже створеного об’єкта',
        fixes: [
          'Спершу додайте вісь (DXF або LandXML), потім на екрані об’єкта: кнопка «Дані об’єкта» вгорі → «З відомості (CSV)».',
        ]),
    'xlsx' || 'xls' => const Problem(Severity.error, 'Це Excel — програма читає відомість у форматі CSV',
        fixes: [
          'Excel: «Файл → Зберегти як» → «CSV UTF-8 (розділювач — кома)».',
          'Потім додайте її до об’єкта: кнопка «Дані об’єкта» вгорі → «З відомості (CSV)».',
        ]),
    _ => Problem(Severity.error, t('Файл «{name}» — не креслення DXF', {'name': name}),
        fixes: const ['Виберіть файл з розширенням .dxf.', _resaveDxf]),
  };
}

const binaryDxf = Problem(Severity.error, 'Це двійковий DXF — програма читає лише текстовий',
    fixes: ['AutoCAD: «Зберегти як → DXF», у «Параметрах» збереження вибрати формат ASCII, а не Binary.']);

Problem notDxf(String where) => Problem(Severity.error, 'Файл не схожий на DXF',
    detail: t(
        'Не вдалося прочитати: {where}. Можливо, це інший формат з розширенням .dxf або файл обрізаний '
        '(не докачався з пошти чи хмари).',
        {'where': where}),
    fixes: const [
      'Перекачайте файл ще раз і перевірте, що він відкривається в AutoCAD.',
      _resaveDxf,
    ]);

const noEntities = Problem(Severity.error, 'У файлі немає креслення (розділу ENTITIES)',
    fixes: ['Відкрийте файл в AutoCAD і збережіть як DXF ще раз.', _resaveDxf]);

const noLines = Problem(Severity.error, 'У кресленні немає ліній, які програма читає',
    detail: 'Програма читає відрізки, дуги, полілінії (й 3D-полілінії) та підписи.',
    fixes: [
      _explode,
      'Якщо вісь у зовнішньому посиланні (Xref) — прив\'яжіть його (XREF → Bind / Внедрить).',
      _civilExport,
      'Сплайни (SPLINE) перетворіть на полілінію (SPLINEDIT → «Перетворити на полілінію»).',
    ]);

const proxyInDrawing = Problem(Severity.warning, 'У кресленні є об\'єкти Civil 3D чи інших програм, яких DXF не передає',
    detail: 'Вони залишаються «невидимими» для програми (proxy).',
    fixes: [_civilExport, _landXml]);

/// Що на шарі не прочиталось: кількість за типом.
Problem unreadableOnLayer(String layer, Map<String, int> kinds) {
  final blocks = kinds['INSERT'] ?? 0;
  final proxies = kinds.entries.where((e) => e.key == 'ACAD_PROXY_ENTITY' || e.key.startsWith('AECC')).fold(0, (a, e) => a + e.value);
  final splines = (kinds['SPLINE'] ?? 0) + (kinds['ELLIPSE'] ?? 0);
  return Problem(Severity.warning, t('На шарі «{layer}» є об\'єкти, яких програма не читає', {'layer': layer}),
      detail: [
        if (blocks > 0) t('блоків: {n}', {'n': blocks}),
        if (proxies > 0) t('об\'єктів Civil 3D: {n}', {'n': proxies}),
        if (splines > 0) t('сплайнів чи еліпсів: {n}', {'n': splines}),
        for (final e in kinds.entries)
          if (!{'INSERT', 'ACAD_PROXY_ENTITY', 'SPLINE', 'ELLIPSE'}.contains(e.key) && !e.key.startsWith('AECC'))
            '${e.key}: ${e.value}',
      ].join(', '),
      fixes: [
        if (blocks > 0) _explode,
        if (proxies > 0) _civilExport,
        if (splines > 0) 'Сплайни: SPLINEDIT → «Перетворити на полілінію», точність 0.01 м.',
        'Якщо ці об\'єкти — не частина осі (умовні знаки, підписи), попередження можна не зважати.',
      ]);
}

Problem axisBroken(double used, double total, double second) => Problem(Severity.warning,
    'Вісь, схоже, розірвана: взято лише найдовший шматок',
    detail: t(
        'Взято {used} м; найдовший з решти — {second} м '
        '(усього на шарі {total} м). Кінці шматків розходяться більше ніж на 5 см.',
        {'used': used.toStringAsFixed(0), 'second': second.toStringAsFixed(0), 'total': total.toStringAsFixed(0)}),
    fixes: const [
      'З\'єднайте лінії осі в одну (JOIN / СОЕДИНИТЬ або PEDIT → Join) і збережіть DXF знову.',
      'Якщо на шарі дві різні осі (ліва й права проїзна частина, з\'їзди) — рознесіть їх на різні шари '
          'й додайте окремими об\'єктами.',
    ]);

Problem axisBranches(int n) => Problem(Severity.warning, t('Лінії на шарі осі розгалужуються ({n} місць)', {'n': n}),
    detail: 'Вісь має бути однією лінією без відгалужень. Програма пішла однією з гілок.',
    fixes: const [
      'Перевірте, чи це справді шар осі (а не, наприклад, сітка чи риски).',
      'Приберіть дублікати ліній (OVERKILL / УДАЛИТЬ ДУБЛИКАТЫ) і зайві відгалуження, збережіть DXF знову.',
    ]);

const axisClosed = Problem(Severity.warning, 'Лінія осі замкнена в кільце',
    fixes: ['Для кільцевої розв\'язки перевірте початок пікетажу (зелена позначка на карті).',
      'Для звичайної дороги — це, найпевніше, не той шар (контур, межа ділянки).']);

const outsideCountry = Problem(Severity.warning, 'Вісь не потрапляє в межі країни цієї системи координат',
    fixes: [
      'Натисніть «Змінити» біля системи координат — нагорі списку будуть ті, у яких вісь лягає в межі країни.',
      'Спробуйте перемикач «Поміняти місцями X і Y».',
      'Креслення в умовних чи місцевих координатах (0,0 у куті аркуша, місцева система району) — '
          '«Змінити» → «Калібрувати за точками»: 2–4 точки, які ви знайдете на місцевості.',
    ]);

const noLabels = Problem(Severity.info, 'Підписів пікетажу біля осі не знайдено',
    fixes: ['Введіть ПК початку вручну: подивіться на кресленні, який ПК на початку осі (зелена позначка на карті).']);

Problem labelsDisagree(double spread) => Problem(Severity.warning,
    t('Підписи ПК не узгоджуються між собою (розкид {n} м)', {'n': spread.toStringAsFixed(0)}),
    detail: 'Так буває при розриві пікетажу (рівнянні) або коли підписи стоять не біля своїх рисок.',
    fixes: const [
      'Перевірте ПК початку й напрям на карті: підписи кожні 100 м мають збігатися з кресленням.',
      'Розриви пікетажу програма поки не враховує — для такої дороги додайте ділянки окремими об\'єктами.',
    ]);

Problem brokenSaved(int n) => Problem(Severity.warning, t('Не вдалося прочитати збережених об\'єктів: {n}', {'n': n}),
    detail: 'Файли об\'єктів у пам\'яті пристрою пошкоджені (наприклад, телефон вимкнувся під час запису).',
    fixes: const ['Додайте ці об\'єкти з DXF ще раз.']);

const gpsOff = Problem(Severity.error, 'Геолокацію вимкнено',
    fixes: ['Увімкніть «Місцезнаходження» в налаштуваннях пристрою (кнопка нижче).',
      'Поки що можна дивитися ПК будь-якої точки — режим «Точка на карті».']);

const gpsDenied = Problem(Severity.error, 'Програмі не дозволено знати місцезнаходження',
    fixes: ['Налаштування програми → Дозволи → Місцезнаходження → «Дозволити під час використання» (кнопка нижче).',
      'Поки що — режим «Точка на карті».']);

const gpsWaiting = Problem(Severity.info, 'GPS ще не визначив місце',
    fixes: [
      'Вийдіть на відкрите місце, подалі від будівель і дерев.',
      'Без мобільного інтернету перше визначення може тривати кілька хвилин.',
    ]);

Problem gpsPoor(double accuracy) => Problem(Severity.warning,
    t('Точність GPS ±{n} м — гірша за звичайну (±3–5 м)', {'n': accuracy.toStringAsFixed(0)}),
    fixes: const [
      'Зачекайте хвилину на місці — точність зазвичай покращується.',
      'Відійдіть від будівель, мостів, дерев; не тримайте пристрій у кабіні.',
    ]);

const tilesFailed = Problem(Severity.info, 'Карта-підкладка не завантажується',
    detail: 'Немає інтернету або сайт карти недоступний. Вісь, ПК і лінії працюють і без підкладки.',
    fixes: ['Сховайте підкладку кнопкою шарів угорі, щоб не відволікала.',
      'Офлайн-підкладка (власна ортофото чи завантажена заздалегідь карта) — етап 4.']);
