// Переклади (група b): ключ — український текст з коду.
const en = <String, String>{
  // object_data_screen.dart — екран «Дані об'єкта»
  'Дані: {name}': 'Data: {name}',
  'Вісь: {a} – {b}, {len} м · {crs} · {file}': 'Axis: {a} – {b}, {len} m · {crs} · {file}',
  'Поздовжній профіль (проєктна відмітка осі)': 'Longitudinal profile (design elevation of the axis)',
  'Немає.': 'None.',
  '{src}: точок {n}, {a} – {b}.': '{src}: {n} points, {a} – {b}.',
  'З відомості (CSV)': 'From schedule (CSV)',
  'З LandXML': 'From LandXML',
  'Прибрати': 'Remove',
  'Ширина проїзної частини': 'Carriageway width',
  'Зберегти': 'Save',
  'PDF поперечників': 'Cross-section PDF',
  '{file}: сторінок {p}, підписаних поперечників {n}.': '{file}: {p} pages, {n} labelled cross-sections.',
  'Додати PDF': 'Add PDF',
  'Підкладки (спільні для всіх об’єктів)': 'Basemaps (shared by all projects)',
  'Карта OSM без інтернету — вирізана з Protomaps для ділянки об’єкта; ортофото чи інша карта — PMTiles, MBTiles (будь-якого розміру) або знімок JPG/PNG з файлом прив’язки (.jgw / .pgw) у системі координат об’єкта. Вибір підкладки — кнопка шарів на екрані об’єкта.':
      'Offline OSM map — cut from Protomaps for the project area; orthophoto or another map — PMTiles, MBTiles (any size) or a JPG/PNG image with a world file (.jgw / .pgw) in the project coordinate system. Choose the basemap with the layers button on the project screen.',
  'OSM без інтернету (Protomaps)': 'Offline OSM (Protomaps)',
  'Додати PMTiles': 'Add PMTiles',
  'Команда для ПК': 'Command for PC',
  'Додати MBTiles': 'Add MBTiles',
  'Додати знімок + прив’язку': 'Add image + world file',
  'Видалити підкладку «{name}»?': 'Delete basemap "{name}"?',
  'Вона зникне з пристрою для всіх об’єктів. Ваш файл на комп’ютері не зміниться.':
      'It will be removed from the device for all projects. Your file on the computer will not change.',
  'Ні': 'No',
  'Видалити': 'Delete',
  'Скасувати': 'Cancel',
  'Додати все одно': 'Add anyway',
  'Закрити': 'Close',
  'Завантажити': 'Download',
  'Підкладка не перетинається з віссю цього об’єкта': 'The basemap does not overlap the axis of this project',
  'Можливо, це підкладка іншої ділянки — тоді все гаразд, вона знадобиться там.':
      'It may be a basemap of another section — then all is fine, it will be used there.',
  'Якщо вона мала лягти сюди — перевірте систему координат знімка й файлу прив’язки.':
      'If it was meant to be here — check the coordinate system of the image and the world file.',
  'Карта OSM для ділянки без інтернету': 'Offline OSM map for the area',
  'Програма візьме зі щоденної збірки Protomaps (дані OpenStreetMap) лише ділянку цього об’єкта з запасом 1 км, наближення до 15 (вулиці, будинки, назви). Потрібен інтернет зараз — далі карта працює без нього. Зазвичай це кілька мегабайт.':
      'The app will take from the daily Protomaps build (OpenStreetMap data) only the area of this project with a 1 km margin, zoom up to 15 (streets, buildings, names). Internet is needed now — after that the map works without it. Usually a few megabytes.',
  'Завантажую карту ділянки…': 'Downloading the area map…',
  'Карту ділянки не вдалося завантажити': 'Could not download the area map',
  'Перевірте інтернет (мобільні дані чи Wi-Fi) і спробуйте ще раз.':
      'Check the internet connection (mobile data or Wi-Fi) and try again.',
  'Або виріжте ділянку на комп’ютері (кнопка «Команда для ПК») і додайте файл .pmtiles.':
      'Or cut the area on a computer ("Command for PC" button) and add the .pmtiles file.',
  'Файл PMTiles': 'PMTiles file',
  'Це не PMTiles, який програма читає': 'This is not a PMTiles file the app can read',
  'Потрібен PMTiles версії 3 — такий робить `pmtiles extract` і Protomaps.':
      'PMTiles version 3 is required — produced by `pmtiles extract` and Protomaps.',
  'Файл PMTiles не відкрився': 'The PMTiles file did not open',
  'Перевірте, що файл цілий (перекопіюйте його) і що на пристрої досить місця.':
      'Check that the file is complete (copy it again) and that the device has enough space.',
  'pmtiles extract https://build.protomaps.com/РРРРММДД.pmtiles ділянка.pmtiles --bbox={bbox} --maxzoom=15':
      'pmtiles extract https://build.protomaps.com/YYYYMMDD.pmtiles area.pmtiles --bbox={bbox} --maxzoom=15',
  'Вирізати карту на комп’ютері': 'Cut the map on a computer',
  '1. Завантажте pmtiles для Windows: github.com/protomaps/go-pmtiles/releases (файл pmtiles.exe).':
      '1. Download pmtiles for Windows: github.com/protomaps/go-pmtiles/releases (file pmtiles.exe).',
  '2. Дату збірки (РРРРММДД) візьміть на maps.protomaps.com/builds — найсвіжішу.':
      '2. Take the build date (YYYYMMDD) from maps.protomaps.com/builds — the latest one.',
  '3. Виконайте в командному рядку:': '3. Run in the command prompt:',
  '4. Перенесіть ділянка.pmtiles на пристрій і додайте кнопкою «Додати PMTiles».':
      '4. Copy area.pmtiles to the device and add it with the "Add PMTiles" button.',
  'Скопіювати команду': 'Copy command',
  'MBTiles у браузері не відкриваються': 'MBTiles cannot be opened in the browser',
  'Це перевірочна версія на комп’ютері; на планшеті MBTiles працюють.':
      'This is a test version on a computer; MBTiles work on the tablet.',
  'Файл MBTiles': 'MBTiles file',
  'MBTiles не додався': 'MBTiles was not added',
  'Перевірте, що на пристрої досить місця, і спробуйте ще раз.':
      'Check that the device has enough space and try again.',
  'Знімок (JPG/PNG) разом з файлом прив’язки': 'Image (JPG/PNG) together with its world file',
  'Знімок не додався': 'The image was not added',
  'Перевірте, що це звичайний JPG чи PNG і що він відкривається на комп’ютері.':
      'Check that it is a regular JPG or PNG and that it opens on a computer.',
  'Виберіть файл ({ext})': 'Choose a file ({ext})',
  'Не вдалося відкрити «{name}»': 'Could not open "{name}"',
  'Збережіть файл у пам’ять пристрою (Завантаження) і виберіть ще раз.':
      'Save the file to the device storage (Downloads) and choose it again.',
  'Потрібна відомість у форматі CSV': 'A schedule in CSV format is required',
  'Excel: «Файл → Зберегти як» → «CSV UTF-8 (розділювач — кома)» або «CSV (розділювач — крапка з комою)».':
      'Excel: "File → Save As" → "CSV UTF-8 (comma delimited)" or "CSV (semicolon delimited)".',
  'Колонки: ПК (наприклад 0+025.00 або метри), проєктна відмітка, за бажанням — ширина чи напівширина.':
      'Columns: PK (e.g. 0+025.00 or metres), design elevation, optionally — width or half-width.',
  'Потрібен файл LandXML (.xml)': 'A LandXML file (.xml) is required',
  'Civil 3D: «Вивід → Експорт у LandXML», позначте вісь і її профіль.':
      'Civil 3D: "Output → Export to LandXML", select the alignment and its profile.',
  'Вісь у LandXML не збігається з віссю об’єкта': 'The axis in LandXML does not match the project axis',
  'Початок осі «{name}» ({a}) лежить на {b} об’єкта, за {off} м від осі.':
      'The start of axis "{name}" ({a}) lies at {b} of the project, {off} m from the axis.',
  'Перевірте, що це LandXML саме цієї дороги й ділянки.': 'Check that this LandXML is for this very road and section.',
  'Перевірте ПК початку осі об’єкта — він має збігатися з пікетажем Civil 3D.':
      'Check the start PK of the project axis — it must match the Civil 3D chainage.',
  'Потрібен PDF з поперечниками': 'A PDF with cross-sections is required',
  'Виберіть PDF-аркуші поперечних профілів, де кожен підписаний «PK 0+025.00» чи «ПК 12+34».':
      'Choose PDF sheets of cross-sections, each labelled "PK 0+025.00" or "ПК 12+34".',
  'У PDF не знайдено підписів ПК': 'No PK labels found in the PDF',
  'Програма шукає на сторінках текст виду «PK 0+025.00», «ПК 12+34», «км 1+200».':
      'The app looks on the pages for text like "PK 0+025.00", "ПК 12+34", "км 1+200".',
  'Якщо PDF — скан (картинка), тексту в ньому немає: потрібен векторний PDF, «надрукований» з AutoCAD / Civil 3D.':
      'If the PDF is a scan (a picture), it contains no text: a vector PDF "printed" from AutoCAD / Civil 3D is needed.',
  'Векторизація сканів — етап 7, ще не зроблено.': 'Vectorising scans is stage 7, not done yet.',
  'ПК у PDF не збігаються з віссю': 'PKs in the PDF do not match the axis',
  'Знайдено {n} підписів, але жоден не в межах осі ({a} – {b}).':
      'Found {n} labels, but none is within the axis ({a} – {b}).',
  'Перевірте, що PDF від цієї ділянки, і ПК початку осі об’єкта.':
      'Check that the PDF is for this section, and check the start PK of the project axis.',
  'PDF не відкрився': 'The PDF did not open',
  'Перевірте, що PDF відкривається на комп’ютері й не захищений паролем.':
      'Check that the PDF opens on a computer and is not password-protected.',

  // basemaps.dart — підкладки
  'Це не MBTiles з растровими плитками': 'This is not an MBTiles file with raster tiles',
  'QGIS: «Обробка → Інструменти → Растрові інструменти → Створити XYZ-плитки (MBTiles)» з ортофото.':
      'QGIS: "Processing → Toolbox → Raster tools → Generate XYZ tiles (MBTiles)" from the orthophoto.',
  'Або GDAL: gdal_translate -of MBTILES ортофото.tif ортофото.mbtiles, потім gdaladdo -r average ортофото.mbtiles 2 4 8 16.':
      'Or GDAL: gdal_translate -of MBTILES orthophoto.tif orthophoto.mbtiles, then gdaladdo -r average orthophoto.mbtiles 2 4 8 16.',
  'Це векторні MBTiles — програма показує лише растрові': 'These are vector MBTiles — the app shows raster ones only',
  'Наріжте растрові плитки (PNG чи JPG) з ортофото чи карти в QGIS: «Створити XYZ-плитки (MBTiles)».':
      'Cut raster tiles (PNG or JPG) from the orthophoto or map in QGIS: "Generate XYZ tiles (MBTiles)".',
  'У MBTiles немає жодної плитки': 'The MBTiles file has no tiles',
  'Перевірте діапазон наближень під час нарізки (наприклад 14–20).':
      'Check the zoom range used when cutting the tiles (e.g. 14–20).',
  'Потрібен файл .mbtiles': 'An .mbtiles file is required',
  'Ортофото (GeoTIFF) наріжте в MBTiles: QGIS «Створити XYZ-плитки (MBTiles)» або gdal_translate -of MBTILES.':
      'Cut the orthophoto (GeoTIFF) into MBTiles: QGIS "Generate XYZ tiles (MBTiles)" or gdal_translate -of MBTILES.',
  'Потрібен файл .pmtiles': 'A .pmtiles file is required',
  'Виріжте ділянку командою pmtiles extract (кнопка «Команда для ПК») або завантажте карту ділянки кнопкою «OSM без інтернету».':
      'Cut the area with the pmtiles extract command ("Command for PC" button) or download the area map with the "Offline OSM" button.',
  'GeoTIFF програма напряму не показує': 'The app cannot show GeoTIFF directly',
  'Ортофото з дрона зазвичай — гігабайти; без нарізки на плитки воно не вміститься в пам’ять планшета.':
      'A drone orthophoto is usually gigabytes; without cutting it into tiles it will not fit into the tablet memory.',
  'QGIS: «Обробка → Інструменти → Растрові інструменти → Створити XYZ-плитки (MBTiles)», наближення 14–21, потім «Додати MBTiles».':
      'QGIS: "Processing → Toolbox → Raster tools → Generate XYZ tiles (MBTiles)", zoom 14–21, then "Add MBTiles".',
  'Або GDAL: gdal_translate -of MBTILES орто.tif орто.mbtiles, потім gdaladdo -r average орто.mbtiles 2 4 8 16 32.':
      'Or GDAL: gdal_translate -of MBTILES ortho.tif ortho.mbtiles, then gdaladdo -r average ortho.mbtiles 2 4 8 16 32.',
  'Невеликий знімок: QGIS «Растр → Перетворення → Перетворити» у JPEG з параметром WORLDFILE=YES — і «Додати знімок + прив’язку».':
      'Small image: QGIS "Raster → Conversion → Translate" to JPEG with WORLDFILE=YES — then "Add image + world file".',
  'Знімок не схожий на PNG чи JPEG': 'The image does not look like PNG or JPEG',
  'Збережіть знімок як PNG або JPEG (QGIS: «Растр → Перетворення → Перетворити»).':
      'Save the image as PNG or JPEG (QGIS: "Raster → Conversion → Translate").',
  'Потрібні два файли: знімок і файл прив’язки': 'Two files are needed: the image and its world file',
  'Файл прив’язки (.jgw для JPG, .pgw для PNG) каже, де знімок лежить у координатах.':
      'The world file (.jgw for JPG, .pgw for PNG) tells where the image lies in coordinates.',
  'Виберіть обидва файли разом (довгий дотик — вибрати кілька).':
      'Select both files together (long press — select several).',
  'Немає файлу прив’язки — експортуйте знімок з QGIS з параметром WORLDFILE=YES у системі координат об’єкта.':
      'No world file — export the image from QGIS with WORLDFILE=YES in the project coordinate system.',
  'Невідомий вид плиток у PMTiles': 'Unknown tile type in PMTiles',
  'Підходять векторні плитки (як у Protomaps) або растрові PNG / JPEG / WebP.':
      'Vector tiles (as in Protomaps) or raster PNG / JPEG / WebP are supported.',
  'Плитки в PMTiles стиснені способом, якого програма не знає':
      'The tiles in PMTiles use a compression the app does not know',
  'Вирізайте ділянку з Protomaps (там gzip) або зберігайте PMTiles без стиснення плиток.':
      'Cut the area from Protomaps (gzip there) or save PMTiles without tile compression.',
  'Файл прив’язки не читається': 'The world file cannot be read',
  'Очікується 6 чисел, по одному в рядку.': '6 numbers are expected, one per line.',
  'Створіть його заново під час експорту знімка (QGIS: параметр WORLDFILE=YES).':
      'Create it again when exporting the image (QGIS: WORLDFILE=YES).',
  'Знімок завеликий для пристрою: {n} млн пікселів': 'The image is too large for the device: {n} million pixels',
  'Без нарізки на плитки такий знімок не вміститься в пам’ять планшета.':
      'Without cutting into tiles such an image will not fit into the tablet memory.',
  'Наріжте його в MBTiles: QGIS «Створити XYZ-плитки (MBTiles)» або gdal_translate -of MBTILES.':
      'Cut it into MBTiles: QGIS "Generate XYZ tiles (MBTiles)" or gdal_translate -of MBTILES.',
  'Або експортуйте менший (з більшим пікселем) — до {n} млн пікселів.':
      'Or export a smaller one (with a larger pixel) — up to {n} million pixels.',
  'Знімок не потрапляє в межі країни системи «{name}»': 'The image is outside the country of the "{name}" system',
  'Перевірте, що файл прив’язки зроблено в тій самій системі координат, що й вісь об’єкта.':
      'Check that the world file is in the same coordinate system as the project axis.',
  'Знімок у WGS84 / UTM чи іншій системі — перепроєктуйте його в QGIS у систему об’єкта.':
      'Image in WGS84 / UTM or another system — reproject it in QGIS to the project system.',

  // pmtiles.dart, osm_offline.dart — тексти помилок (показуються в «подробицях»)
  'не PMTiles': 'not PMTiles',
  'версія PMTiles {n}, програма читає 3': 'PMTiles version {n}, the app reads 3',
  'каталог обірвано': 'directory is truncated',
  'сайт відповів {code}': 'server responded {code}',
  'список збірок недоступний ({code})': 'build list unavailable ({code})',
  'для цієї ділянки в архіві немає плиток': 'the archive has no tiles for this area',

  // pdf_section_screen.dart
  'Поперечник {pk}': 'Cross-section {pk}',
  'Попередній поперечник': 'Previous cross-section',
  'Наступний поперечник': 'Next cross-section',
};

