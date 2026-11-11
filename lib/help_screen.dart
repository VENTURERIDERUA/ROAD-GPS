// Довідка: що робить програма, як почати, які файли вона читає — з прикладами (вісь, профіль, поперечники, ЦММ,
// підкладки). Приклади — як є, без перекладу: так виглядає сам файл.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'i18n.dart';

/// Розділ довідки: заголовок, абзаци (пункти — з «• ») і приклади файлів (підпис, текст файлу).
typedef _Part = (String title, List<String> text, List<(String, String)> examples);

List<_Part> _parts() => [
      (
        t('Що робить програма'),
        [
          t('Показує, де ви відносно осі дороги: ПК і зміщення від осі (ліворуч чи праворуч) — за GPS або за точкою, якої торкнулися на карті.'),
          t('• Прив’язка — лише до осі. Інші лінії плану (кромки, бордюри, межа відводу, мережі) — для огляду; біля лінії з попередженням — вібрація й напис.'),
          t('• Відмітка в точці: проєктна — з поперечників чи ЦММ проєкту; земля — з ЦММ зйомки; є обидві — перемикач «Проєкт / Земля»; лише вісь — відмітки немає.'),
          t('• Позначки (дефекти, зауваження; для лабораторії — відбір зразків і випробування) з фото й голосом; на фото — '
              'ПК, зміщення, координати, дата й час; Excel і акт, надсилання поштою чи в месенджер.'),
          t('• Працює без інтернету; карту ділянки варто завантажити заздалегідь («Дані об’єкта» → «Підкладки»).'),
          t('Відмітки — для ознайомлення, не для винесення в натуру.'),
        ],
        const [],
      ),
      (
        t('Як почати'),
        [
          t('1. «Додати» → креслення з віссю (DXF, LandXML) або скан плану (JPG, PNG, PDF).'),
          t('2. Перевірте систему координат і що вісь лягла на карту там, де дорога; ПК початку — з підпису на кресленні або вручну.'),
          t('3. На екрані об’єкта кнопка «Дані об’єкта» (вгорі): профіль, поперечники, ЦММ, PDF поперечників, лінії плану, підкладки.'),
        ],
        const [],
      ),
      (
        t('Вісь і лінії плану'),
        [
          t('• DXF: вісь — полілінія (чи відрізки й дуги) на своєму шарі («AXIS», «Ax», «Вісь»…); блоки розкладаються. Підписи ПК біля осі допомагають визначити ПК початку. Інші шари — лінії плану; що це за лінія, програма визначає за назвою шару, змінюється в «Дані об’єкта» → «Лінії плану».'),
          t('• LandXML: Alignment з CoordGeom (Line, Curve, Spiral); профіль у тому самому файлі — ProfAlign. Координати в LandXML — «північ схід».'),
          t('• Скан плану: прив’язка за 2–3 точками з відомими координатами, далі — обведення осі.'),
          t('• Кілька осей (основна дорога й примикання, з’їзди, дві проїзні частини) — кожна окремим об’єктом: DXF з осями на різних шарах додайте стільки разів, скільки осей, щоразу вибираючи шар; з LandXML — щоразу іншу вісь. На трасі сусідні осі видно сірим пунктиром; за GPS програма сама переходить на ту, до якої ви ближчі (серед об’єктів того самого виду робіт), або торкніться «Поруч вісь …».'),
        ],
        [
          (
            t('LandXML — вісь і профіль'),
            '<LandXML>\n'
                ' <Alignments>\n'
                '  <Alignment name="Axa" staStart="0">\n'
                '   <CoordGeom>\n'
                '    <Line>\n'
                '     <Start>334120.50 589410.20</Start>\n'
                '     <End>334200.10 589460.80</End>\n'
                '    </Line>\n'
                '    <Curve rot="cw" radius="300">\n'
                '     <Start>334200.10 589460.80</Start>\n'
                '     <Center>334039.20 589713.90</Center>\n'
                '     <End>334262.40 589512.30</End>\n'
                '    </Curve>\n'
                '   </CoordGeom>\n'
                '   <Profile>\n'
                '    <ProfAlign name="Linie rosie">\n'
                '     <PVI>0 84.20</PVI>\n'
                '     <PVI>250 83.14</PVI>\n'
                '     <ParaCurve length="100">450 82.80</ParaCurve>\n'
                '     <PVI>853 82.40</PVI>\n'
                '    </ProfAlign>\n'
                '   </Profile>\n'
                '  </Alignment>\n'
                ' </Alignments>\n'
                '</LandXML>',
          ),
        ],
      ),
      (
        t('Поздовжній профіль'),
        [
          t('• Таблиця CSV (відомість): колонки ПК і проєктна відмітка, розділювач «;» чи «,». ПК — «0+025.00» або метри числом; з «;» можна десяткову кому. Колонки програма знаходить за назвами (ПК, Pichet, Station; Відмітка, Cota proiect, Z) — їх можна й вибрати.'),
          t('• LandXML: ProfAlign з точками PVI («ПК відмітка»), вертикальні криві — ParaCurve з довжиною.'),
          t('• Скан чи PDF профілю: дві точки сітки з ПК і відміткою (масштаб), дотик до лінії проєктного профілю; точки з ПК і відміткою з таблиці — опорні, вирівнюють перекошений скан.'),
        ],
        [
          (
            t('CSV — профіль'),
            'ПК;Відмітка проєктна\n'
                '0+000.00;84,20\n'
                '0+025.00;84,09\n'
                '0+050.00;83,99\n'
                '0+075.00;83,88',
          ),
        ],
      ),
      (
        t('Поперечники з відмітками'),
        [
          t('• Таблиця CSV: ПК, зміщення від осі (ліворуч — з мінусом, праворуч — плюс) і проєктна відмітка; рядки з однаковим ПК — один поперечник.'),
          t('• DXF-креслення поперечників: біля кожного — підпис ПК (можна з відміткою осі: «PK 0+025.00 Z ax = 84.09»), вертикаль осі й лінія проєктного профілю на своїх шарах; масштаби — з напису «H 1:100 V 1:10» або вписати.'),
          t('• LandXML: CrossSects / CrossSect sta="ПК" / DesignCrossSectSurf з точками CrossSectPnt «зміщення відмітка».'),
          t('• PDF поперечників: векторний (з AutoCAD, Civil 3D) — дотик до лінії проєктного профілю бере лінію з креслення, а масштаби, вісь і її відмітку — з чисел сітки чи таблиці; скан — лінія йде за кольором (дотик чи перо), масштаб — двома дотиками, відмітка осі — вписати.'),
        ],
        [
          (
            t('CSV — поперечники'),
            'ПК;Зміщення;Відмітка\n'
                '0+000;-10.00;84.28\n'
                '0+000;-5.25;84.07\n'
                '0+000;0.00;84.20\n'
                '0+000;5.25;84.07\n'
                '0+000;10.00;84.28\n'
                '0+025;-10.00;84.17\n'
                '0+025;0.00;84.09\n'
                '0+025;10.00;84.17',
          ),
          (
            t('LandXML — поперечник'),
            '<CrossSects>\n'
                ' <CrossSect sta="25">\n'
                '  <DesignCrossSectSurf name="Proiect">\n'
                '   <CrossSectPnt>-10.00 84.17</CrossSectPnt>\n'
                '   <CrossSectPnt>-5.25 83.96</CrossSectPnt>\n'
                '   <CrossSectPnt>0.00 84.09</CrossSectPnt>\n'
                '   <CrossSectPnt>5.25 83.96</CrossSectPnt>\n'
                '   <CrossSectPnt>10.00 84.17</CrossSectPnt>\n'
                '  </DesignCrossSectSurf>\n'
                ' </CrossSect>\n'
                '</CrossSects>',
          ),
        ],
      ),
      (
        t('ЦММ (поверхня)'),
        [
          t('ЦММ дає відмітку в будь-якій точці. Зберігаючи, виберіть: «Проєкт» чи «Земля (зйомка)».'),
          t('• LandXML: Surface з точками P («північ схід висота») і трикутниками F (номери трьох точок).'),
          t('• DXF з 3D-гранями (3DFACE): Civil 3D — «Витягнути об’єкти з поверхні».'),
          t('• Точки креслення з відмітками (топозйомка: точки, блоки на висоті, 3D-полілінії) — трикутники програма будує сама.'),
          t('• З поперечників з відмітками — програма будує сама.'),
        ],
        [
          (
            t('LandXML — поверхня'),
            '<Surfaces>\n'
                ' <Surface name="Proiect">\n'
                '  <Definition surfType="TIN">\n'
                '   <Pnts>\n'
                '    <P id="1">589410.20 334120.50 84.20</P>\n'
                '    <P id="2">589412.80 334125.10 84.15</P>\n'
                '    <P id="3">589405.60 334123.30 84.11</P>\n'
                '   </Pnts>\n'
                '   <Faces>\n'
                '    <F>1 2 3</F>\n'
                '   </Faces>\n'
                '  </Definition>\n'
                ' </Surface>\n'
                '</Surfaces>',
          ),
        ],
      ),
      (
        t('Підкладки (карта без інтернету, ортофото)'),
        [
          t('• MBTiles чи PMTiles — готові карти; OSM для ділянки об’єкта програма може завантажити сама.'),
          t('• Знімок JPG / PNG з файлом прив’язки (.jgw / .pgw) у тій самій системі координат, що й об’єкт: розмір пікселя по X, два повороти (зазвичай 0), розмір пікселя по Y з мінусом, X і Y середини лівого верхнього пікселя.'),
        ],
        [
          (
            t('.pgw / .jgw — прив’язка знімка'),
            '0.25\n'
                '0.0\n'
                '0.0\n'
                '-0.25\n'
                '334100.125\n'
                '589480.125',
          ),
        ],
      ),
      (
        t('Системи координат'),
        [
          t('Україна, Румунія (Stereo 70), Молдова, Угорщина, Балкани й сусіди — у списку «Змінити» на екрані нового об’єкта. Програма пропонує ті, у межах яких лягає вісь; кілька варіантів — звична річ (у сусідніх зонах ті самі числа): перевірте вісь на карті.'),
        ],
        const [],
      ),
    ];

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const T('Довідка')),
      body: ListView(padding: const EdgeInsets.all(8), children: [
        for (final (i, (title, text, examples)) in _parts().indexed)
          Card(
            child: ExpansionTile(
              initiallyExpanded: i == 0,
              title: Text(title, style: theme.textTheme.titleMedium),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in text) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(p)),
                for (final (label, body) in examples) _Example(label, body),
              ],
            ),
          ),
      ]),
    );
  }
}

/// Приклад файлу: як він виглядає, моноширинним шрифтом, з кнопкою «Копіювати».
class _Example extends StatelessWidget {
  final String label, body;
  const _Example(this.label, this.body);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(t('Приклад: {f}', {'f': label}), style: const TextStyle(fontWeight: FontWeight.w600))),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: body));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Скопійовано'))));
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const T('Копіювати'),
            ),
          ]),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF1F1F1), borderRadius: BorderRadius.circular(6)),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(body, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ),
          ),
        ]),
      );
}
