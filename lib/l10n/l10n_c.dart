// Переклади (група c): ключ — український текст з коду.
const en = <String, String>{
  // Пікетаж, картка проблеми
  'ПК': 'PK',
  'км': 'km',
  'Як виправити:': 'How to fix:',
  'Зрозуміло': 'Got it',

  // Ролі ліній (LineRole.label), схема поперечника
  'Кромка': 'Edge',
  'Бровка': 'Shoulder edge',
  'Підошва укосу': 'Toe of slope',
  'Межа відводу': 'Right-of-way limit',
  'Інша лінія': 'Other line',
  'ліворуч': 'left',
  'праворуч': 'right',
  'я': 'me',

  // problems.dart — спільні кроки
  'AutoCAD чи Civil 3D: «Файл → Зберегти як» → тип «AutoCAD 2018 DXF (*.dxf)».':
      'AutoCAD or Civil 3D: "File → Save As" → type "AutoCAD 2018 DXF (*.dxf)".',
  'Без AutoCAD: безкоштовна програма ODA File Converter (opendesign.com) перетворює DWG на DXF на комп\'ютері.':
      'Without AutoCAD: the free ODA File Converter (opendesign.com) converts DWG to DXF on a computer.',
  'Вісь Civil 3D точніше передати файлом LandXML («Вивід → Експорт у LandXML») — разом із профілем.':
      'A Civil 3D alignment is transferred more accurately as a LandXML file ("Output → Export to LandXML"), together with its profile.',
  'Якщо лінії всередині блоків — розбийте блоки (EXPLODE / РАСЧЛЕНИТЬ, для атрибутів — BURST) і збережіть DXF знову.':
      'If the lines are inside blocks, explode the blocks (EXPLODE; for attributes, BURST) and save the DXF again.',
  'Об\'єкти Civil 3D (вісь, коридор, лінії характерних точок): «Експорт у AutoCAD» (EXPORTTOAUTOCAD) — стануть звичайними лініями; тоді зберегти як DXF.':
      'Civil 3D objects (alignment, corridor, feature lines): "Export to AutoCAD" (EXPORTTOAUTOCAD) turns them into ordinary lines; then save as DXF.',

  // problems.dart — не той файл
  'Якщо AutoCAD пише «Drawing needs recovery»: команда RECOVER (ВОССТАНОВИТЬ), потім AUDIT (ПРОВЕРИТЬ), і лише тоді «Зберегти як DXF».':
      'If AutoCAD says "Drawing needs recovery": run RECOVER, then AUDIT, and only then "Save As" DXF.',
  'Це PDF — з нього програма координат не бере': 'This is a PDF — the app cannot take coordinates from it',
  'У PDF креслення — картинка аркуша без державних координат; числа в ньому часто злипаються.':
      'In a PDF the drawing is a picture of the sheet without national grid coordinates; numbers in it often run together.',
  'Попросіть у проєктувальника той самий аркуш у DXF (або DWG і збережіть як DXF).':
      'Ask the designer for the same sheet in DXF (or in DWG, then save it as DXF).',
  'Немає векторного файлу — на головному екрані «Додати» → цей PDF: прив\'язка за точками й обведення осі.':
      'No vector file — on the home screen tap «Add» → this PDF: georeference by points and trace the axis.',
  'Це підкладка (карта) — її додають до об’єкта': 'This is a basemap — it is added to a project',
  'Відкрийте об’єкт → кнопка шарів угорі → «Додати ортофото чи карту».':
      'Open the project → layers button at the top → "Add orthophoto or map".',
  'Це TIFF — ортофото чи скан креслення': 'This is a TIFF — an orthophoto or a scanned drawing',
  'Ортофото: наріжте в MBTiles (QGIS «Створити XYZ-плитки (MBTiles)») і додайте як підкладку об’єкта.':
      'Orthophoto: cut it into MBTiles (QGIS "Generate XYZ tiles (MBTiles)") and add it as the project basemap.',
  'Скан креслення з віссю — збережіть як PNG чи JPG і додайте на головному екрані: прив\'язка й обведення осі; точніше — DXF від проєктувальника.':
      'A scan of the drawing with the axis — save it as PNG or JPG and add it on the home screen: georeference and trace the axis; a DXF from the designer is more accurate.',
  'Це зображення (скан чи фото) — його треба векторизувати': 'This is an image (scan or photo) — it needs vectorizing',
  'Пошукайте векторний оригінал (DXF) у проєктувальника — це найточніше.':
      'Get the vector original (DXF) from the designer — that is the most accurate.',
  'Або додайте цей скан на головному екрані: прив\'язка за точками й обведення осі пером.':
      'Or add this scan on the home screen: georeference by points and trace the axis with the pen.',
  'Це відомість — її додають до вже створеного об’єкта': 'This is a schedule — it is added to an existing project',
  'Спершу додайте вісь (DXF або LandXML), потім на екрані об’єкта: кнопка «Дані об’єкта» вгорі → «З відомості (CSV)».':
      'First add the axis (DXF or LandXML), then on the project screen: "Project data" button at the top → "From schedule (CSV)".',
  'Це Excel — програма читає відомість у форматі CSV': 'This is Excel — the app reads schedules in CSV format',
  'Excel: «Файл → Зберегти як» → «CSV UTF-8 (розділювач — кома)».':
      'Excel: "File → Save As" → "CSV UTF-8 (Comma delimited)".',
  'Потім додайте її до об’єкта: кнопка «Дані об’єкта» вгорі → «З відомості (CSV)».':
      'Then add it to the project: "Project data" button at the top → "From schedule (CSV)".',
  'Файл «{name}» — не креслення DXF': 'File "{name}" is not a DXF drawing',
  'Виберіть файл з розширенням .dxf.': 'Choose a file with the .dxf extension.',

  // problems.dart — DXF не читається
  'Це двійковий DXF — програма читає лише текстовий': 'This is a binary DXF — the app reads only text (ASCII) DXF',
  'AutoCAD: «Зберегти як → DXF», у «Параметрах» збереження вибрати формат ASCII, а не Binary.':
      'AutoCAD: "Save As → DXF", and in the save "Options" choose ASCII format, not Binary.',
  'Файл не схожий на DXF': 'The file does not look like a DXF',
  'Не вдалося прочитати: {where}. Можливо, це інший формат з розширенням .dxf або файл обрізаний (не докачався з пошти чи хмари).':
      'Could not read: {where}. It may be another format with a .dxf extension, or the file is truncated (not fully downloaded from email or the cloud).',
  'Перекачайте файл ще раз і перевірте, що він відкривається в AutoCAD.':
      'Download the file again and check that it opens in AutoCAD.',
  'У файлі немає креслення (розділу ENTITIES)': 'The file has no drawing (no ENTITIES section)',
  'Відкрийте файл в AutoCAD і збережіть як DXF ще раз.': 'Open the file in AutoCAD and save it as DXF again.',
  'У кресленні немає ліній, які програма читає': 'The drawing has no lines the app can read',
  'Програма читає відрізки, дуги, полілінії (й 3D-полілінії) та підписи.':
      'The app reads lines, arcs, polylines (including 3D polylines) and text labels.',
  'Якщо вісь у зовнішньому посиланні (Xref) — прив\'яжіть його (XREF → Bind / Внедрить).':
      'If the axis is in an external reference (Xref), bind it (XREF → Bind).',
  'Сплайни (SPLINE) перетворіть на полілінію (SPLINEDIT → «Перетворити на полілінію»).':
      'Convert splines (SPLINE) to polylines (SPLINEDIT → "Convert to Polyline").',
  'У кресленні є об\'єкти Civil 3D чи інших програм, яких DXF не передає':
      'The drawing has Civil 3D or other programs\' objects that DXF does not carry',
  'Вони залишаються «невидимими» для програми (proxy).': 'They stay "invisible" to the app (proxy objects).',
  'На шарі «{layer}» є об\'єкти, яких програма не читає': 'Layer "{layer}" has objects the app cannot read',
  'блоків: {n}': 'blocks: {n}',
  'об\'єктів Civil 3D: {n}': 'Civil 3D objects: {n}',
  'сплайнів чи еліпсів: {n}': 'splines or ellipses: {n}',
  'Сплайни: SPLINEDIT → «Перетворити на полілінію», точність 0.01 м.':
      'Splines: SPLINEDIT → "Convert to Polyline", precision 0.01 m.',
  'Якщо ці об\'єкти — не частина осі (умовні знаки, підписи), попередження можна не зважати.':
      'If these objects are not part of the axis (symbols, labels), you can ignore this warning.',

  // problems.dart — вісь і пікетаж
  'Вісь, схоже, розірвана: взято лише найдовший шматок': 'The axis seems broken: only the longest piece was used',
  'Взято {used} м; найдовший з решти — {second} м (усього на шарі {total} м). Кінці шматків розходяться більше ніж на 5 см.':
      'Used {used} m; the longest of the rest is {second} m ({total} m on the layer in total). The ends of the pieces are more than 5 cm apart.',
  'З\'єднайте лінії осі в одну (JOIN / СОЕДИНИТЬ або PEDIT → Join) і збережіть DXF знову.':
      'Join the axis lines into one (JOIN or PEDIT → Join) and save the DXF again.',
  'Якщо на шарі дві різні осі (ліва й права проїзна частина, з\'їзди) — рознесіть їх на різні шари й додайте окремими об\'єктами.':
      'If the layer holds two different axes (left and right carriageways, ramps), move them to separate layers and add them as separate projects.',
  'Лінії на шарі осі розгалужуються ({n} місць)': 'Lines on the axis layer branch ({n} places)',
  'Вісь має бути однією лінією без відгалужень. Програма пішла однією з гілок.':
      'The axis must be a single line without branches. The app followed one of the branches.',
  'Перевірте, чи це справді шар осі (а не, наприклад, сітка чи риски).':
      'Check that this really is the axis layer (and not, say, a grid or tick marks).',
  'Приберіть дублікати ліній (OVERKILL / УДАЛИТЬ ДУБЛИКАТЫ) і зайві відгалуження, збережіть DXF знову.':
      'Remove duplicate lines (OVERKILL) and extra branches, then save the DXF again.',
  'Лінія осі замкнена в кільце': 'The axis line is closed into a loop',
  'Для кільцевої розв\'язки перевірте початок пікетажу (зелена позначка на карті).':
      'For a roundabout, check where the chainage starts (green marker on the map).',
  'Для звичайної дороги — це, найпевніше, не той шар (контур, межа ділянки).':
      'For an ordinary road, this is most likely the wrong layer (an outline, a plot boundary).',
  'Вісь не потрапляє в межі країни цієї системи координат':
      'The axis is outside the country of this coordinate system',
  'Натисніть «Змінити» біля системи координат — нагорі списку будуть ті, у яких вісь лягає в межі країни.':
      'Tap "Change" next to the coordinate system — systems in which the axis falls inside the country will be at the top of the list.',
  'Спробуйте перемикач «Поміняти місцями X і Y».': 'Try the "Swap X and Y" switch.',
  'Креслення в умовних чи місцевих координатах (0,0 у куті аркуша, місцева система району) — «Змінити» → «Калібрувати за точками»: 2–4 точки, які ви знайдете на місцевості.':
      'Drawing in arbitrary or local coordinates (0,0 in the sheet corner, a local district system): "Change" → "Calibrate by points": 2–4 points you can find on site.',
  'Підписів пікетажу біля осі не знайдено': 'No chainage labels found near the axis',
  'Введіть ПК початку вручну: подивіться на кресленні, який ПК на початку осі (зелена позначка на карті).':
      'Enter the start PK manually: check on the drawing which PK is at the start of the axis (green marker on the map).',
  'Підписи ПК не узгоджуються між собою (розкид {n} м)': 'PK labels do not agree with each other (spread {n} m)',
  'Так буває при розриві пікетажу (рівнянні) або коли підписи стоять не біля своїх рисок.':
      'This happens at a chainage break (station equation) or when labels are not next to their tick marks.',
  'Перевірте ПК початку й напрям на карті: підписи кожні 100 м мають збігатися з кресленням.':
      'Check the start PK and direction on the map: the labels every 100 m must match the drawing.',
  'Розриви пікетажу програма поки не враховує — для такої дороги додайте ділянки окремими об\'єктами.':
      'The app does not handle chainage breaks yet — for such a road, add the sections as separate projects.',
  'Не вдалося прочитати збережених об\'єктів: {n}': 'Saved projects that could not be read: {n}',
  'Файли об\'єктів у пам\'яті пристрою пошкоджені (наприклад, телефон вимкнувся під час запису).':
      'Project files in device storage are damaged (for example, the phone switched off while saving).',
  'Додайте ці об\'єкти з DXF ще раз.': 'Add these projects from DXF again.',

  // problems.dart — GPS і карта
  'Геолокацію вимкнено': 'Location is turned off',
  'Увімкніть «Місцезнаходження» в налаштуваннях пристрою (кнопка нижче).':
      'Turn on "Location" in the device settings (button below).',
  'Поки що можна дивитися ПК будь-якої точки — режим «Точка на карті».':
      'Meanwhile you can check the PK of any point — "Point on map" mode.',
  'Програмі не дозволено знати місцезнаходження': 'The app is not allowed to access location',
  'Налаштування програми → Дозволи → Місцезнаходження → «Дозволити під час використання» (кнопка нижче).':
      'App settings → Permissions → Location → "Allow only while using the app" (button below).',
  'Поки що — режим «Точка на карті».': 'Meanwhile, use "Point on map" mode.',
  'GPS ще не визначив місце': 'GPS has not found the position yet',
  'Вийдіть на відкрите місце, подалі від будівель і дерев.': 'Move to an open place, away from buildings and trees.',
  'Без мобільного інтернету перше визначення може тривати кілька хвилин.':
      'Without mobile internet, the first fix can take a few minutes.',
  'Точність GPS ±{n} м — гірша за звичайну (±3–5 м)': 'GPS accuracy ±{n} m — worse than usual (±3–5 m)',
  'Зачекайте хвилину на місці — точність зазвичай покращується.': 'Wait a minute in place — accuracy usually improves.',
  'Відійдіть від будівель, мостів, дерев; не тримайте пристрій у кабіні.':
      'Move away from buildings, bridges and trees; do not keep the device inside the cab.',
  'Карта-підкладка не завантажується': 'The basemap is not loading',
  'Немає інтернету або сайт карти недоступний. Вісь, ПК і лінії працюють і без підкладки.':
      'No internet, or the map site is unavailable. The axis, PK and lines work without a basemap.',
  'Сховайте підкладку кнопкою шарів угорі, щоб не відволікала.':
      'Hide the basemap with the layers button at the top so it does not distract you.',
  'Офлайн-підкладка (власна ортофото чи завантажена заздалегідь карта) — етап 4.':
      'Offline basemap (your own orthophoto or a map downloaded in advance) — stage 4.',

  // vidomist.dart, csv_import_screen.dart — відомість CSV
  'Проєктна відмітка': 'Design elevation',
  'Напівширина': 'Half-width',
  'Ширина (повна)': 'Width (full)',
  'Відомість порожня': 'The schedule is empty',
  'Перевірте, що вибрано той файл; збережіть таблицю з Excel як «CSV UTF-8 (розділювач — кома)».':
      'Check that the right file is selected; save the table from Excel as "CSV UTF-8 (Comma delimited)".',
  'Колонка {n}': 'Column {n}',
  'Не вибрано колонку ПК': 'No PK column selected',
  'Виберіть у списку колонку з пікетажем (наприклад «PK», «ПК», «S_m»).':
      'Choose the chainage column in the list (for example "PK", "KM", "S_m").',
  'Немає такої колонки — додайте її в Excel і збережіть CSV ще раз.':
      'No such column — add it in Excel and save the CSV again.',
  'Не вибрано жодної колонки з даними': 'No data column selected',
  'Виберіть колонку проєктної відмітки та/або ширини.': 'Choose the design elevation and/or width column.',
  'рядок {n}: ПК «{v}»': 'row {n}: PK "{v}"',
  'рядок {n}: відмітка «{v}»': 'row {n}: elevation "{v}"',
  'Не прочиталось клітинок: {n}': 'Cells not read: {n}',
  'Наприклад: {a}.': 'For example: {a}.',
  'Порожні клітинки й текст замість чисел програма пропускає — перевірте ці рядки в Excel.':
      'The app skips empty cells and text instead of numbers — check these rows in Excel.',
  'Десяткова кома й крапка читаються обидві; пробіли в числах — теж.':
      'Both decimal comma and decimal point are read; so are spaces in numbers.',
  'У відомості є однакові ПК': 'The schedule has duplicate PKs',
  'Буває на розриві пікетажу або при повторі рядків. Береться перший за порядком.':
      'Happens at a chainage break or when rows are repeated. The first one in order is used.',
  'Приберіть повтори в Excel; розриви пікетажу програма поки не враховує.':
      'Remove the repeats in Excel; the app does not handle chainage breaks yet.',
  'ПК відомості не збігаються з віссю': 'Schedule PKs do not match the axis',
  'Відомість: {a}–{b} м, вісь: {c}–{d} м.': 'Schedule: {a}–{b} m, axis: {c}–{d} m.',
  'Перевірте ПК початку осі (екран об’єкта) — він має збігатися з пікетажем відомості.':
      'Check the axis start PK (project screen) — it must match the schedule chainage.',
  'Перевірте колонку ПК: метри чи пікети (12+34 = 1234 м)?':
      'Check the PK column: metres or 100 m stations (12+34 = 1234 m)?',
  'Відомість покриває не всю вісь': 'The schedule does not cover the whole axis',
  'Відмітки будуть лише на {a}–{b} м.': 'Elevations will be available only on {a}–{b} m.',
  'Відміток замало — потрібно щонайменше два рядки': 'Too few elevations — at least two rows are needed',
  'Перевірте колонку відмітки й десятковий роздільник.': 'Check the elevation column and the decimal separator.',
  'Відомість: {f}': 'Schedule: {f}',
  'Програма вибрала колонки за назвами — перевірте.': 'The app picked the columns by their names — please check.',
  '— немає —': '— none —',
  'Відміток: {n}, ПК {a}–{b} м.': 'Elevations: {n}, PK {a}–{b} m.',
  'Ширин: {n}.': 'Widths: {n}.',
  'Перші рядки файлу:': 'First rows of the file:',
  'Додати до об’єкта': 'Add to project',

  // landxml.dart
  'Файл не схожий на LandXML': 'The file does not look like LandXML',
  'Civil 3D: «Вивід → Експорт у LandXML», позначте вісь і її профіль.':
      'Civil 3D: "Output → Export to LandXML", select the alignment and its profile.',
  'Або збережіть вісь як DXF («Експорт у AutoCAD», потім «Зберегти як DXF»).':
      'Or save the axis as DXF ("Export to AutoCAD", then "Save As" DXF).',
  'XML не читається: {e}': 'Cannot read the XML: {e}',
  'Кореневий елемент — «{n}».': 'The root element is "{n}".',
  'Одиниці LandXML — «{u}», а не метри': 'LandXML units are "{u}", not metres',
  'Експортуйте LandXML з метричними одиницями (налаштування креслення Civil 3D → Units: Meters).':
      'Export LandXML in metric units (Civil 3D drawing settings → Units: Meters).',
  'Клотоїда «{n}» не зійшлася з кінцем на {m} м': 'Spiral "{n}" misses its end point by {m} m',
  'Перевірте параметри клотоїди в Civil 3D; ПК на ній може відрізнятися на цю величину.':
      'Check the spiral parameters in Civil 3D; PK along it may be off by this amount.',
  'Елемент осі «{n}» програма не читає': 'The app cannot read axis element "{n}"',
  'Повідомте розробнику, з якої програми цей LandXML.': 'Tell the developer which program produced this LandXML.',
  'В осі є розриви пікетажу (StaEquation)': 'The axis has chainage breaks (StaEquation)',
  'Програма рахує пікетаж без розривів — після розриву ПК відрізнятиметься.':
      'The app counts chainage without breaks — after a break, PK will differ.',
  'Розбийте вісь у Civil 3D на ділянки між розривами й додайте їх окремими об’єктами.':
      'Split the alignment in Civil 3D into sections between the breaks and add them as separate projects.',
  'Вісь {n}': 'Axis {n}',
  'профіль': 'profile',
  'У файлі немає осей (Alignment з CoordGeom).': 'The file has no alignments (Alignment with CoordGeom).',
  'У елементі {e} немає точки {tag}.': 'Element {e} has no {tag} point.',

  // dxf.dart
  'рядок {n} — «{s}» замість числового коду': 'line {n} — "{s}" instead of a numeric code',
  'файл порожній': 'the file is empty',
};

