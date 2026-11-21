# Что нового / What's new

Русский · [English](#english)

## Русский

### Версия 6.0 — 2026-11-20

**Программа переименована в StartForMac** (`StartForMac.app`: имя в меню, «О программе», Dock и сообщениях). После копирования новой версии в папку «Программы» старую «Пуск» нужно удалить. Настройки, разрешения и список сайтов сохраняются: идентификатор программы прежний. Автозапуск при входе обновляется сам, значок в Dock нужно закрепить заново.

**Новое**
- **Умный буфер обмена:** история последних копирований — текст, картинки и файлы, на 3, 5 или 10 записей (выбор в настройках). Открывается по ⇧⌘V списком у курсора (стрелки или цифры, Enter вставляет, P закрепляет, ⌫ убирает) и значком буфера на верхней панели «Пуска» (клик копирует запись). Закреплённые записи не вытесняются и не считаются в лимите. Пароли не сохраняются: пропускаются скрытые копии и программы-менеджеры паролей; история только в памяти и исчезает при выходе. Включается в Настройках → «Система» (по умолчанию выключено); при включении запрашивается доступ «Универсальный доступ» для автоматической вставки.
- Меню «Инструменты» сдвинуто вправо: его левый край на уровне рамки быстрых вызовов.
- **Калькулятор** убран из «Инструментов» и вынесен на верхнюю панель — значок справа от чашки.
- **Настройки:** выключатели выровнены по правому краю, две нижние кнопки одинаковой ширины и по центру окна.
- **UnRar** (Инструменты): распаковка архивов — RAR и RAR5, 7z, ZIP (в т. ч. с шифрованием), TAR, GZ, BZ2, XZ, ISO, DMG, CAB, ARJ, LZH, WIM и другие. Поддерживаются пароль (если архив защищён, в строке появляется поле для пароля, при неверном — повторный ввод) и многотомные архивы: можно выбрать любой том (.part2.rar, .r01, .7z.002 …) — распаковка начнётся с первого. Архивы добавляются кнопкой или перетаскиванием, распаковываются по очереди с индикатором; результат — рядом с архивом (в папку с его именем) или в выбранную папку. Движок — консольный 7-Zip: берётся из системы, а если его нет, скачивается при первом открытии.
- **Дубликаты и похожие фото** (Инструменты): точные дубликаты ищутся по содержимому (SHA-256), похожие снимки — по уменьшенному «отпечатку» картинки; жёсткие ссылки не считаются копиями. Отмечаете лишнее вручную или кнопкой «Выбрать лишние» (у дубликатов остаётся самая старая копия, у фото — с наибольшим разрешением), в каждой группе всегда остаётся хотя бы одна копия; в Корзину уходит только отмеченное. Папку можно выбрать или перетащить в окно, у файла есть предпросмотр Quick Look.
- **Анализатор диска:** коллектор (значок лотка у объекта или перетаскивание вниз — собрать лишнее и убрать в Корзину одним действием, с суммой освобождаемого места), анализ любой папки или диска («Выбрать папку…» или перетаскивание папки в окно), предпросмотр файла стандартной утилитой macOS (Quick Look, значок глаза); при наведении на сектор диаграммы в центре показываются имя, размер и доля.
- **Переключение окон по ⌥Tab:** для тех, кто пришёл с Windows — переключает фокус между отдельными окнами, а не приложениями целиком, и показывает их миниатюры. Пока Option зажат: Tab / ⇧Tab или стрелки — выбор, Esc — отмена, щелчок мышью — выбрать. Включается в Настройках → «Система» (по умолчанию выключено; миниатюры — отдельным переключателем, по умолчанию выключены, нужен доступ «Запись экрана и системного звука»).
- **⌘X в Finder:** «вырезать» файлы — ⌘X копирует выделенное и помечает как вырезанное, следующая вставка ⌘V перемещает файлы; справа внизу на пару секунд выезжает небольшая плашка «Вырезано» (в цветах текущей темы). Включается в Настройках → «Система» (по умолчанию выключено); нужен доступ «Универсальный доступ».
- **Окна с клавиатуры (⌃⌥ + стрелки):** активное окно любого приложения встаёт в левую или правую половину экрана (если размер окна меняется; если нет — сдвигается до края), ↑ — на весь экран, ↓ — свернуть в Dock. Включается в Настройках → «Система» (по умолчанию выключено); нужен доступ «Универсальный доступ».
- **Новая игра «Lode Runner»** в меню «Передохни»: собрать всё золото, уходя от охранников, и подняться по появившейся лестнице наверх. Бегун копает яму пробелом — с той стороны, куда смотрит; охранник в яме выбывает, яма зарастает. Простые звуки: копание, золото, лестница, конец уровня. Игра помнит уровень, жизни и очки даже после выхода из программы. При запуске игра стоит на паузе, пауза снимается любой клавишей. 15 уровней, на каждом по три охранника, они бегут плавно и ищут кратчайший путь; стрелки или WASD — бег, P — пауза.
- **Рекорды** у JezzBall и Lode Runner: таблица 12 лучших результатов справа от поля, имя спрашивается в конце игры, как в «Тетрисе».
- **Новая игра «JezzBall»** в меню «Передохни»: Простые звуки: построение стены, закрытие участка, потеря жизни, конец уровня и игры. по полю летают шарики, щелчок строит стену, которая растёт сразу в обе стороны; если шарик заденет растущую половину — она разрушается и теряется жизнь. Участки без шариков закрашиваются, нужно закрыть 75% поля. Правый клик или пробел поворачивают стену, на каждом уровне на один шарик и одну жизнь больше, пауза включается сама при потере фокуса.

**Улучшения**
- Версия 6.0.

---

### Версия 5.0 — 2026-11-19

**Новое**
- Меню «Инструменты» закрывается кликом в любом месте окна мимо меню, а не только повторным нажатием на кнопку.
- Сброс размера и положения окна убран с главного экрана и перенесён в настройки («Система») с подтверждением.
- **«Дурак»:** анимация перелёта карт, колода стопкой с козырем под ней, отбой в углу под вуалью, рука на подсвеченной панели, имя игрока и правильные формы глаголов («Вы ходите», «Алексей ходит»); имена игроков крупнее и у каждого свой цвет везде, где встречаются.
- **Нижняя панель:** «Инструменты» — справа у края; быстрые вызовы программ (Терминал, Мониторинг системы, App Store, Системные настройки) стоят слева в тонкой полупрозрачной рамке. Правый клик по значку — заменить программу, убрать или вернуть набор по умолчанию; кнопка «+» добавляет программу (до четырёх).
- **Настройки → «Система» → «Значок в верхней панели»:** значок в строке меню можно убрать или вернуть (по умолчанию он есть).
- **Новая игра «Дурак»** в меню «Передохни»: подкидной и переводной, 2–4 игрока с компьютером, карты, рубашка и цвет стола как у «Косынки». Компьютер учитывает вышедшие карты и играет по эвристике; в конце партии просчитывает ходы случайными раздачами неизвестных карт (PIMC).
- Кнопка «Свернуть все окна» под «Новой категорией»: только сворачивает, повторный клик не разворачивает.
- Свои категории: правый клик → «Значок и цвет» (28 значков, 12 цветов); по умолчанию — голубая папка, как в Finder.
- Цветные значки категорий в боковом списке (настройки → «Значки»: «Обычные» / «Цветные»), по умолчанию цветные.
- «Недавние»: список сгруппирован по дням («Сегодня», «Вчера», «На этой неделе», «Раньше»), количество документов выбирается на вкладке: 25 / 50 / 100 / 200.
- **Вкладка «Недавние».** Самая первая в списке: 100 последних документов, с которыми работали на этом Маке (любыми программами, по данным Spotlight), с временем последнего открытия.
- **Вкладка «Сайты»: порядок значков.** Значки можно расставить вручную (перетащить на другой — встанет перед ним), либо включить сортировку по алфавиту или по частоте открытия; выбор запоминается, ручной порядок не теряется.
- **«Передохни» теперь с выбором: Тетрис и Косынка.** Новая игра «Косынка» (Klondike): карты перетаскиваются мышью, двойной щелчок отправляет карту в «дом», отмена хода (кнопка или `Z`), набор из колоды по 1 или по 3 карты, счётчик ходов и время, экран победы, авторская колода картинок и звук хода (если папки `Cards` нет, карты рисуются кодом). Когда все карты открыты, а колода пуста, остаток раскладывается в «дома» сам; после победы карты каскадом вылетают из «домов» и оставляют след, как в классической косынке; таблица 10 лучших результатов (время и ходы) отдельно для набора по 1 и по 3 карты, кнопка «Рекорды», выбор рубашки из пяти (по умолчанию «Шотландка», стол «Графит») и цвета стола из пяти приглушённых тонов (кнопка «Вид», выбор запоминается).
- **Поиск Пуска:** Enter больше не открывает документы из результатов (только приложения и копирование результата калькулятора); приложения находятся по любому из названий: русскому, английскому и из локализаций (например, «Печа» и «Prin» находят один и тот же «Центр печати»/Print Center).
- **«Передохни»:** тетрис падает плавно, а не рывками на целую клетку; шаг считается по реальному времени.

**Улучшения**
- Версия 5.0.

---

### Версия 4.1 — 2026-11-18

**Новое**
- **Опорная пара валют для конвертера в поиске.** В настройках Пуска появился раздел «Конвертер валют в поиске»: выбираются основная и вторая валюта (по умолчанию рубль и доллар). Если в поиске набрана одна валюта без «в …», например `100 долларов`, она переводится в основную, а основная — во вторую. Раньше рубль и доллар были заданы жёстко.

**Улучшения**
- Версия 4.1.

---

### Версия 4.0 — 2026-11-18

**Новое**
- **Инструмент «Файл менеджер»** (ключ → «Файл менеджер»): две панели в духе Total Commander. Клавиатура: ↑↓, PgUp/PgDn, Home/End двигают курсор; Shift+стрелки выделяют диапазон, а если начать с уже выделенной строки — снимают выделение; Пробел/Insert отмечают и переходят вниз; ⌘A, Num + / − / * ; Esc снимает выделение; Enter открывает папку или запускает файл; Backspace — вверх; Tab и ←/→ — между панелями. Мышь: Shift+клик — диапазон (по выделенному — снятие), ⌘+клик — отметить одну строку. F2/Shift+F6 переименование (для нескольких файлов — пакетное: маски [N] [E] [C] [Y][M][D], поиск и замена, регистр, счётчик, предпросмотр с проверкой конфликтов), F3 просмотр, F4 правка, F5 копирование, F6 перенос, F7 новая папка, F8 или Delete — удаление в Корзину (пакетно для отмеченных). Копирование и перенос спрашивают папку назначения, при совпадении имён — заменить (старый уходит в Корзину) / пропустить / применить ко всем. Файлы можно перетаскивать на панель из результатов поиска «Пуска», Finder и других программ (копия), а из панели — в любые приложения. Внешние диски и подключённые тома — в меню слева от пути; «Показать в Finder» открывает текущую папку. Тема и язык применяются. Контекстное меню строки содержит все функции F-клавиш (работает и на всём выделении). Если флешку или диск отключили, пока панель на нём, панель переходит в «Загрузки».

- **Файл менеджер: телефоны Android (MTP) и поиск.** В меню слева от пути (там же, где диски) появляется подключённый Android в режиме «Передача файлов»; открывается в панели как обычная папка (сначала хранилища: «Внутренняя память», карта). Работает напрямую по USB без сторонних программ, как OpenMTP: на время подключения «Пуск» завершает системную службу ptpcamera, которая держит телефон. С телефоном доступны только копирование (F5, перетаскивание на панель из поиска и Finder), переименование (в том числе пакетное) и удаление (насовсем, с подтверждением); просмотр, правка, перенос и новая папка на такой панели отключены везде: внизу, по F-клавишам и в контекстном меню. Файлы больше 4 ГБ пока не поддерживаются. Если телефон отключили, панель переходит в «Загрузки». В каждой панели есть строка поиска, как в «Пуске» (по имени и тексту внутри файлов, без калькулятора и конверторов): двойной клик по результату открывает его папку в панели, результаты можно перетаскивать.

- **Жест «большой + три пальца»:** запуск стал устойчивее на старых macOS и Intel (список трекпадов больше не освобождается, запасной поиск устройства, перезапуск после сна и повторные попытки при старте); в настройках под переключателем показывается диагностика: сколько трекпадов найдено и сколько пальцев видит система.

**Новое**
- **Инструмент «Загрузка и конвертация»** (кнопка с ключом → «Загрузка и конвертация»). В «Пуск» перенесено отдельное приложение Download and Convert, а вместе с ним ToMP3, YTLoader и «Конвертер», которые оно объединяло. Отдельное окно с тремя разделами: При открытии инструмента проверяется версия yt-dlp: если она старше последнего релиза на GitHub, над журналом загрузки появляется предупреждение с кнопкой «Обновить yt-dlp» (то же и во вкладке «Компоненты», где видна и версия). Не чаще раза в 12 часов; без интернета проверка молча пропускается. То же для ffmpeg: сравнивается с последней сборкой, и при новой версии появляется предупреждение с кнопкой «Обновить ffmpeg». Кнопки обновления в окне загрузки и в баннерах показываются только когда есть что обновлять; во вкладке «Компоненты» кнопки есть всегда, а подпись зависит от состояния: «Скачать», «Обновить» или «Скачать заново». Четвёртый раздел «Текст и документы»: TXT, RTF, HTML, DOC, DOCX, ODT, Markdown, PDF, FB2 и EPUB друг в друга, картинки и сканы PDF — в текст встроенным распознаванием macOS (Vision, офлайн; русский — в macOS 13+).
  - **Загрузка с YouTube** — качество (лучшее, 1080p, 720p, звук mp3), папка, cookies из браузера. В списке «Cookies из» только установленные браузеры (Safari, Chrome, Firefox, Brave, Edge, Opera, Vivaldi); по умолчанию Safari, а полный доступ к диску у «Пуска» уже есть.
  - **Аудио конвертор** — MP3, M4A, FLAC, WAV, AIFF, OGG, Opus; битрейт для сжатых форматов.
  - **Видео конвертор** — MP4, MOV, MKV, WebM, AVI, GIF; кодек H.264 / H.265, качество, ограничение Full HD, звук «Со звуком» / «Без звука» / «Только звук» (на выходе аудиофайл), HDR, обрезка и вырезание кусков.
  - **Компоненты** — состояние ffmpeg и yt-dlp, скачать заново или обновить. Они скачиваются один раз при первом открытии инструмента в `~/Library/Application Support/DownloadAndConvert`.
- **Выбор темы** в настройках под выбором языка: как в системе, светлая или тёмная. Применяется ко всем окнам «Пуска» и всем инструментам и запоминается; язык тоже сразу меняется во всех открытых инструментах. Раздел «О программе» убран из настроек (остался в меню приложения).
- **Файлы из поиска** можно перетаскивать мышкой в любое приложение или в Finder (уходит копия, оригинал остаётся), а справа у строки при наведении есть кнопка «Показать в Finder»; в контекстном меню файла появился пункт «Копировать файл» (как ⌘C в Finder, ⌘V вставит копию).
- **Своя иконка у сайтов**: правый клик по плитке сайта → «Сменить иконку…» (банк готовых иконок или картинка с диска), «Вернуть исходную иконку» возвращает значок самого сайта.
- Временные копии файлов, перетащенных в конверторы из программ, которые отдают только копию, удаляются при запуске «Пуска».
- **«Передохни»** — тетрис в инструментах (самый верхний пункт). Игра с Python перенесена на Swift: те же фигуры и уровни. Таблица рекордов хранится в настройках приложения (старые результаты из файла не переносятся). Очки и уровни как в международном тетрисе (Tetris Guideline), поэтому результаты можно сравнивать: 100 / 300 / 500 / 800 × уровень за 1–4 линии, +1 очко за клетку мягкого сброса (↓) и +2 за клетку жёсткого (пробел), подряд два «тетриса» — ×1,5, серия линий — 50 × номер × уровень; уровень растёт каждые 10 линий, скорость падения — (0,8 − (L−1)·0,007)^(L−1) секунд на клетку. T-spin и «чистый стакан» не считаются.
- **Калькулятор** в инструментах (второй пункт, после «Передохни»): в стиле CalcNew: простой цифровой дисплей, который масштабируется под число цифр, метки M1 (слева) и M2 (справа) с мелким содержимым ячейки (не помещается — в виде «× 10ⁿ»), клавиши в цветах «Пуска» (действия — акцентным цветом системы, функции и память — его светлым оттенком) (в том числе `xʸ`, `ʸ√x`, `x!`, `eˣ`), `См1`/`См2` для стирания памяти (цвета функциональных клавиш), процент как в обычных калькуляторах и ввод с клавиатуры; обычный (не перечёркнутый) ноль, ввод без ограничения числа знаков, очень большие и малые числа — в виде «1,5 × 10²⁵» (при наборе — после 15 цифр). Вкладка «Конвертер» умеет всё, что строка поиска: быстрый ввод («5 миль в км», «100 usd в руб»), единицы и валюты.
- **Своя иконка приложения.** Правый клик по приложению → «Сменить иконку…»: банк готовых иконок на разные случаи (с выбором цвета; удобно для веб-приложений) или картинка с диска; «Вернуть исходную иконку» отменяет замену. Меняется только вид в «Пуске», сами программы не трогаются.
- Если идёт загрузка или конвертация, при выходе из «Пуска» он спрашивает подтверждение; язык окна следует настройке языка «Пуска».

**Улучшения**
- Версия 4.0.

---

### Версия 3.0 — 2026-11-17

**Новое**
- **Калькулятор, единицы и валюты в строке поиска.** Наберите `15% от 8400`, `2+2*3`, `sqrt(144)`, `5 миль в км`, `72 f в c`, `3 гб в мб` или `100 usd в руб` — ответ появится крупной карточкой над результатами, клик копирует число, Enter копирует и закрывает окно. Курсы валют берутся из интернета (не чаще раза в час), без связи показываются последние сохранённые.
- **Поиск по всему компьютеру.** Кроме приложений, строка поиска находит файлы и папки через системный Spotlight (домашняя папка, iCloud Drive и внешние диски; файлы, не скачанные из iCloud, помечены значком облака) и показывает их отдельным блоком «Файлы и папки», как в Spotlight на iPhone: значок, имя, папка и тип. Ищет и по именам, и по тексту внутри файлов (то, что проиндексировал Spotlight); найденные по тексту помечены «в тексте». Клик открывает файл, правый клик — «Показать в Finder» и «Копировать путь»; Enter открывает первое приложение, а если приложений нет, — первый файл. Текст в строке поиска не пропадает, если «Пуск» свернули и открыли снова (или переключились в другую программу); очищается кнопкой с крестиком в конце строки.
- **Не давать компьютеру уснуть**: кнопка с чашкой рядом с настройками (включается и из меню значка в строке меню). Пока включена, Мак и экран не засыпают от бездействия (как Amphetamine); чашка и значок в строке меню становятся голубыми, а рядом с чашкой появляется подпись «Не давать компьютеру уснуть». Закрытие крышки по-прежнему усыпляет Мак.

---

### Версия 2.0 — 2026-11-17

**Новое**
- **Внешние диски** (Инструменты), вкладка «Форматирование». Настоящие FAT32, FAT16, exFAT, а также Mac OS Extended и APFS. По умолчанию — FAT32 со схемой разделов MBR: так устройства (камеры, ТВ, магнитолы, Windows) читают флешку надёжнее, чем после стандартного «Дискового редактора». Показываются только внешние диски; диск, с которого загружен Mac, скрыт. Перед стиранием — отдельное подтверждение.
- **Внешние диски**, вкладка «Скорость»: измеряет последовательную скорость записи и чтения (в обход кэша системы), определяет подключение (USB 2.0 / 3.0 / 3.1 / 3.2 / USB4) и сравнивает результат с практическим пределом интерфейса и с типичными устройствами: флешки, SD-карты, HDD, SATA- и NVMe-SSD. Тест работает во временном файле, который потом удаляется. Чтение и запись показаны отдельными графиками и сравниваются с типичными значениями для того же направления; запись сбрасывается на носитель и учитывается вместе со сбросом.
- **Анализатор диска** (Инструменты) в стиле DaisyDisk: круговая диаграмма и список, переход вглубь, «Показать в Finder», перемещение в Корзину с подтверждением.
  - Открывается в отдельном окне и живёт независимо от «Пуск».
  - Помнит прошлое сканирование и обновляет только то, что изменилось (по журналу изменений macOS).
  - Быстрый нативный обход диска; пропускает iCloud Drive и дубликаты системных путей.
- **Закрыть все программы** (Инструменты): вежливо просит программы завершиться, программы с несохранёнными данными сами спросят, что делать. Можно выбрать, что закрывать.
- **Вкладка «Сайты»**: быстрый доступ к сайтам и IP-адресам (IP без http/https), значки берутся с самих сайтов, можно создавать папки.
- **Настройки внутри «Пуск»**: язык (как в системе / русский / английский), сочетания клавиш, жест, Dock, автозапуск. В меню в строке состояния остались только «Открыть «Пуск»» и «Выход».
- **Английский язык** и переключатель языка.
- **Горячая клавиша** показа и скрытия «Пуск» (по умолчанию ⌃⌥P); Esc закрывает окно из любого места.
- **Жест «щипок» (большой палец + три пальца)** — по умолчанию выключен, включается в настройках с подтверждением.
- **Ввод пароля администратора** прямо в окне «Пуск», раскладка переключается на английскую, пароль не показывается и не предлагается менеджерам паролей.

**Улучшения**
- Раздел «О программе» в настройках и в меню приложения: версия 2.0, © 2026 Andy Khristoforov.
- Все инструменты, кроме «Закрыть все программы», открываются в отдельных окнах: «Пуск» их только запускает, дальше они живут независимо. Esc закрывает окно инструмента.
- Строки в списках целиком кликабельны и разворачиваются по клику; при наведении мыши подсвечиваются серым.
- В очистке мусора можно выбирать отдельные элементы.
- Окно по умолчанию стало выше на один ряд значков.
- Подпись и нотаризация сборки настраиваются через `.sign.local`.

---

## English

### Version 6.0 — 2026-11-20

**The app is renamed StartForMac** (`StartForMac.app`: menu name, About, Dock and messages). After copying the new version to the Applications folder, delete the old “Пуск”. Settings, permissions and the list of websites are kept: the bundle identifier is unchanged. Launch at login is updated automatically; pin the Dock icon again.

**New**
- **Smart clipboard:** history of recent copies — text, images and files, keeping 3, 5 or 10 entries (set in Settings). Opens with ⇧⌘V as a list at the cursor (arrows or digits, Enter pastes, P pins, ⌫ removes) and via a clipboard icon in the top bar (a click copies the entry). Pinned entries are never pushed out and do not count toward the limit. Passwords are not saved: concealed copies and password managers are skipped; the history lives in memory only and is gone on quit. Turn it on in Settings → “System” (off by default); enabling it asks for the “Accessibility” permission needed for automatic pasting.
- The Tools menu is shifted right: its left edge lines up with the quick-launch frame.
- **Calculator** moved from Tools to the top bar — an icon to the right of the cup.
- **Settings:** switches are aligned to the right edge; the two bottom buttons have equal width and are centred.
- **UnRar** (Tools): extracts RAR and RAR5, 7z, ZIP (including encrypted), TAR, GZ, BZ2, XZ, ISO, DMG, CAB, ARJ, LZH, WIM and more. Supports passwords (a protected archive shows a password field; a wrong password can be re-entered) and multi-volume archives: pick any volume (.part2.rar, .r01, .7z.002 …) and extraction starts from the first. Add archives with a button or drag-and-drop; they are extracted one by one with progress, next to the archive (in a folder named after it) or into a chosen folder. The engine is command-line 7-Zip: taken from the system, or downloaded on first open.
- **Duplicates & similar photos** (Tools): exact duplicates are found by content (SHA-256), similar pictures by a small image fingerprint; hard links are not counted as copies. Tick extras by hand or with “Select extras” (for duplicates the oldest copy stays, for photos the one with the highest resolution), at least one copy always stays in every group, and only what is ticked goes to the Trash. Pick or drag a folder into the window; every file has a Quick Look preview.
- **Disk analyzer:** a Collector (tray icon on an item or drag it down — gather the clutter and move it all to the Trash at once, with the total space to be freed), analysis of any folder or disk (“Choose folder…” or drag a folder into the window), and a file preview with the standard macOS Quick Look (eye icon); hovering a chart sector shows its name, size and share in the centre.
- **Window switcher on ⌥Tab:** for those coming from Windows — switches focus between individual windows rather than whole apps and shows their thumbnails. While Option is held: Tab / ⇧Tab or arrows pick, Esc cancels, a click selects. Turn it on in Settings → “System” (off by default; thumbnails have their own switch, are off by default and need the Screen & System Audio Recording permission).
- **⌘X in Finder:** cut files — ⌘X copies the selection and marks it as cut, the next ⌘V moves the files; a small “Cut” notice slides in at the bottom right for a moment (in the current theme colours). Turn it on in Settings → “System” (off by default); needs the Accessibility permission.
- **Window control from the keyboard (⌃⌥ + arrows):** the active window of any app snaps to the left or right half of the screen (if it can be resized; otherwise it just moves to that edge), ↑ fills the screen, ↓ minimizes to the Dock. Turn it on or off in Settings → “System” (off by default); needs the Accessibility permission.
- **New game “Lode Runner”** in the “Take a Break” menu: collect all the gold while evading guards, then climb the ladder that appears. The runner digs with Space, on the side he is facing; a guard in a hole is out for a while, holes fill back in. Simple sounds: digging, gold, the ladder appearing, level end. The game remembers the level, lives and score even after the app is quit. The game starts paused, and any key resumes it. 15 levels with three guards each, they run smoothly and take the shortest path; arrows or WASD run, P pauses.
- **Records** for JezzBall and Lode Runner: a top-12 table beside the field, the name is asked at the end of the game, as in Tetris.
- **New game “JezzBall”** in the “Take a Break” menu: Simple sounds: building a wall, closing an area, losing a life, level and game end. balls bounce around the field, a click builds a wall that grows in both directions at once; if a ball hits a growing half it is destroyed and you lose a life. Areas without balls are filled in; fill 75% of the field to win the level. Right-click or Space turns the wall, each level adds a ball and a life, and the game pauses by itself when the window loses focus.

**Improvements**
- Version 6.0.

---

### Version 5.0 — 2026-11-19

**New**
- The Tools menu now closes with a click anywhere in the window outside the menu, not only by pressing the Tools button again.
- Resetting the window size and position moved from the main screen to Settings (“System”), with a confirmation.
- **Durak:** animated card moves, the deck shown as a stack with the trump under it, the discard pile in a corner under a veil, your hand on a highlighted panel, player name and correct verb forms; player names are larger and each has its own colour wherever it appears.
- **Bottom bar:** “Tools” is at the right edge; the quick-launch apps (Terminal, Activity Monitor, App Store, System Settings) sit on the left in a thin translucent frame. Right-click an icon to replace it, remove it or restore the default set; “+” adds an app (up to four).
- **Settings → System → “Menu bar icon”:** the menu bar icon can be hidden or shown again (shown by default).
- **New game “Durak”** in the “Take a Break” menu: throw-in and transfer variants, 2–4 players with the computer, same cards, card back and table colour as Solitaire. The computer tracks the cards that are out and plays by a heuristic; near the end of the game it evaluates moves with random deals of the unknown cards (PIMC).
- “Minimize all windows” button under “New category”: it only minimizes, a second click does not restore.
- Your own categories: right-click → “Icon and color” (28 icons, 12 colors); default is a blue Finder-style folder.
- Colored category icons in the sidebar (Settings → “Icons”: Plain / Colored), colored by default.
- “Recent”: the list is grouped by day (Today, Yesterday, This week, Earlier) and the number of documents is chosen on the tab: 25 / 50 / 100 / 200.
- **“Recent” tab.** The first one in the list: the 100 most recent documents worked with on this Mac (in any app, from Spotlight), with the last-opened time.
- **“Sites” tab: icon order.** Icons can be arranged by hand (drag one onto another to place it before it), or sorted alphabetically or by how often they are opened; the choice is remembered and the manual order is kept.
- **“Take a Break” now offers Tetris and Solitaire.** New Klondike Solitaire game: drag cards with the mouse, double-click sends a card to the foundation, undo (button or `Z`), draw 1 or 3 cards, move counter and timer, win screen, the author's own card images and a move sound (if the `Cards` folder is missing, cards are drawn in code). When every card is face up and the stock is empty, the rest is moved to the foundations automatically; after a win the cards fly out of the foundations and leave trails, like in classic Solitaire; a top-10 table (time and moves) separately for draw-1 and draw-3, “Records” button, a choice of five card backs (default: Tartan back, Graphite table) and five muted table colours (“View” button, remembered).
- **Start search:** Enter no longer opens documents from the results (only apps and copying a calculator result); apps are found by any of their names: Russian, English and the localized ones (for example “Печа” and “Prin” both find Print Center).
- **“Rest” (Tetris):** the piece now falls smoothly instead of jumping a whole cell; the step is driven by real elapsed time.

**Improvements**
- Version 5.0.

---

### Version 4.1 — 2026-11-18

**New**
- **Reference currency pair for the search converter.** Start's Settings now has a “Currency converter in search” section: choose a main and a second currency (ruble and dollar by default). If the search has a single currency without “to …”, e.g. `100 dollars`, it is converted to the main currency, and the main one to the second. Before, the ruble and the dollar were hard-coded.

**Improvements**
- Version 4.1.

---

### Version 4.0 — 2026-11-18

**New**
- **“File manager” tool** (wrench → “File manager”): two panes in the spirit of Total Commander. Keyboard: ↑↓, PgUp/PgDn, Home/End move the cursor; Shift+arrows select a range, and starting from an already selected row deselects; Space/Insert mark and step down; ⌘A, Num + / − / *; Esc clears the selection; Enter opens a folder or launches a file; Backspace goes up; Tab and ←/→ switch panes. Mouse: Shift+click selects a range (on a selected row it deselects), ⌘+click toggles one row. F2/Shift+F6 rename (several files → batch rename: [N] [E] [C] [Y][M][D] masks, find & replace, case, counter, live preview with conflict checks), F3 view, F4 edit, F5 copy, F6 move, F7 new folder, F8 or Delete move to Trash (batch for marked files). Copy and move ask for the destination; on name clashes: replace (the old one goes to the Trash) / skip / apply to all. Files can be dragged onto a pane from Start search results, Finder and other apps (copy), and out of a pane into any app. External drives and mounted volumes are in the menu left of the path; “Show in Finder” opens the current folder. Theme and language apply. The row context menu has every F-key function (it works on the whole selection too). If a flash drive or disk is ejected while a pane is on it, the pane switches to Downloads.

- **File manager: Android phones (MTP) and search.** A connected Android in “File transfer” mode appears in the menu left of the path (next to the disks) and opens in a pane like a normal folder (storages first: “Internal storage”, SD card). It works directly over USB without third-party apps, like OpenMTP: while connected, Start stops the system ptpcamera service that holds the phone. With a phone only copy (F5, dropping onto the pane from search and Finder), rename (batch too) and delete (permanent, with confirmation) are available; view, edit, move and new folder are disabled on such a pane everywhere: the bottom bar, F-keys and the context menu. Files over 4 GB are not supported yet. If the phone is unplugged, the pane returns to Downloads. Every pane has a search field like Start’s (by name and by text inside files, without the calculator and converters): double-click a result to open its folder in the pane; results can be dragged.

- **“Thumb + three fingers” gesture:** more reliable start on older macOS and Intel (the trackpad list is no longer released, fallback device lookup, restart after sleep and retries at launch); Settings shows a diagnostic line under the switch: how many trackpads were found and how many fingers the system sees.

**New**
- **Download and Convert tool** (wrench button → “Download and Convert”). The standalone Download and Convert app, which itself merged ToMP3, YTLoader and “Конвертер”, now lives inside Start. One window with three sections: When the tool opens, the yt-dlp version is checked: if it is older than the latest GitHub release, a warning with an “Update yt-dlp” button appears above the download log (the same in the “Components” tab, which also shows the version). At most once every 12 hours; offline, the check is silently skipped. The same for ffmpeg: it is compared with the latest build, and a warning with an “Update ffmpeg” button appears when a newer one exists. Update buttons in the download window and banners appear only when there is something to update; in the “Components” tab the buttons are always there and their label depends on the state: “Download”, “Update” or “Download again”. A fourth section, “Text & Documents”: TXT, RTF, HTML, DOC, DOCX, ODT, Markdown, PDF, FB2 and EPUB into each other, pictures and scanned PDFs to text with the built-in macOS recognition (Vision, offline; Russian on macOS 13+).
  - **Download from YouTube** — quality (best, 1080p, 720p, audio mp3), folder, cookies from a browser. “Cookies from” lists only installed browsers (Safari, Chrome, Firefox, Brave, Edge, Opera, Vivaldi); Safari is the default, and Start already has Full Disk Access.
  - **Audio Converter** — MP3, M4A, FLAC, WAV, AIFF, OGG, Opus; a bitrate for lossy formats.
  - **Video Converter** — MP4, MOV, MKV, WebM, AVI, GIF; H.264 / H.265, quality, Full HD limit, sound “With sound” / “No sound” / “Sound only” (the output is an audio file), HDR, trimming and cutting out parts.
  - **Components** — status of ffmpeg and yt-dlp, re-download or update. They are downloaded once, the first time the tool is opened, into `~/Library/Application Support/DownloadAndConvert`.
- **Theme choice** in Settings under the language: system, light or dark. It applies to all Пуск windows and all tools and is remembered; the language also switches at once in every open tool. The “About” section was removed from Settings (it stays in the app menu).
- **Files from search** can be dragged with the mouse into any app or Finder (a copy is passed, the original stays), and a “Show in Finder” button appears at the right of the row on hover; the file context menu has a new “Copy file” item (like ⌘C in Finder, ⌘V pastes a copy).
- **Custom icons for sites**: right-click a site tile → “Change Icon…” (the bank of ready-made icons or a picture from disk); “Restore Original Icon” brings back the site’s own icon.
- Temporary copies of files dragged into the converters from apps that hand over only a copy are deleted when Пуск starts.
- **Take a Break** — Tetris in the tools (the top item). Ported from Python to Swift: same pieces and levels. The score table is stored in the app settings (old results from the file are not carried over). Scoring and levels follow the international Tetris Guideline, so results are comparable: 100 / 300 / 500 / 800 × level for 1–4 lines, +1 point per cell of soft drop (↓) and +2 per cell of hard drop (Space), back-to-back Tetrises ×1.5, combo 50 × count × level; the level rises every 10 lines and the fall speed is (0.8 − (L−1)·0.007)^(L−1) seconds per row. T-spins and perfect clears are not counted.
- **Calculator** in the tools (the second item, after “Take a Break”): CalcNew style: a simple digital display that scales with the number of digits, M1 (left) and M2 (right) marks with the small cell contents (if too long — shown as “× 10ⁿ”), keys in the Пуск colors (actions in the system accent color, functions and memory in its light tint) (including `xʸ`, `ʸ√x`, `x!`, `eˣ`), `См1`/`См2` to clear memory (function-key color), percent as in ordinary calculators and keyboard input; a plain (not slashed) zero, no limit on the number of digits typed, very large and small numbers shown as “1.5 × 10²⁵” (while typing — after 15 digits). The “Converter” tab does everything the search field does: quick input (“5 miles to km”, “100 usd to rub”), units and currencies.
- **Custom app icons.** Right-click an app → “Change Icon…”: a bank of ready-made icons for different cases (with a choice of color; handy for web apps) or an image from disk; “Restore Original Icon” undoes it. Only the look inside Start changes, the apps themselves are untouched.
- If a download or conversion is running, Start asks for confirmation before quitting; the window follows Start's language setting.

**Improvements**
- Version 4.0.

---

### Version 3.0 — 2026-11-17

**New**
- **Calculator, units and currencies in the search field.** Type `15% of 8400`, `2+2*3`, `sqrt(144)`, `5 miles to km`, `72 f to c`, `3 gb to mb` or `100 usd to rub` — the answer appears as a large card above the results; click copies the number, Enter copies it and closes the window. Currency rates come from the internet (at most once an hour); offline, the last saved rates are used.
- **Search the whole computer.** Besides apps, the search field finds files and folders through system Spotlight (home folder, iCloud Drive and external drives; files not yet downloaded from iCloud get a cloud icon) and shows them in a separate “Files and folders” block, like Spotlight on iPhone: icon, name, folder and kind. It searches both names and text inside files (whatever Spotlight has indexed); items found by text are marked “in text”. Click opens the file; right click gives “Show in Finder” and “Copy path”. Enter opens the first app, or the first file when there are no apps. The search text is kept when “Пуск” is hidden and opened again (or you switch to another app); it is cleared with the ✕ button at the end of the field.
- **Keep the Mac awake**: a cup button next to Settings (also available from the menu-bar icon menu). While on, the Mac and its display do not sleep from inactivity (like Amphetamine); the cup and the menu-bar icon turn blue, and a “Keep the Mac awake” label appears next to the cup. Closing the lid still puts the Mac to sleep.

---

### Version 2.0 — 2026-11-17

**New**
- **External drives** (Tools), “Format” tab. Real FAT32, FAT16 and exFAT, plus Mac OS Extended and APFS. The default is FAT32 with an MBR partition scheme: cameras, TVs, car stereos and Windows read such drives far more reliably than after Disk Utility's defaults. Only external drives are listed; the drive your Mac booted from is hidden. A separate confirmation is required before erasing.
- **External drives**, “Speed” tab: measures sequential write and read speed (bypassing the system cache), detects the connection (USB 2.0 / 3.0 / 3.1 / 3.2 / USB4) and compares the result with the interface’s practical limit and with typical devices: flash drives, SD cards, HDDs, SATA and NVMe SSDs. The test uses a temporary file that is deleted afterwards. Read and write are shown as separate charts, each compared with typical values for the same direction; the write includes flushing to the media.
- **Disk analyzer** (Tools), DaisyDisk-style: sunburst chart and list, drill-down, “Show in Finder”, move to Trash with confirmation.
  - Opens in its own window and lives independently of “Пуск”.
  - Remembers the previous scan and updates only what changed (using the macOS file-system change journal).
  - Fast native scanning; skips iCloud Drive and duplicate system paths.
- **Quit all apps** (Tools): politely asks apps to quit; apps with unsaved data ask what to do themselves. You choose which apps to close.
- **“Sites” tab**: quick access to websites and IP addresses (IPs are stored without http/https), icons are taken from the sites themselves, and you can create folders.
- **Settings inside “Пуск”**: language (system / Russian / English), hotkeys, gesture, Dock, launch at login. The menu-bar menu now has only “Open Пуск” and “Quit”.
- **English localization** and a language switcher.
- **Global hotkey** to show/hide “Пуск” (default ⌃⌥P); Esc closes the window from anywhere.
- **Pinch gesture (thumb + three fingers)** — off by default, enabled in settings after a confirmation.
- **Admin password prompt** right inside “Пуск”: the keyboard layout switches to English, the password is never shown and never offered to password managers.

**Improvements**
- “About” section in settings and in the app menu: version 2.0, © 2026 Andy Khristoforov.
- All tools except “Quit all apps” open in their own windows: “Пуск” only launches them and they live independently. Esc closes a tool window.
- Whole rows in lists are clickable and expand on click; rows highlight in gray on hover.
- Junk cleanup lets you pick individual items.
- The default window is one icon row taller.
- Signing and notarization are configured via `.sign.local`.
