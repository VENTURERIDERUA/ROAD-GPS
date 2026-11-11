# ROAD-GPS

*Українською — нижче.*

An Android app for people on a road construction site (foremen, site engineers, surveyors, lab staff): **where am I on the road?**

- **Chainage and offset.** It shows the station (PK) and the offset from the road axis at your GPS position, or at a point tapped on the map.
- **Design and ground level.** Where the project data allows, it shows the design level, the ground level, or both with a switch. The levels come from the longitudinal profile, the cross-sections (interpolated between them) and the terrain model.
- **Project data in.** It reads DXF, LandXML and CSV, and cross-sections / profiles from PDF drawings: vector line picking, axis scales read from the sheet numbers, or scans traced by hand. It also reads geo-referenced images, MBTiles and PMTiles. It works with local coordinate systems, Stereo 70 and MOLDREF99 among them.
- **Plan lines.** Lines get roles (edge, curb, right-of-way boundary, utilities…), with an alert when you come close to one.
- **Field notes and lab samples.** Notes and samples are tied to chainage, coordinates, date and time. They hold photos (camera or gallery) with that data stamped on, voice notes and sample numbers. Export goes to Excel, a Word inspection report or a ZIP, and the app sends them by mail or messenger.
- **Offline maps.** OpenStreetMap tiles are cached, and offline areas can be cut from Protomaps builds.
- **Several alignments.** Main road, junctions, ramps: neighbouring alignments are shown, and by GPS the app switches to the closer one.
- **Languages.** Ukrainian, English, Romanian, Spanish, French, Portuguese, German, Polish, Turkish, Russian, Arabic (right to left), Chinese. The newer translations were machine-assisted; corrections are welcome.

**DWG is not read.** Save the drawing as DXF (AutoCAD / Civil 3D "Save As", or the free ODA File Converter).

## Build

You need Flutter (stable channel, 3.47 or later), JDK 17 and the Android SDK.

```bash
flutter pub get
flutter build apk --release
```

Or run `bash tools/build_apk.sh`. It builds one APK for all devices and three smaller per-processor APKs. Android 7.0 (API 24) or newer is required.

Tests: `flutter test`. The `pdfrx` package builds a native PDFium library for the desktop test host, and on Windows that needs the MSVC build tools.

## Support

This is a personal project, shared as is. **Support is not guaranteed.** Issues are read when time allows.

## License

ROAD-GPS is licensed under the GNU General Public License v3.0 or later (`GPL-3.0-or-later`). See [LICENSE](LICENSE).
Third-party packages and their licences are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Copyright © 2026 VENTURERIDERUA

---

# ROAD-GPS (українською)

Програма для Android для людей на будівництві дороги (виконроби, інженери, геодезисти, лабораторія): **де я на трасі?**

- **ПК і зміщення.** Показує ПК+плюс і зміщення від осі там, де ви стоїте (GPS) або де торкнулися карти.
- **Проєктна відмітка й відмітка землі.** Коли проєкт це дає, показує проєктну відмітку, відмітку землі або обидві з перемикачем. Відмітки беруться з поздовжнього профілю, поперечників (з інтерполяцією між ними) і ЦММ.
- **Дані проєкту.** Читає DXF, LandXML, CSV, поперечники й поздовжні профілі з PDF-креслень: торкання векторної лінії, масштаби й вісь — з чисел на аркуші, або обведення скану. Читає й знімки з прив'язкою, MBTiles і PMTiles. Працює з місцевими системами координат, серед них Stereo 70 і MOLDREF99.
- **Лінії плану.** Лініям задаються ролі (кромка, бордюр, межа відводу, комунікації…), з попередженням, коли підходите близько.
- **Позначки й проби лабораторії.** Прив'язані до ПК, координат, дати й часу. Мають кілька фото (камера чи галерея) з цими даними на фото, голосові нотатки й номер проби. Вивантаження — Excel, акт огляду (Word) чи ZIP, надсилання поштою чи в месенджер.
- **Карта без інтернету.** Плитки OpenStreetMap зберігаються, а ділянку карти можна вирізати зі збірки Protomaps.
- **Кілька осей.** Основна дорога, примикання, з'їзди: сусідні осі видно, і за GPS програма переходить на ближчу.
- **Мови.** Українська, англійська, румунська, іспанська, французька, португальська, німецька, польська, турецька, російська, арабська (справа наліво), китайська. Нові переклади зроблено з допомогою ШІ; виправлення вітаються.

**DWG програма не читає.** Збережіть креслення як DXF (AutoCAD / Civil 3D «Зберегти як» або безкоштовний ODA File Converter).

## Збірка

Потрібні Flutter (stable, 3.47 чи новіший), JDK 17 і Android SDK.

```bash
flutter pub get
flutter build apk --release
```

Або `bash tools/build_apk.sh`: один APK для всіх пристроїв і три менші, під процесор. Потрібен Android 7.0 (API 24) чи новіший.

Тести: `flutter test`. Пакет `pdfrx` збирає для тестів на комп'ютері бібліотеку PDFium, і на Windows для цього потрібні інструменти збірки MSVC.

## Підтримка

Особистий проєкт, викладено як є. **Підтримка не гарантується.** Issues читаю, коли є час.

## Ліцензія

ROAD-GPS поширюється за ліцензією GNU General Public License v3.0 або новішої версії (`GPL-3.0-or-later`), текст — у [LICENSE](LICENSE).
Сторонні пакети та їхні ліцензії — у [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

© 2026 VENTURERIDERUA