const ro = <String, String>{
  // object_data_screen.dart — екран «Дані об'єкта»
  'Дані: {name}': 'Date: {name}',
  'Вісь: {a} – {b}, {len} м · {crs} · {file}': 'Axă: {a} – {b}, {len} m · {crs} · {file}',
  'Поздовжній профіль (проєктна відмітка осі)': 'Profil longitudinal (cota proiectată a axei)',
  'Немає.': 'Nu există.',
  '{src}: точок {n}, {a} – {b}.': '{src}: {n} puncte, {a} – {b}.',
  'З відомості (CSV)': 'Din tabel (CSV)',
  'З LandXML': 'Din LandXML',
  'Прибрати': 'Elimină',
  'Ширина проїзної частини': 'Lățimea părții carosabile',
  'Зберегти': 'Salvează',
  'PDF поперечників': 'PDF cu profiluri transversale',
  '{file}: сторінок {p}, підписаних поперечників {n}.': '{file}: {p} pagini, {n} profiluri transversale etichetate.',
  'Додати PDF': 'Adaugă PDF',
  'Підкладки (спільні для всіх об’єктів)': 'Hărți de fundal (comune pentru toate proiectele)',
  'Карта OSM без інтернету — вирізана з Protomaps для ділянки об’єкта; ортофото чи інша карта — PMTiles, MBTiles (будь-якого розміру) або знімок JPG/PNG з файлом прив’язки (.jgw / .pgw) у системі координат об’єкта. Вибір підкладки — кнопка шарів на екрані об’єкта.':
      'Hartă OSM fără internet — decupată din Protomaps pentru zona proiectului; ortofoto sau altă hartă — PMTiles, MBTiles (de orice mărime) sau imagine JPG/PNG cu fișier de georeferențiere (.jgw / .pgw) în sistemul de coordonate al proiectului. Harta de fundal se alege cu butonul de straturi de pe ecranul proiectului.',
  'OSM без інтернету (Protomaps)': 'OSM fără internet (Protomaps)',
  'Додати PMTiles': 'Adaugă PMTiles',
  'Команда для ПК': 'Comandă pentru PC',
  'Додати MBTiles': 'Adaugă MBTiles',
  'Додати знімок + прив’язку': 'Adaugă imagine + georeferențiere',
  'Видалити підкладку «{name}»?': 'Ștergeți harta de fundal „{name}”?',
  'Вона зникне з пристрою для всіх об’єктів. Ваш файл на комп’ютері не зміниться.':
      'Va dispărea de pe dispozitiv pentru toate proiectele. Fișierul de pe calculator nu se va modifica.',
  'Ні': 'Nu',
  'Видалити': 'Șterge',
  'Скасувати': 'Anulează',
  'Додати все одно': 'Adaugă oricum',
  'Закрити': 'Închide',
  'Завантажити': 'Descarcă',
  'Підкладка не перетинається з віссю цього об’єкта': 'Harta de fundal nu se suprapune cu axa acestui proiect',
  'Можливо, це підкладка іншої ділянки — тоді все гаразд, вона знадобиться там.':
      'Poate este harta de fundal a altui tronson — atunci e în regulă, va fi folosită acolo.',
  'Якщо вона мала лягти сюди — перевірте систему координат знімка й файлу прив’язки.':
      'Dacă trebuia să fie aici — verificați sistemul de coordonate al imaginii și al fișierului de georeferențiere.',
  'Карта OSM для ділянки без інтернету': 'Hartă OSM a zonei fără internet',
  'Програма візьме зі щоденної збірки Protomaps (дані OpenStreetMap) лише ділянку цього об’єкта з запасом 1 км, наближення до 15 (вулиці, будинки, назви). Потрібен інтернет зараз — далі карта працює без нього. Зазвичай це кілька мегабайт.':
      'Aplicația va lua din versiunea zilnică Protomaps (date OpenStreetMap) doar zona acestui proiect, cu o margine de 1 km, zoom până la 15 (străzi, clădiri, denumiri). Internetul este necesar acum — apoi harta funcționează fără el. De obicei câțiva megaocteți.',
  'Завантажую карту ділянки…': 'Se descarcă harta zonei…',
  'Карту ділянки не вдалося завантажити': 'Harta zonei nu a putut fi descărcată',
  'Перевірте інтернет (мобільні дані чи Wi-Fi) і спробуйте ще раз.':
      'Verificați internetul (date mobile sau Wi-Fi) și încercați din nou.',
  'Або виріжте ділянку на комп’ютері (кнопка «Команда для ПК») і додайте файл .pmtiles.':
      'Sau decupați zona pe calculator (butonul „Comandă pentru PC”) și adăugați fișierul .pmtiles.',
  'Файл PMTiles': 'Fișier PMTiles',
  'Це не PMTiles, який програма читає': 'Nu este un PMTiles pe care aplicația îl poate citi',
  'Потрібен PMTiles версії 3 — такий робить `pmtiles extract` і Protomaps.':
      'Este necesar PMTiles versiunea 3 — așa cum îl produc `pmtiles extract` și Protomaps.',
  'Файл PMTiles не відкрився': 'Fișierul PMTiles nu s-a deschis',
  'Перевірте, що файл цілий (перекопіюйте його) і що на пристрої досить місця.':
      'Verificați că fișierul este întreg (copiați-l din nou) și că dispozitivul are spațiu suficient.',
  'pmtiles extract https://build.protomaps.com/РРРРММДД.pmtiles ділянка.pmtiles --bbox={bbox} --maxzoom=15':
      'pmtiles extract https://build.protomaps.com/AAAALLZZ.pmtiles zona.pmtiles --bbox={bbox} --maxzoom=15',
  'Вирізати карту на комп’ютері': 'Decupați harta pe calculator',
  '1. Завантажте pmtiles для Windows: github.com/protomaps/go-pmtiles/releases (файл pmtiles.exe).':
      '1. Descărcați pmtiles pentru Windows: github.com/protomaps/go-pmtiles/releases (fișierul pmtiles.exe).',
  '2. Дату збірки (РРРРММДД) візьміть на maps.protomaps.com/builds — найсвіжішу.':
      '2. Luați data versiunii (AAAALLZZ) de pe maps.protomaps.com/builds — cea mai recentă.',
  '3. Виконайте в командному рядку:': '3. Rulați în linia de comandă:',
  '4. Перенесіть ділянка.pmtiles на пристрій і додайте кнопкою «Додати PMTiles».':
      '4. Copiați zona.pmtiles pe dispozitiv și adăugați-l cu butonul „Adaugă PMTiles”.',
  'Скопіювати команду': 'Copiază comanda',
  'MBTiles у браузері не відкриваються': 'MBTiles nu se deschid în browser',
  'Це перевірочна версія на комп’ютері; на планшеті MBTiles працюють.':
      'Aceasta este versiunea de test pe calculator; pe tabletă MBTiles funcționează.',
  'Файл MBTiles': 'Fișier MBTiles',
  'MBTiles не додався': 'MBTiles nu a fost adăugat',
  'Перевірте, що на пристрої досить місця, і спробуйте ще раз.':
      'Verificați că dispozitivul are spațiu suficient și încercați din nou.',
  'Знімок (JPG/PNG) разом з файлом прив’язки': 'Imagine (JPG/PNG) împreună cu fișierul de georeferențiere',
  'Знімок не додався': 'Imaginea nu a fost adăugată',
  'Перевірте, що це звичайний JPG чи PNG і що він відкривається на комп’ютері.':
      'Verificați că este un JPG sau PNG obișnuit și că se deschide pe calculator.',
  'Виберіть файл ({ext})': 'Alegeți fișierul ({ext})',
  'Не вдалося відкрити «{name}»': 'Nu s-a putut deschide „{name}”',
  'Збережіть файл у пам’ять пристрою (Завантаження) і виберіть ще раз.':
      'Salvați fișierul în memoria dispozitivului (Descărcări) și alegeți-l din nou.',
  'Потрібна відомість у форматі CSV': 'Este necesar un tabel în format CSV',
  'Excel: «Файл → Зберегти як» → «CSV UTF-8 (розділювач — кома)» або «CSV (розділювач — крапка з комою)».':
      'Excel: „Fișier → Salvare ca” → „CSV UTF-8 (separator — virgulă)” sau „CSV (separator — punct și virgulă)”.',
  'Колонки: ПК (наприклад 0+025.00 або метри), проєктна відмітка, за бажанням — ширина чи напівширина.':
      'Coloane: PK (de exemplu 0+025.00 sau metri), cota proiectată, opțional — lățimea sau semilățimea.',
  'Потрібен файл LandXML (.xml)': 'Este necesar un fișier LandXML (.xml)',
  'Civil 3D: «Вивід → Експорт у LandXML», позначте вісь і її профіль.':
      'Civil 3D: „Output → Export to LandXML”, selectați axa și profilul ei.',
  'Вісь у LandXML не збігається з віссю об’єкта': 'Axa din LandXML nu coincide cu axa proiectului',
  'Початок осі «{name}» ({a}) лежить на {b} об’єкта, за {off} м від осі.':
      'Începutul axei „{name}” ({a}) se află la {b} din proiect, la {off} m de axă.',
  'Перевірте, що це LandXML саме цієї дороги й ділянки.':
      'Verificați că acest LandXML este chiar al acestui drum și tronson.',
  'Перевірте ПК початку осі об’єкта — він має збігатися з пікетажем Civil 3D.':
      'Verificați PK-ul de început al axei proiectului — trebuie să coincidă cu pichetajul din Civil 3D.',
  'Потрібен PDF з поперечниками': 'Este necesar un PDF cu profiluri transversale',
  'Виберіть PDF-аркуші поперечних профілів, де кожен підписаний «PK 0+025.00» чи «ПК 12+34».':
      'Alegeți planșele PDF cu profiluri transversale, fiecare etichetat „PK 0+025.00” sau „ПК 12+34”.',
  'У PDF не знайдено підписів ПК': 'În PDF nu s-au găsit etichete PK',
  'Програма шукає на сторінках текст виду «PK 0+025.00», «ПК 12+34», «км 1+200».':
      'Aplicația caută pe pagini text de forma „PK 0+025.00”, „ПК 12+34”, „км 1+200”.',
  'Якщо PDF — скан (картинка), тексту в ньому немає: потрібен векторний PDF, «надрукований» з AutoCAD / Civil 3D.':
      'Dacă PDF-ul este o scanare (imagine), nu conține text: este necesar un PDF vectorial „tipărit” din AutoCAD / Civil 3D.',
  'Векторизація сканів — етап 7, ще не зроблено.': 'Vectorizarea scanărilor — etapa 7, încă nerealizată.',
  'ПК у PDF не збігаються з віссю': 'PK-urile din PDF nu corespund axei',
  'Знайдено {n} підписів, але жоден не в межах осі ({a} – {b}).':
      'S-au găsit {n} etichete, dar niciuna nu se află în limitele axei ({a} – {b}).',
  'Перевірте, що PDF від цієї ділянки, і ПК початку осі об’єкта.':
      'Verificați că PDF-ul este al acestui tronson, precum și PK-ul de început al axei proiectului.',
  'PDF не відкрився': 'PDF-ul nu s-a deschis',
  'Перевірте, що PDF відкривається на комп’ютері й не захищений паролем.':
      'Verificați că PDF-ul se deschide pe calculator și nu este protejat cu parolă.',

  // basemaps.dart — підкладки
  'Це не MBTiles з растровими плитками': 'Nu este un MBTiles cu dale raster',
  'QGIS: «Обробка → Інструменти → Растрові інструменти → Створити XYZ-плитки (MBTiles)» з ортофото.':
      'QGIS: „Processing → Toolbox → Raster tools → Generate XYZ tiles (MBTiles)” din ortofoto.',
  'Або GDAL: gdal_translate -of MBTILES ортофото.tif ортофото.mbtiles, потім gdaladdo -r average ортофото.mbtiles 2 4 8 16.':
      'Sau GDAL: gdal_translate -of MBTILES ortofoto.tif ortofoto.mbtiles, apoi gdaladdo -r average ortofoto.mbtiles 2 4 8 16.',
  'Це векторні MBTiles — програма показує лише растрові': 'Acestea sunt MBTiles vectoriale — aplicația afișează doar raster',
  'Наріжте растрові плитки (PNG чи JPG) з ортофото чи карти в QGIS: «Створити XYZ-плитки (MBTiles)».':
      'Generați dale raster (PNG sau JPG) din ortofoto sau hartă în QGIS: „Generate XYZ tiles (MBTiles)”.',
  'У MBTiles немає жодної плитки': 'Fișierul MBTiles nu conține nicio dală',
  'Перевірте діапазон наближень під час нарізки (наприклад 14–20).':
      'Verificați intervalul de zoom folosit la generare (de exemplu 14–20).',
  'Потрібен файл .mbtiles': 'Este necesar un fișier .mbtiles',
  'Ортофото (GeoTIFF) наріжте в MBTiles: QGIS «Створити XYZ-плитки (MBTiles)» або gdal_translate -of MBTILES.':
      'Transformați ortofoto (GeoTIFF) în MBTiles: QGIS „Generate XYZ tiles (MBTiles)” sau gdal_translate -of MBTILES.',
  'Потрібен файл .pmtiles': 'Este necesar un fișier .pmtiles',
  'Виріжте ділянку командою pmtiles extract (кнопка «Команда для ПК») або завантажте карту ділянки кнопкою «OSM без інтернету».':
      'Decupați zona cu comanda pmtiles extract (butonul „Comandă pentru PC”) sau descărcați harta zonei cu butonul „OSM fără internet”.',
  'GeoTIFF програма напряму не показує': 'Aplicația nu afișează direct GeoTIFF',
  'Ортофото з дрона зазвичай — гігабайти; без нарізки на плитки воно не вміститься в пам’ять планшета.':
      'Un ortofoto din dronă are de obicei gigaocteți; fără împărțire în dale nu încape în memoria tabletei.',
  'QGIS: «Обробка → Інструменти → Растрові інструменти → Створити XYZ-плитки (MBTiles)», наближення 14–21, потім «Додати MBTiles».':
      'QGIS: „Processing → Toolbox → Raster tools → Generate XYZ tiles (MBTiles)”, zoom 14–21, apoi „Adaugă MBTiles”.',
  'Або GDAL: gdal_translate -of MBTILES орто.tif орто.mbtiles, потім gdaladdo -r average орто.mbtiles 2 4 8 16 32.':
      'Sau GDAL: gdal_translate -of MBTILES orto.tif orto.mbtiles, apoi gdaladdo -r average orto.mbtiles 2 4 8 16 32.',
  'Невеликий знімок: QGIS «Растр → Перетворення → Перетворити» у JPEG з параметром WORLDFILE=YES — і «Додати знімок + прив’язку».':
      'Imagine mică: QGIS „Raster → Conversion → Translate” în JPEG cu parametrul WORLDFILE=YES — apoi „Adaugă imagine + georeferențiere”.',
  'Знімок не схожий на PNG чи JPEG': 'Imaginea nu pare a fi PNG sau JPEG',
  'Збережіть знімок як PNG або JPEG (QGIS: «Растр → Перетворення → Перетворити»).':
      'Salvați imaginea ca PNG sau JPEG (QGIS: „Raster → Conversion → Translate”).',
  'Потрібні два файли: знімок і файл прив’язки': 'Sunt necesare două fișiere: imaginea și fișierul de georeferențiere',
  'Файл прив’язки (.jgw для JPG, .pgw для PNG) каже, де знімок лежить у координатах.':
      'Fișierul de georeferențiere (.jgw pentru JPG, .pgw pentru PNG) arată unde se află imaginea în coordonate.',
  'Виберіть обидва файли разом (довгий дотик — вибрати кілька).':
      'Selectați ambele fișiere împreună (apăsare lungă — selectare multiplă).',
  'Немає файлу прив’язки — експортуйте знімок з QGIS з параметром WORLDFILE=YES у системі координат об’єкта.':
      'Lipsește fișierul de georeferențiere — exportați imaginea din QGIS cu parametrul WORLDFILE=YES în sistemul de coordonate al proiectului.',
  'Невідомий вид плиток у PMTiles': 'Tip de dale necunoscut în PMTiles',
  'Підходять векторні плитки (як у Protomaps) або растрові PNG / JPEG / WebP.':
      'Sunt acceptate dale vectoriale (ca în Protomaps) sau raster PNG / JPEG / WebP.',
  'Плитки в PMTiles стиснені способом, якого програма не знає':
      'Dalele din PMTiles sunt comprimate printr-o metodă pe care aplicația nu o cunoaște',
  'Вирізайте ділянку з Protomaps (там gzip) або зберігайте PMTiles без стиснення плиток.':
      'Decupați zona din Protomaps (acolo e gzip) sau salvați PMTiles fără comprimarea dalelor.',
  'Файл прив’язки не читається': 'Fișierul de georeferențiere nu poate fi citit',
  'Очікується 6 чисел, по одному в рядку.': 'Se așteaptă 6 numere, câte unul pe rând.',
  'Створіть його заново під час експорту знімка (QGIS: параметр WORLDFILE=YES).':
      'Creați-l din nou la exportul imaginii (QGIS: parametrul WORLDFILE=YES).',
  'Знімок завеликий для пристрою: {n} млн пікселів': 'Imaginea este prea mare pentru dispozitiv: {n} milioane de pixeli',
  'Без нарізки на плитки такий знімок не вміститься в пам’ять планшета.':
      'Fără împărțire în dale, o astfel de imagine nu încape în memoria tabletei.',
  'Наріжте його в MBTiles: QGIS «Створити XYZ-плитки (MBTiles)» або gdal_translate -of MBTILES.':
      'Transformați-o în MBTiles: QGIS „Generate XYZ tiles (MBTiles)” sau gdal_translate -of MBTILES.',
  'Або експортуйте менший (з більшим пікселем) — до {n} млн пікселів.':
      'Sau exportați una mai mică (cu pixel mai mare) — până la {n} milioane de pixeli.',
  'Знімок не потрапляє в межі країни системи «{name}»': 'Imaginea nu se află în țara sistemului „{name}”',
  'Перевірте, що файл прив’язки зроблено в тій самій системі координат, що й вісь об’єкта.':
      'Verificați că fișierul de georeferențiere este în același sistem de coordonate ca axa proiectului.',
  'Знімок у WGS84 / UTM чи іншій системі — перепроєктуйте його в QGIS у систему об’єкта.':
      'Imagine în WGS84 / UTM sau alt sistem — reproiectați-o în QGIS în sistemul proiectului.',

  // pmtiles.dart, osm_offline.dart — тексти помилок (показуються в «подробицях»)
  'не PMTiles': 'nu este PMTiles',
  'версія PMTiles {n}, програма читає 3': 'PMTiles versiunea {n}, aplicația citește 3',
  'каталог обірвано': 'directorul este trunchiat',
  'сайт відповів {code}': 'serverul a răspuns {code}',
  'список збірок недоступний ({code})': 'lista versiunilor indisponibilă ({code})',
  'для цієї ділянки в архіві немає плиток': 'arhiva nu are dale pentru această zonă',

  // pdf_section_screen.dart
  'Поперечник {pk}': 'Profil transversal {pk}',
  'Попередній поперечник': 'Profilul transversal anterior',
  'Наступний поперечник': 'Profilul transversal următor',
};