const ro = <String, String>{
  // Пікетаж, картка проблеми
  'ПК': 'PK',
  'км': 'km',
  'Як виправити:': 'Cum se rezolvă:',
  'Зрозуміло': 'Am înțeles',

  // Ролі ліній (LineRole.label), схема поперечника
  'Кромка': 'Margine carosabil',
  'Бровка': 'Muchie taluz',
  'Підошва укосу': 'Piciorul taluzului',
  'Межа відводу': 'Limita de expropriere',
  'Інша лінія': 'Altă linie',
  'ліворуч': 'stânga',
  'праворуч': 'dreapta',
  'я': 'eu',

  // problems.dart — спільні кроки (меню AutoCAD / Civil 3D — англійською: румунської версії немає)
  'AutoCAD чи Civil 3D: «Файл → Зберегти як» → тип «AutoCAD 2018 DXF (*.dxf)».':
      'AutoCAD sau Civil 3D: „File → Save As” → tipul „AutoCAD 2018 DXF (*.dxf)”.',
  'Без AutoCAD: безкоштовна програма ODA File Converter (opendesign.com) перетворює DWG на DXF на комп\'ютері.':
      'Fără AutoCAD: programul gratuit ODA File Converter (opendesign.com) convertește DWG în DXF pe calculator.',
  'Вісь Civil 3D точніше передати файлом LandXML («Вивід → Експорт у LandXML») — разом із профілем.':
      'Axa din Civil 3D se transmite mai exact ca fișier LandXML („Output → Export to LandXML”), împreună cu profilul.',
  'Якщо лінії всередині блоків — розбийте блоки (EXPLODE / РАСЧЛЕНИТЬ, для атрибутів — BURST) і збережіть DXF знову.':
      'Dacă liniile sunt în interiorul blocurilor, descompuneți blocurile (EXPLODE; pentru atribute, BURST) și salvați din nou DXF-ul.',
  'Об\'єкти Civil 3D (вісь, коридор, лінії характерних точок): «Експорт у AutoCAD» (EXPORTTOAUTOCAD) — стануть звичайними лініями; тоді зберегти як DXF.':
      'Obiectele Civil 3D (axă, coridor, feature lines): „Export to AutoCAD” (EXPORTTOAUTOCAD) le transformă în linii obișnuite; apoi salvați ca DXF.',

  // problems.dart — не той файл
  'Якщо AutoCAD пише «Drawing needs recovery»: команда RECOVER (ВОССТАНОВИТЬ), потім AUDIT (ПРОВЕРИТЬ), і лише тоді «Зберегти як DXF».':
      'Dacă AutoCAD afișează „Drawing needs recovery”: comanda RECOVER, apoi AUDIT și abia apoi „Save As” DXF.',
  'Це PDF — з нього програма координат не бере': 'Este un PDF — aplicația nu poate prelua coordonate din el',
  'У PDF креслення — картинка аркуша без державних координат; числа в ньому часто злипаються.':
      'Într-un PDF desenul este o imagine a planșei fără coordonate în sistemul național; cifrele din el se lipesc adesea.',
  'Попросіть у проєктувальника той самий аркуш у DXF (або DWG і збережіть як DXF).':
      'Cereți proiectantului aceeași planșă în DXF (sau în DWG și salvați-o ca DXF).',
  'Немає векторного файлу — на головному екрані «Додати» → цей PDF: прив\'язка за точками й обведення осі.':
      'Nu există fișier vectorial — pe ecranul principal «Adaugă» → acest PDF: georeferențiere pe puncte și trasarea axei.',
  'Це підкладка (карта) — її додають до об’єкта': 'Este o hartă de fundal — se adaugă la un proiect',
  'Відкрийте об’єкт → кнопка шарів угорі → «Додати ортофото чи карту».':
      'Deschideți proiectul → butonul de straturi de sus → „Adăugați ortofoto sau hartă”.',
  'Це TIFF — ортофото чи скан креслення': 'Este un TIFF — ortofoto sau desen scanat',
  'Ортофото: наріжте в MBTiles (QGIS «Створити XYZ-плитки (MBTiles)») і додайте як підкладку об’єкта.':
      'Ortofoto: tăiați-l în MBTiles (QGIS „Generate XYZ tiles (MBTiles)”) și adăugați-l ca hartă de fundal a proiectului.',
  'Скан креслення з віссю — збережіть як PNG чи JPG і додайте на головному екрані: прив\'язка й обведення осі; точніше — DXF від проєктувальника.':
      'O scanare a desenului cu axa — salvați-o ca PNG sau JPG și adăugați-o pe ecranul principal: georeferențiere și trasarea axei; un DXF de la proiectant este mai precis.',
  'Це зображення (скан чи фото) — його треба векторизувати':
      'Este o imagine (scanare sau fotografie) — trebuie vectorizată',
  'Пошукайте векторний оригінал (DXF) у проєктувальника — це найточніше.':
      'Cereți originalul vectorial (DXF) proiectantului — este cel mai exact.',
  'Або додайте цей скан на головному екрані: прив\'язка за точками й обведення осі пером.':
      'Sau adăugați această scanare pe ecranul principal: georeferențiere pe puncte și trasarea axei cu creionul.',
  'Це відомість — її додають до вже створеного об’єкта': 'Este un tabel — se adaugă la un proiect deja creat',
  'Спершу додайте вісь (DXF або LandXML), потім на екрані об’єкта: кнопка «Дані об’єкта» вгорі → «З відомості (CSV)».':
      'Mai întâi adăugați axa (DXF sau LandXML), apoi pe ecranul proiectului: butonul „Datele proiectului” de sus → „Din tabel (CSV)”.',
  'Це Excel — програма читає відомість у форматі CSV': 'Este Excel — aplicația citește tabelul în format CSV',
  'Excel: «Файл → Зберегти як» → «CSV UTF-8 (розділювач — кома)».':
      'Excel: „Fișier → Salvare ca” → „CSV UTF-8 (delimitat prin virgulă)”.',
  'Потім додайте її до об’єкта: кнопка «Дані об’єкта» вгорі → «З відомості (CSV)».':
      'Apoi adăugați-l la proiect: butonul „Datele proiectului” de sus → „Din tabel (CSV)”.',
  'Файл «{name}» — не креслення DXF': 'Fișierul „{name}” nu este un desen DXF',
  'Виберіть файл з розширенням .dxf.': 'Alegeți un fișier cu extensia .dxf.',

  // problems.dart — DXF не читається
  'Це двійковий DXF — програма читає лише текстовий': 'Este un DXF binar — aplicația citește doar DXF text (ASCII)',
  'AutoCAD: «Зберегти як → DXF», у «Параметрах» збереження вибрати формат ASCII, а не Binary.':
      'AutoCAD: „Save As → DXF”, iar în „Options” la salvare alegeți formatul ASCII, nu Binary.',
  'Файл не схожий на DXF': 'Fișierul nu pare a fi DXF',
  'Не вдалося прочитати: {where}. Можливо, це інший формат з розширенням .dxf або файл обрізаний (не докачався з пошти чи хмари).':
      'Nu s-a putut citi: {where}. Poate fi alt format cu extensia .dxf sau fișierul este trunchiat (nu s-a descărcat complet din e-mail sau din cloud).',
  'Перекачайте файл ще раз і перевірте, що він відкривається в AutoCAD.':
      'Descărcați din nou fișierul și verificați că se deschide în AutoCAD.',
  'У файлі немає креслення (розділу ENTITIES)': 'Fișierul nu conține desen (secțiunea ENTITIES)',
  'Відкрийте файл в AutoCAD і збережіть як DXF ще раз.': 'Deschideți fișierul în AutoCAD și salvați-l din nou ca DXF.',
  'У кресленні немає ліній, які програма читає': 'Desenul nu conține linii pe care aplicația le poate citi',
  'Програма читає відрізки, дуги, полілінії (й 3D-полілінії) та підписи.':
      'Aplicația citește segmente, arce, polilinii (inclusiv polilinii 3D) și texte.',
  'Якщо вісь у зовнішньому посиланні (Xref) — прив\'яжіть його (XREF → Bind / Внедрить).':
      'Dacă axa este într-o referință externă (Xref), legați-o (XREF → Bind).',
  'Сплайни (SPLINE) перетворіть на полілінію (SPLINEDIT → «Перетворити на полілінію»).':
      'Convertiți splinele (SPLINE) în polilinii (SPLINEDIT → „Convert to Polyline”).',
  'У кресленні є об\'єкти Civil 3D чи інших програм, яких DXF не передає':
      'Desenul conține obiecte Civil 3D sau din alte programe, pe care DXF nu le transmite',
  'Вони залишаються «невидимими» для програми (proxy).': 'Ele rămân „invizibile” pentru aplicație (obiecte proxy).',
  'На шарі «{layer}» є об\'єкти, яких програма не читає':
      'Stratul „{layer}” conține obiecte pe care aplicația nu le citește',
  'блоків: {n}': 'blocuri: {n}',
  'об\'єктів Civil 3D: {n}': 'obiecte Civil 3D: {n}',
  'сплайнів чи еліпсів: {n}': 'spline sau elipse: {n}',
  'Сплайни: SPLINEDIT → «Перетворити на полілінію», точність 0.01 м.':
      'Spline: SPLINEDIT → „Convert to Polyline”, precizie 0.01 m.',
  'Якщо ці об\'єкти — не частина осі (умовні знаки, підписи), попередження можна не зважати.':
      'Dacă aceste obiecte nu fac parte din axă (simboluri, texte), puteți ignora avertizarea.',

  // problems.dart — вісь і пікетаж
  'Вісь, схоже, розірвана: взято лише найдовший шматок': 'Axa pare întreruptă: s-a preluat doar cea mai lungă bucată',
  'Взято {used} м; найдовший з решти — {second} м (усього на шарі {total} м). Кінці шматків розходяться більше ніж на 5 см.':
      'Preluat {used} m; cea mai lungă dintre celelalte — {second} m (în total pe strat {total} m). Capetele bucăților sunt la peste 5 cm unul de altul.',
  'З\'єднайте лінії осі в одну (JOIN / СОЕДИНИТЬ або PEDIT → Join) і збережіть DXF знову.':
      'Uniți liniile axei într-una singură (JOIN sau PEDIT → Join) și salvați din nou DXF-ul.',
  'Якщо на шарі дві різні осі (ліва й права проїзна частина, з\'їзди) — рознесіть їх на різні шари й додайте окремими об\'єктами.':
      'Dacă pe strat sunt două axe diferite (calea stângă și dreaptă, bretele), mutați-le pe straturi diferite și adăugați-le ca proiecte separate.',
  'Лінії на шарі осі розгалужуються ({n} місць)': 'Liniile de pe stratul axei se ramifică ({n} locuri)',
  'Вісь має бути однією лінією без відгалужень. Програма пішла однією з гілок.':
      'Axa trebuie să fie o singură linie fără ramificații. Aplicația a urmat una dintre ramuri.',
  'Перевірте, чи це справді шар осі (а не, наприклад, сітка чи риски).':
      'Verificați dacă acesta este într-adevăr stratul axei (și nu, de exemplu, un caroiaj sau repere).',
  'Приберіть дублікати ліній (OVERKILL / УДАЛИТЬ ДУБЛИКАТЫ) і зайві відгалуження, збережіть DXF знову.':
      'Eliminați liniile duplicate (OVERKILL) și ramificațiile în plus, apoi salvați din nou DXF-ul.',
  'Лінія осі замкнена в кільце': 'Linia axei este închisă în buclă',
  'Для кільцевої розв\'язки перевірте початок пікетажу (зелена позначка на карті).':
      'Pentru un sens giratoriu, verificați începutul pichetajului (marcajul verde de pe hartă).',
  'Для звичайної дороги — це, найпевніше, не той шар (контур, межа ділянки).':
      'Pentru un drum obișnuit, cel mai probabil este stratul greșit (un contur, o limită de parcelă).',
  'Вісь не потрапляє в межі країни цієї системи координат':
      'Axa nu se încadrează în limitele țării acestui sistem de coordonate',
  'Натисніть «Змінити» біля системи координат — нагорі списку будуть ті, у яких вісь лягає в межі країни.':
      'Apăsați „Schimbă” lângă sistemul de coordonate — în partea de sus a listei vor fi sistemele în care axa se încadrează în țară.',
  'Спробуйте перемикач «Поміняти місцями X і Y».': 'Încercați comutatorul „Inversează X și Y”.',
  'Креслення в умовних чи місцевих координатах (0,0 у куті аркуша, місцева система району) — «Змінити» → «Калібрувати за точками»: 2–4 точки, які ви знайдете на місцевості.':
      'Desen în coordonate convenționale sau locale (0,0 în colțul planșei, sistem local): „Schimbă” → „Calibrare pe puncte”: 2–4 puncte pe care le găsiți pe teren.',
  'Підписів пікетажу біля осі не знайдено': 'Nu s-au găsit texte de pichetaj lângă axă',
  'Введіть ПК початку вручну: подивіться на кресленні, який ПК на початку осі (зелена позначка на карті).':
      'Introduceți manual PK de început: verificați pe desen ce PK este la începutul axei (marcajul verde de pe hartă).',
  'Підписи ПК не узгоджуються між собою (розкид {n} м)': 'Textele PK nu concordă între ele (abatere {n} m)',
  'Так буває при розриві пікетажу (рівнянні) або коли підписи стоять не біля своїх рисок.':
      'Se întâmplă la o întrerupere de pichetaj (ecuație de pichetaj) sau când textele nu sunt lângă reperele lor.',
  'Перевірте ПК початку й напрям на карті: підписи кожні 100 м мають збігатися з кресленням.':
      'Verificați PK de început și sensul pe hartă: textele de la fiecare 100 m trebuie să coincidă cu desenul.',
  'Розриви пікетажу програма поки не враховує — для такої дороги додайте ділянки окремими об\'єктами.':
      'Aplicația nu ține încă seama de întreruperile de pichetaj — pentru un astfel de drum adăugați tronsoanele ca proiecte separate.',
  'Не вдалося прочитати збережених об\'єктів: {n}': 'Proiecte salvate care nu s-au putut citi: {n}',
  'Файли об\'єктів у пам\'яті пристрою пошкоджені (наприклад, телефон вимкнувся під час запису).':
      'Fișierele proiectelor din memoria dispozitivului sunt deteriorate (de exemplu, telefonul s-a oprit în timpul salvării).',
  'Додайте ці об\'єкти з DXF ще раз.': 'Adăugați din nou aceste proiecte din DXF.',

  // problems.dart — GPS і карта
  'Геолокацію вимкнено': 'Localizarea este dezactivată',
  'Увімкніть «Місцезнаходження» в налаштуваннях пристрою (кнопка нижче).':
      'Activați „Locație” în setările dispozitivului (butonul de mai jos).',
  'Поки що можна дивитися ПК будь-якої точки — режим «Точка на карті».':
      'Între timp puteți vedea PK-ul oricărui punct — modul „Punct pe hartă”.',
  'Програмі не дозволено знати місцезнаходження': 'Aplicația nu are permisiunea de a accesa locația',
  'Налаштування програми → Дозволи → Місцезнаходження → «Дозволити під час використання» (кнопка нижче).':
      'Setările aplicației → Permisiuni → Locație → „Permiteți doar în timp ce folosiți aplicația” (butonul de mai jos).',
  'Поки що — режим «Точка на карті».': 'Între timp — modul „Punct pe hartă”.',
  'GPS ще не визначив місце': 'GPS-ul nu a determinat încă poziția',
  'Вийдіть на відкрите місце, подалі від будівель і дерев.': 'Ieșiți într-un loc deschis, departe de clădiri și copaci.',
  'Без мобільного інтернету перше визначення може тривати кілька хвилин.':
      'Fără internet mobil, prima determinare poate dura câteva minute.',
  'Точність GPS ±{n} м — гірша за звичайну (±3–5 м)': 'Precizie GPS ±{n} m — mai slabă decât de obicei (±3–5 m)',
  'Зачекайте хвилину на місці — точність зазвичай покращується.':
      'Așteptați un minut pe loc — de obicei precizia se îmbunătățește.',
  'Відійдіть від будівель, мостів, дерев; не тримайте пристрій у кабіні.':
      'Depărtați-vă de clădiri, poduri și copaci; nu țineți dispozitivul în cabină.',
  'Карта-підкладка не завантажується': 'Harta de fundal nu se încarcă',
  'Немає інтернету або сайт карти недоступний. Вісь, ПК і лінії працюють і без підкладки.':
      'Nu există internet sau site-ul hărții nu este disponibil. Axa, PK și liniile funcționează și fără hartă de fundal.',
  'Сховайте підкладку кнопкою шарів угорі, щоб не відволікала.':
      'Ascundeți harta de fundal cu butonul de straturi de sus, ca să nu vă distragă.',
  'Офлайн-підкладка (власна ортофото чи завантажена заздалегідь карта) — етап 4.':
      'Hartă de fundal offline (ortofoto propriu sau hartă descărcată în prealabil) — etapa 4.',

  // vidomist.dart, csv_import_screen.dart — відомість CSV
  'Проєктна відмітка': 'Cotă proiectată',
  'Напівширина': 'Semilățime',
  'Ширина (повна)': 'Lățime (totală)',
  'Відомість порожня': 'Tabelul este gol',
  'Перевірте, що вибрано той файл; збережіть таблицю з Excel як «CSV UTF-8 (розділювач — кома)».':
      'Verificați că ați ales fișierul corect; salvați tabelul din Excel ca „CSV UTF-8 (delimitat prin virgulă)”.',
  'Колонка {n}': 'Coloana {n}',
  'Не вибрано колонку ПК': 'Nu este aleasă coloana PK',
  'Виберіть у списку колонку з пікетажем (наприклад «PK», «ПК», «S_m»).':
      'Alegeți din listă coloana cu pichetajul (de exemplu „PK”, „KM”, „S_m”).',
  'Немає такої колонки — додайте її в Excel і збережіть CSV ще раз.':
      'Nu există o astfel de coloană — adăugați-o în Excel și salvați din nou CSV-ul.',
  'Не вибрано жодної колонки з даними': 'Nu este aleasă nicio coloană cu date',
  'Виберіть колонку проєктної відмітки та/або ширини.': 'Alegeți coloana cotei proiectate și/sau a lățimii.',
  'рядок {n}: ПК «{v}»': 'rândul {n}: PK „{v}”',
  'рядок {n}: відмітка «{v}»': 'rândul {n}: cotă „{v}”',
  'Не прочиталось клітинок: {n}': 'Celule necitite: {n}',
  'Наприклад: {a}.': 'De exemplu: {a}.',
  'Порожні клітинки й текст замість чисел програма пропускає — перевірте ці рядки в Excel.':
      'Aplicația sare peste celulele goale și peste textul în loc de numere — verificați aceste rânduri în Excel.',
  'Десяткова кома й крапка читаються обидві; пробіли в числах — теж.':
      'Se citesc atât virgula, cât și punctul zecimal; la fel și spațiile din numere.',
  'У відомості є однакові ПК': 'Tabelul are PK-uri identice',
  'Буває на розриві пікетажу або при повторі рядків. Береться перший за порядком.':
      'Apare la o întrerupere de pichetaj sau la rânduri repetate. Se preia primul în ordine.',
  'Приберіть повтори в Excel; розриви пікетажу програма поки не враховує.':
      'Eliminați repetările în Excel; aplicația nu ține încă seama de întreruperile de pichetaj.',
  'ПК відомості не збігаються з віссю': 'PK-urile din tabel nu corespund axei',
  'Відомість: {a}–{b} м, вісь: {c}–{d} м.': 'Tabel: {a}–{b} m, axă: {c}–{d} m.',
  'Перевірте ПК початку осі (екран об’єкта) — він має збігатися з пікетажем відомості.':
      'Verificați PK de început al axei (ecranul proiectului) — trebuie să coincidă cu pichetajul din tabel.',
  'Перевірте колонку ПК: метри чи пікети (12+34 = 1234 м)?':
      'Verificați coloana PK: metri sau pichete de 100 m (12+34 = 1234 m)?',
  'Відомість покриває не всю вісь': 'Tabelul nu acoperă toată axa',
  'Відмітки будуть лише на {a}–{b} м.': 'Cotele vor exista doar pe {a}–{b} m.',
  'Відміток замало — потрібно щонайменше два рядки': 'Prea puține cote — sunt necesare cel puțin două rânduri',
  'Перевірте колонку відмітки й десятковий роздільник.': 'Verificați coloana cotei și separatorul zecimal.',
  'Відомість: {f}': 'Tabel: {f}',
  'Програма вибрала колонки за назвами — перевірте.': 'Aplicația a ales coloanele după denumiri — verificați.',
  '— немає —': '— niciuna —',
  'Відміток: {n}, ПК {a}–{b} м.': 'Cote: {n}, PK {a}–{b} m.',
  'Ширин: {n}.': 'Lățimi: {n}.',
  'Перші рядки файлу:': 'Primele rânduri ale fișierului:',
  'Додати до об’єкта': 'Adaugă la proiect',

  // landxml.dart
  'Файл не схожий на LandXML': 'Fișierul nu pare a fi LandXML',
  'Civil 3D: «Вивід → Експорт у LandXML», позначте вісь і її профіль.':
      'Civil 3D: „Output → Export to LandXML”, bifați axa și profilul ei.',
  'Або збережіть вісь як DXF («Експорт у AutoCAD», потім «Зберегти як DXF»).':
      'Sau salvați axa ca DXF („Export to AutoCAD”, apoi „Save As” DXF).',
  'XML не читається: {e}': 'XML-ul nu poate fi citit: {e}',
  'Кореневий елемент — «{n}».': 'Elementul rădăcină este „{n}”.',
  'Одиниці LandXML — «{u}», а не метри': 'Unitățile LandXML sunt „{u}”, nu metri',
  'Експортуйте LandXML з метричними одиницями (налаштування креслення Civil 3D → Units: Meters).':
      'Exportați LandXML în unități metrice (setările desenului Civil 3D → Units: Meters).',
  'Клотоїда «{n}» не зійшлася з кінцем на {m} м': 'Clotoida „{n}” nu se închide la capăt cu {m} m',
  'Перевірте параметри клотоїди в Civil 3D; ПК на ній може відрізнятися на цю величину.':
      'Verificați parametrii clotoidei în Civil 3D; PK pe ea poate diferi cu această valoare.',
  'Елемент осі «{n}» програма не читає': 'Aplicația nu citește elementul de axă „{n}”',
  'Повідомте розробнику, з якої програми цей LandXML.': 'Comunicați dezvoltatorului din ce program provine acest LandXML.',
  'В осі є розриви пікетажу (StaEquation)': 'Axa are întreruperi de pichetaj (StaEquation)',
  'Програма рахує пікетаж без розривів — після розриву ПК відрізнятиметься.':
      'Aplicația calculează pichetajul fără întreruperi — după o întrerupere PK va diferi.',
  'Розбийте вісь у Civil 3D на ділянки між розривами й додайте їх окремими об’єктами.':
      'Împărțiți axa în Civil 3D în tronsoane între întreruperi și adăugați-le ca proiecte separate.',
  'Вісь {n}': 'Axa {n}',
  'профіль': 'profil',
  'У файлі немає осей (Alignment з CoordGeom).': 'Fișierul nu conține axe (Alignment cu CoordGeom).',
  'У елементі {e} немає точки {tag}.': 'Elementul {e} nu are punctul {tag}.',

  // dxf.dart
  'рядок {n} — «{s}» замість числового коду': 'linia {n} — „{s}” în loc de cod numeric',
  'файл порожній': 'fișierul este gol',
};
