# Что нового / What's new

### Версия 11.4

**Новое**
- Внутри кнопки «Пуска» вместо голых синих квадратов значок: скруглённый квадрат с фоном и тончайшей серой окантовкой и четырьмя синими окнами, чуть меньше значка Finder в Dock. При нажатии темнеют синие окна, а не сама кнопка.
- Настройки фона значка (Настройки → «Окна»): цвет (белый, чёрный и цвета радуги: красный, оранжевый, жёлтый, зелёный, голубой, синий, фиолетовый), прозрачность и насыщенность (у белого и чёрного не действует), выключатель окантовки. По умолчанию белый фон, прозрачность 90%, окантовка включена.
- Кнопка увеличивается вместе с Dock (режим «Рядом с Dock»): когда в системе включено «Увеличение» и курсор над Dock, кнопка раздвигается вдоль Dock (по горизонтали от стороны Dock, у бокового Dock вверх и вниз поровну), а значок внутри растёт и приподнимается, как значки Dock, и может выходить за границы кнопки. Увеличение зависит от расстояния до кнопки: плавно растёт по пути к ней и затухает за ней, на самой кнопке значок максимальный. Предел задают только настройки Dock (размер увеличенных значков). Клик по значку, в том числе правой кнопкой, работает по всей его площади, и там, где он выше кнопки.
- Размер кнопки пересчитан: прежние 135% теперь 100% (по умолчанию), диапазон 60–160%; ползунок меняет кнопку и значок пропорционально, увеличение Dock умножает уже этот размер. Сохранённый ранее размер сбрасывается на 100%.
- Кнопка плавнее едет за Dock: положение догоняется на каждом кадре (120 раз в секунду), а не прыжками по ответам опроса Dock.
- Меню по правому клику на кнопке открывается над кнопкой, по её центру, как у значков Dock (с отступом от увеличенного значка), а у бокового Dock — сбоку от кнопки: справа, если Dock слева, и слева, если справа.
- Кнопка «Пуска» на старых macOS: убраны своя подложка и ползунок «Прозрачность фона», остался только системный материал `.hudWindow`, который сам светлеет и темнеет по теме и фону.
- Версия 11.4.

**Исправлено**
- Сообщение «Установлена последняя версия» после проверки обновлений в настройках теперь по центру окна настроек, а не правее и выше.

### Version 11.4

- Inside the Start button, instead of bare blue squares there is now an icon: a rounded square with a background and a hairline gray outline and four blue windows, slightly smaller than the Finder icon in the Dock. On press the blue windows darken instead of the button itself.
- Icon background settings (Settings → “Windows”): color (white, black and the rainbow: red, orange, yellow, green, light blue, blue, violet), transparency and saturation (no effect for white and black), an outline switch. Default: white background, 90% transparency, outline on.
- The button magnifies with the Dock (“Next to Dock” mode): when Dock magnification is on and the pointer is over the Dock, the button widens along the Dock (horizontally away from the Dock side, or up and down equally beside a side Dock) and the icon inside grows and lifts like the Dock icons, and may extend beyond the button. The magnification depends on the distance to the button: it grows smoothly on the way to it and fades behind it, and the icon is at maximum on the button itself. The limit is set only by the Dock settings (the size of magnified icons). A click on the icon, right button included, works over its whole area, also where it is taller than the button.
- The button size is rescaled: the former 135% is now 100% (default), range 60–160%; the slider scales the button and the icon proportionally, and Dock magnification multiplies that size. A previously saved size resets to 100%.
- The button follows the Dock more smoothly: its position catches up on every frame (120 times a second) instead of jumping on each Dock poll.
- The right-click menu of the button opens above the button, centered on it, like Dock icons' menus (clear of the magnified icon), and beside a side Dock it opens to the side of the button: to the right if the Dock is on the left, and to the left if it is on the right.
- The Start button on older macOS: the custom backing and the “Background transparency” slider are removed; only the system material `.hudWindow` remains, which lightens and darkens by itself with the theme and backdrop.
- The “You have the latest version” message after an update check in Settings is now centered over the Settings window instead of appearing to the right and higher.
- Version 11.4.

### Версия 11.1

**Новое**
- Окно «Пуска» теперь ниже Dock: если окно перекрывает Dock, значки Dock остаются поверх него, как и кнопка «Пуска».
- Главное окно «Пуска» больше не уезжает в сторону, когда в macOS включено «Показывать Рабочий стол при нажатии на обои»: оно остаётся на месте, как флаг раскладки.
- Кнопка «Пуска» (рядом с Dock и на экране) в macOS 26 и новее сделана из «жидкого стекла», как Dock и системные кнопки; прозрачность и яркость стекла подстраивает сама система под фон за кнопкой (как у Dock), к ней добавлено небольшое затемнение по теме системы (сильнее в тёмной теме). В более старых macOS кнопка прежняя (размытие с плотной подложкой). В старых macOS прозрачность подложки регулируется ползунком «Прозрачность фона» в настройках, в macOS 26 он не нужен и скрыт.
- Версия 11.1.

### Version 11.1

- The Start window is now below the Dock: if the window overlaps the Dock, the Dock icons stay on top of it, like the Start button.
- The main Start window no longer slides aside when macOS “Show Desktop when clicking wallpaper” is on: it stays in place, like the layout flag.
- On macOS 26 and later the Start button (next to the Dock and on screen) is made of Liquid Glass, like the Dock and system buttons; the system itself adapts the glass transparency and brightness to what is behind the button (like the Dock), with a slight extra darkening by the system theme (stronger in dark mode). On older macOS the backing transparency is set with the “Background transparency” slider in Settings; on macOS 26 it is not needed and hidden. Older macOS keeps the previous look (blur with a dense backing).
- Version 11.1.

### Версия 10.0

**Новое**
- «Загрузка и конвертация»: исправлено перетаскивание файлов. При дропе видео из стопки в Dock на вкладку «Видео конвертор» вместо него подставлялся старый документ (docx) с прошлого перетаскивания. Теперь «Пуск» сверяет путь из буфера перетаскивания с тем, что отдаёт текущий дроп, а разделы «Видео» и «Аудио» принимают только свои типы файлов.
- «Загрузка и конвертация»: выбор папки для результата убран, во всех трёх конверторах и в загрузке с YouTube результат всегда сохраняется в «Загрузки»: так проще найти результаты.
- Файл менеджер: стрелка вниз в поле пути переводит курсор в поле поиска, следующая — в список файлов, дальше стрелки ходят по файлам; стрелка вверх с первой строки списка возвращает в поиск, а затем в поле пути. В полях пути и поиска стрелки влево и вправо работают как раньше.
- Настройки → «Окна»: значок «Пуска» в трёх режимах: «В Dock» (обычный значок программы, по умолчанию), «Рядом с Dock» и «На экране». «Пуск» рисует свою плавающую кнопку в виде четырёх синих квадратов (как в Windows) вплотную к левому краю Dock (если Dock сбоку, то под ним) и двигает её вслед за Dock: размер, положение, автоскрытие. Клик открывает и закрывает «Пуск» (кнопка всегда поверх окна «Пуска», положение и размер окна она не меняет), правый клик — то же меню, что у значка в Dock, плюс «Настройки…», «Скрыть кнопку» и «Закрыть «Пуск»» (такой же пункт есть в меню значка в верхней панели); пока кнопка включена, значок «Пуска» в Dock не показывается: закреплённый значок убирается (Dock при этом перезапускается), а при выключении кнопки возвращается на прежнее место; размер кнопки, прозрачность фона (в macOS ниже 26) и (рядом с Dock) расстояние от Dock — от почти вплотную до двух значков — выбираются в настройках; есть режим «На экране»: кнопка стоит где её оставили, поверх всех окон, её можно перетащить, за Dock она не следит. Это эмуляция, а не настоящий значок Dock.
- Версия 10.0.

### Version 10.0

**New**
- Download and Convert: fixed drag and drop. When a video was dropped from a Dock stack onto the “Video converter” section, an old document (docx) from a previous drag was added instead. Start now checks the path from the drag pasteboard against what the current drop provides, and the Video and Audio sections accept only their own file types.
- Download and Convert: the choice of the output folder is gone; in all three converters and in the YouTube download the result is always saved to Downloads, which makes the results easier to find.
- File manager: the down arrow in the path field moves the cursor to the search field, the next one to the file list, and then the arrows walk through the files; the up arrow on the first row of the list goes back to the search field and then to the path field. In the path and search fields the left and right arrows work as before.
- Settings → “Windows”: the Start icon in three modes: “In Dock” (the regular program icon, default), “Next to Dock” and “On screen”. Start draws its own floating button of four blue squares (like in Windows) right next to the left edge of the Dock (below it if the Dock is on the side) and moves it along with the Dock: size, position, auto-hide. A click opens and closes Start (the button is always above the Start window and never changes the window position or size), a right click shows the same menu as the Dock icon plus “Settings…”, “Hide button” and “Quit Start” (the menu bar icon has the same item); while the button is on, the Start icon is not shown in the Dock: a pinned icon is removed (the Dock restarts) and comes back to its place when the button is turned off; the button size (60–160% of a Dock icon, 100% by default), and, next to the Dock, the distance from the Dock (from almost touching to two icons) are set in Settings; there is an “On screen” mode: the button stays where you leave it, above all windows, it can be dragged and does not follow the Dock. This is an emulation, not a real Dock icon.
- Version 10.0.

### Версия 9.1

**Новое**
- Проверка обновлений: теперь каждые 6 часов и после пробуждения Mac (раньше раз в сутки, поэтому новая версия могла появиться с задержкой до суток). Сбой сети или лимит GitHub больше не откладывают следующую попытку на сутки, а найденное обновление не пропадает после перезапуска «Пуска». Переключатель называется «Проверять обновления автоматически».
- Версия 9.1.

### Version 9.1

**New**
- Update check: now every 6 hours and after the Mac wakes up (it used to be once a day, so a new version could show up with up to a day of delay). A network failure or a GitHub rate limit no longer postpones the next attempt by a day, and a found update no longer disappears after restarting Start. The switch is now called “Check for updates automatically”.
- Version 9.1.

### Версия 9.0

**Новое**
- Видеоконвертер: список «Разрешение» — «Как в оригинале» (по умолчанию), 4K, 1080p, 720p, 480p, 360p и «Свой размер…». Готовые варианты задают короткую сторону кадра (подходят и вертикальному видео), пропорции сохраняются, меньший кадр не увеличивается. Для своего размера вводятся ширина и высота (проверяется, что это целые числа больше нуля), кадр вписывается в рамку. Прежний чекбокс «Не больше Full HD» заменён пунктом «1080p».
- Конвертеры (видео, звук, текст): за кнопкой «Папка…» теперь показывается реальная папка результата. Если папка не выбрана, это папка исходных файлов, а для файлов, перетащенных из других программ, — «Загрузки» (раньше везде было написано «рядом с исходным файлом»). Кнопка «Сбросить» переименована в «Рядом с исходным»: она возвращает сохранение рядом с исходным файлом.
- Конвертеры: перетащенные файлы теперь берутся по настоящему пути прямо из буфера перетаскивания (а также по ссылкам вида file:///.file/id=… и через объект-ссылку), а не копируются во временную папку — поэтому «рядом с исходным файлом» работает, а не уходит в «Загрузки».
- Во всех конвертерах и в загрузчике появилась кнопка «Очистить окно»: убирает все файлы из очереди (кроме того, что конвертируется сейчас), а в загрузчике — ссылку, журнал и статус.
- Обслуживание: у каждой задачи показывается точная команда, которая будет выполнена; при сбое выводится причина (последняя строка вывода команды), а код 127 объясняется как «команда не найдена на этой версии macOS». Задача «Запустить скрипты обслуживания» убрана совсем: утилиты `periodic` нет в новых macOS.
- Обслуживание: пять новых задач — пересобрать список «Открыть с помощью», очистить кэш просмотра (Quick Look) и миниатюр, перезапустить Dock, Finder и строку меню, перезапустить звуковую службу, перезапустить Bluetooth. У каждой — понятное описание, что и зачем будет сделано.
- Инструмент «UnRar» переименован в «UnRAR, UnZip, 7z, GZ…» и получил упаковку: переключатель «Распаковка / Упаковка». Можно упаковать файлы и папки в 7z, ZIP, TAR.GZ, TAR.BZ2 или TAR.XZ, выбрать степень сжатия, имя и папку. Для 7z и ZIP есть пароль (у ZIP — AES-256, у 7z можно скрыть и имена файлов) и разбивка на тома (10, 25, 100, 700 МБ, 1 и 4 ГБ или свой размер). Движок — тот же 7-Zip. RAR создавать нельзя: формат закрытый.
- Дубликаты и похожие фото: исключение папок прямо при отметке файлов. Кнопка «Исключить папки…» открывает дерево папок с галочками (снял галочку — папка и всё внутри пропадают из результатов, группы без повторов исчезают), а в каждой строке есть кнопка «Исключить эту папку из поиска». Исключения запоминаются для следующих поисков, «Включить все» сбрасывает их.
- Дубликаты и похожие фото: можно отметить и удалить все копии группы, а не только лишние (раньше одна копия оставалась всегда). Перед удалением окно подтверждения красным предупреждает, в скольких группах не останется ни одной копии; «Выбрать лишние» по-прежнему оставляет по одной.
- Архиватор: при вводе пароля (упаковка и распаковка) раскладка сама переключается на английскую. ZIP принимает пароль только из латиницы, цифр и знаков (иначе 7-Zip отвечал «E_INVALIDARG»): теперь это проверяется заранее, русские буквы подсвечиваются красным предупреждением, а кнопка «Упаковать» неактивна. У 7z пароль может быть любым.
- Вкладка «О программе» в настройках теперь показывает отдельный текст для пользователя (`AppReadme.ru.md` / `AppReadme.md`), а не README для разработчика: те же две части («Возможности» и «Приватность и безопасность»), но переписаны для человека, который просто установил программу.
- Очистка мусора, «Остатки удалённых приложений»: файл настроек больше не считается «осиротевшим», если он подходит к любой установленной программе: по идентификатору (включая вложенные помощники и расширения), названию, имени исполняемого файла или издателю (у некоторых программ, например Amnezia, имя файла настроек не совпадает с идентификатором программы). Раньше такие настройки попадали в список на удаление и пропадали.
- Очистка мусора: всё, что не требует пароля администратора, теперь перемещается в Корзину, а не удаляется насовсем, поэтому ошибочную очистку можно отменить. Содержимое самой Корзины и системные файлы по-прежнему удаляются безвозвратно; окно подтверждения объясняет это.
- Очистка мусора, «Остатки удалённых приложений»: в список попадают только файлы, которыми владеет сам пользователь и которые можно удалить без пароля. Файлы других владельцев (root и т. д.) обычно принадлежат службе установленной программы, как у VPN-клиентов, и остатками не считаются.
- Версия 9.0.

### Version 9.0

**New**
- Video converter: a “Resolution” list — “Same as original” (default), 4K, 1080p, 720p, 480p, 360p and “Custom size…”. Presets set the short side of the frame (so vertical video works too), proportions are kept and smaller frames are not enlarged. A custom size takes width and height (checked to be whole numbers above zero) and fits the frame into that box. The old “Max Full HD” checkbox is replaced by “1080p”.
- Converters (video, audio, text): the actual output folder is now shown next to the “Folder…” button. With no folder chosen it is the source files' folder, or Downloads for files dragged in from other apps (it used to say “next to the original file” in every case). The “Reset” button is now “Next to original”: it returns saving to the source file's folder.
- Converters: dropped files are now taken by their real path straight from the drag pasteboard (and also via file:///.file/id=… links and URL objects) instead of being copied to a temporary folder, so “next to the original file” works instead of falling back to Downloads.
- All converters and the downloader got a “Clear Window” button: it removes every file from the queue (except the one being converted right now); in the downloader it clears the link, log and status.
- Maintenance: every task shows the exact command it will run; on failure the reason is shown (the last line of the command's output), and code 127 is explained as “command not found on this macOS version”. The “Run maintenance scripts” task is removed: the `periodic` tool no longer exists in newer macOS.
- Maintenance: five new tasks — rebuild the “Open With” list, clear the Quick Look and thumbnail cache, restart Dock, Finder and the menu bar, restart the audio service, restart Bluetooth. Each has a plain description of what it does and why.
- The “UnRar” tool is renamed “UnRAR, UnZip, 7z, GZ…” and can now create archives: an “Extract / Pack” switch. Pack files and folders into 7z, ZIP, TAR.GZ, TAR.BZ2 or TAR.XZ, with a compression level, name and folder. 7z and ZIP support a password (AES-256 for ZIP, 7z can also hide file names) and splitting into volumes (10, 25, 100, 700 MB, 1 and 4 GB or a custom size). Same 7-Zip engine. Creating RAR is not possible: the format is proprietary.
- Duplicates and similar photos: exclude folders right while marking files. The “Exclude folders…” button opens a tree of folders with checkboxes (untick one and the folder with everything inside leaves the results, groups left without repeats disappear), and every row has an “Exclude this folder from the search” button. Exclusions are remembered for future searches; “Include all” resets them.
- Duplicates and similar photos: you can mark and delete every copy of a group, not just the extras (one copy used to be always kept). The confirmation window warns in red how many groups will be left with no copy; “Select extras” still keeps one each.
- Archiver: the keyboard layout switches to English by itself while a password is typed (packing and extracting). ZIP accepts a password of Latin letters, digits and symbols only (7-Zip otherwise answered “E_INVALIDARG”): this is now checked up front, Russian letters get a red warning and “Pack” is disabled. A 7z password can be anything.
- The “About” tab in Settings now shows a separate end-user text (`AppReadme.md` / `AppReadme.ru.md`) instead of the developer README: the same two parts (“Features” and “Privacy and security”), rewritten for someone who just installed the app.
- Junk cleanup, “Leftovers of deleted apps”: a preferences file is no longer treated as orphaned if it fits any installed app: by identifier (including nested helpers and extensions), name, executable name or publisher (for some apps, such as Amnezia, the preferences file name differs from the app's identifier). Such settings used to land in the delete list and get lost.
- Junk cleanup: everything that does not need an administrator password is now moved to the Trash instead of being deleted permanently, so a wrong cleanup can be undone. The contents of the Trash itself and system files are still deleted permanently; the confirmation window explains this.
- Junk cleanup, “Leftovers of deleted apps”: only files owned by the user and deletable without a password are listed. Files owned by others (root and so on) usually belong to the service of an installed app, as with VPN clients, and are not leftovers.
- Version 9.0.

---

### Версия 8.2

**Новое**
- Кнопка «Заблокировать экран» на главном экране под «Свернуть все окна» (окно «Пуска» закрывается и экран блокируется, как по ⌃⌘Q).
- Телефоны по MTP: если телефон в первые секунды отдаёт пустой список хранилищ (бывает у Samsung), «Пуск» спрашивает ещё до пяти раз с паузой; в журнал `Pusk-MTP.log` пишется, сколько хранилищ ответил телефон; сообщение «Телефон не отдал хранилища» подсказывает про пункт Samsung, блокирующий подключение USB при заблокированном телефоне.
- Исправлено падение предпросмотра окон при наведении на Dock: опрос Dock больше не выполняется, когда курсор над окном самого «Пуска», а системный вызов обёрнут в собственный пул автоосвобождения.
- Двухпанельный менеджер: если в панели открыт поиск, F5/F6/F8 и другие команды теперь берут выбранный результат поиска, а не файл из списка под ним (раньше копирование из такой панели не срабатывало).
- Версия 8.2.

### Version 8.2

**New**
- A “Lock screen” button on the main screen under “Minimize all windows” (the Start window closes and the screen locks, like ⌃⌘Q).
- Phones over MTP: if a phone returns an empty storage list in the first seconds (seen on Samsung), Start asks up to five more times with a pause; `Pusk-MTP.log` now records how many storages the phone reported; the “The phone gave no storages” message also mentions the Samsung option that blocks USB connections while the phone is locked.
- Fixed a crash in the Dock window preview: the Dock probe is skipped while the cursor is over Start's own windows, and the system call runs inside its own autorelease pool.
- Two-pane manager: with a search open in a pane, F5/F6/F8 and other commands now act on the selected search result instead of the list underneath (copying from such a pane used to do nothing).
- Version 8.2.

---

### Версия 8.1

**Новое**
- **Автообновление.** Раз в сутки «Пуск» проверяет последний релиз на GitHub (TheBat1972/StartForMac); если вышла новая версия, в настройках появляется сообщение с описанием из релиза и кнопка «Обновить» (на значке настроек в «Пуске» загорается оранжевая точка; всплывающих окон нет). Обновление: скачивание StartForMac.zip из релиза, проверка подписи и идентификатора, замена программы в её папке и перезапуск. Включается и выключается в Настройки → «Интерфейс» → «Обновления» (по умолчанию включено), там же кнопка «Проверить сейчас»; есть пункт «Проверить обновления…» в меню программы. Релиз: тег вида `8.2` (подойдёт и `v8.2`), в файлах `StartForMac.zip`, в описании — что нового. Репозиторий должен быть открытым, иначе релизы не видны.
- Окно «О программе» показывает версию без второго номера в скобках; в настройках появилась вкладка «О программе» (значок, версия, авторские права) после вкладки «Раскладка».
- Вкладка «О программе» в настройках содержит прокручиваемое описание программы: разделы «Возможности» и «Приватность и безопасность» текущего README, русский или английский в зависимости от языка программы (при сборке `build.sh` кладёт README.md и README.ru.md в программу).
- Версия 8.1.

### Version 8.1

**New**
- **Automatic updates.** Once a day Start checks the latest GitHub release (TheBat1972/StartForMac); if a newer version is out a message with the release notes and an “Update” button appears in Settings (the settings icon in Start gets an orange dot; no pop-up windows). Updating downloads StartForMac.zip from the release, verifies the signature and identifier, replaces the app in its folder and restarts it. Toggle it in Settings → Interface → Updates (on by default), with a “Check now” button there and a “Check for updates…” item in the app menu. Release: a tag like `8.2` (`v8.2` works too), `StartForMac.zip` in the files, the notes in the description. The repository must be public, otherwise releases are not visible.
- The About window shows the version without the second number in parentheses; Settings has a new “About” tab (icon, version, copyright) after “Keyboard layout”.
- The “About” tab in Settings has a scrollable description of the app: the “Features” and “Privacy and security” sections of the current README, Russian or English depending on the app language (`build.sh` bundles README.md and README.ru.md into the app).
- Version 8.1.

---

### Версия 8.0

**Новое**
- **Диспетчер задач** (Инструменты): привычное окно как в Windows. Вкладка «Процессы»: «Приложения» и «Фоновые процессы» (процессы одной программы сгруппированы), столбцы «ЦП», «Память», «Диск» (чтение и запись), «Сеть» (приём и передача по процессам, данные даёт системная утилита nettop), «Энергопотребление» (условная оценка по нагрузке на процессор и пробуждениям) и число процессов; правый клик по заголовку выбирает столбцы; группы разворачиваются в отдельные процессы; сортировка по клику на заголовок, подсветка нагруженных, поиск, кнопка «Снять задачу» и меню правой кнопки («Снять задачу», «Принудительно завершить», «Развернуть», «Показать в Finder», «Скопировать путь»). Вкладка «Подробности»: таблица всех процессов (PID, имя, пользователь, состояние, ЦП, память, потоки, приоритет, родитель), сортировка, поиск, «Снять задачу», «Принудительно завершить», «Приостановить» и «Продолжить», «Понизить приоритет» и «Обычный приоритет». Вкладка «Производительность»: графики за последнюю минуту: ЦП (общий и по каждому ядру, модель, число потоков), память (состав: программы, закреплённая, сжатая, кэш, свободно; файл подкачки; давление памяти), диск (скорость чтения и записи, занятое место), сеть (приём и передача, выбор интерфейса, IP-адреса), видеокарта и батарея (заряд, циклы, состояние, время до разрядки или полного заряда; показываются, если есть в компьютере). Вкладка «Автозагрузка»: элементы входа и агенты запуска (LaunchAgents пользователя и всех пользователей, без системных Apple) со столбцами «Имя», «Тип», «Состояние»; кнопки «Отключить / Включить», «Добавить…» (программа в автозагрузку) и «Удалить…», меню правой кнопки, «Показать в Finder». Отключённый элемент входа убирается из системного списка и возвращается при включении, агент отключается со следующего входа (`launchctl disable`), удаляемый агент уходит в Корзину. Данные обновляются раз в секунду, пока окно открыто. Разрешений не требует; чужие системные процессы без прав завершить нельзя.
- **Диспетчер задач — управление и новые вкладки.** Правый клик по процессу: приостановить / продолжить, приоритет (выше и ниже обычного; повышение просит пароль администратора), показать в Finder, скопировать путь. Перед завершением системного процесса и самого «Пуска» — предупреждение. Автоматические действия (кнопка с молнией): если процесс держит больше N % ЦП дольше заданного времени, придёт уведомление или задача будет снята. Кнопки справа от вкладок: окно поверх остальных и значок в строке меню с мини-графиком ЦП. Вкладки: «Журнал» (накопленное время ЦП, сеть и диск по программам с даты сброса), «Пользователи» (появляется, только если на Маке работают несколько учётных записей), «Службы» (демоны и агенты launchd с запуском, остановкой и перезапуском).

**Улучшения**
- Окно разрешений приведено в порядок: у каждого разрешения есть кнопка «Открыть настройки» прямо в нужный раздел Системных настроек; добавлены «Управление приложениями» и «Файлы и папки»; «Данные других приложений» объединено с «Полным доступом к диску»; «Мониторинг ввода» больше не показывает «Выдан», когда это не так.
- Сочетание ручного исправления раскладки теперь исправляет и набираемое слово, и последнее набранное: раньше сама комбинация стирала слово из памяти до того, как успевала сработать.
- Автоматический переключатель раскладки стал умнее: короткие слова перед исправленным («И вот», «А кто это?») теперь исправляются вместе с ним, а не остаются в неверной раскладке; слова с дефисом («что-то», «кто-нибудь») исправляются по частям; знаки после слова («привет.», «привет?», «привет!») набираются правильно; адреса сайтов («github.com») не трогаются; при смене программы набираемое слово и память об исправлении сбрасываются.
- Повторные нажатия сочетания переключают слово туда и обратно: после автоисправления, после исправления набираемого или последнего слова и после исправления выделенного текста (он остаётся выделенным) каждое следующее нажатие меняет раскладку слова, сколько раз ни нажми, пока не набран следующий символ. Слово, которое вернули к набранному виду после автоисправления, больше автоматически не исправляется (до 500 слов); вернули снова — оно опять исправляется.
- «Arcan»: надписи читаются на любом фоне — под шапкой, подвалом и рекордами тёмные подложки, у текста тень, поле затемнено сильнее.
- **Новая игра «Arcan»** в меню «Передохни» — классический арканоид, перенесённый с Qt/C++: бита управляется мышью или стрелками/A·D, шар отскакивает под углом в зависимости от места удара. Кирпичи бывают в 1, 2 и 3 удара, а бонусные дают эффекты: неубиваемая стенка снизу, большой пробивной шар с широкой битой, ускорение, замедление, ещё один шар и сброс эффектов. Три жизни, уровни со всё более плотными стенками, фон меняется на каждом уровне. Картинки и звуки взяты из оригинала (папка `ArcanRes`), справа таблица 12 лучших результатов, имя спрашивается в конце игры.
- **Настройки — отдельное окно с вкладками** (раньше плашка внутри «Пуска»): «Интерфейс» (язык, тема, значки, значок в верхней панели, запуск при входе, окно «Пуска», конвертер валют), «Управление» (горячие клавиши, жест, умный буфер обмена), «Окна» («Свернуть всё», окна по ⌃⌥ + стрелки, ⌥Tab, миниатюры, окна над значком в Dock), «Finder и рабочий стол» (чистый рабочий стол, ⌘X, Enter, «Создать») и «Раскладка». Окно больше, меняет размер и запоминает положение; кнопка «Разрешения…» слева внизу; открывается шестерёнкой в «Пуске», из меню значка и по ⌘, .
- **Enter в Finder открывает файл** (настройка «Enter в Finder — открыть файл», по умолчанию выключена): Enter запускает выделенные файлы и открывает папки, как в Windows; переименование — ⇧Enter, контекстное меню или щелчок по имени. В полях ввода, диалогах и листах Enter остаётся обычным. При включении программа сама просит «Управление устройством и доступ к данным».
- **«Создать» в контекстном меню Finder** (настройка «Создать» в контекстном меню Finder, по умолчанию выключена): правый клик по пустому месту рабочего стола или окна Finder даёт подменю «Создать» — текстовый документ, документ Markdown, пустой файл, страница HTML, файл JSON, таблица CSV, документ RTF, а также документ, таблица и презентация — для тех офисных программ, что установлены (Word, Excel, PowerPoint, Pages, Numbers, Keynote, LibreOffice, OnlyOffice, WPS; программы ищутся при каждом правом клике, настраивать ничего не нужно; пустые заготовки лежат в `FinderTemplates`); новый файл сразу выделяется. Реализовано расширением Finder Sync (`FinderExt/`, внутри приложения `StartFinderExt.appex`, песочница), файлы создаёт само приложение. Расширение Finder не показывает пункты внутри iCloud Drive, поэтому на рабочем столе с включённой синхронизацией «Рабочий стол и документы» его нет; для этого случая то же меню «Создать» (те же типы файлов) вызывается сочетанием клавиш (по умолчанию ⌃⌥N, меняется в настройках) и есть в меню значка «Пуска» в строке меню и в Dock (правая кнопка): файл создаётся в папке активного окна Finder, а если окна нет — на рабочем столе. То же подменю «Создать» есть в правом клике по пустому месту нового чистого рабочего стола (файл создаётся в папке этого стола). При включении программа просит включить расширение (подсказка и список расширений Finder), на вкладке «Разрешения» появилась строка «Расширение Finder» со статусом.
- **Новая игра «Pacman»** в меню «Передохни» — классический Пакман, перенесённый с Qt/C++: два лабиринта оригинала (случайно), пять привидений, точки, таблетки (привидения становятся съедобными на 8 секунд и мигают перед концом), порталы по краям. Пакман и привидения ходят плавно, а не по клеткам, а Пакман на ходу жуёт — рот открывается и закрывается (при гибели раскрывается и исчезает); можно мгновенно развернуться посреди коридора. Три жизни, уровни с растущей скоростью, таблица 12 лучших результатов, управление стрелками/WASD, пробел — пауза; скорость по умолчанию умеренная, кнопка «Сложность» (легко / нормально / трудно) меняет её (на «Легко» и «Нормально» привидений четыре, на «Трудно» пять) и запоминается (картинки и звуки в папке `PacmanRes`).
- «Diam»: кристалл можно тащить и по диагонали; если он вернулся на прежнее место (или поменялся с кристаллом того же цвета), новая линия не добавляется.
- «Diam»: вместе с тройкой в ряд исчезают все связанные с ней по сторонам кристаллы того же цвета (по диагонали связи нет); квадрат 2×2 без тройки в ряд не исчезает.
- **Новая игра «Diam»** в меню «Передохни» — игра с кристаллами, переписанная с iOS: поле 6×16, кристалл перетаскивается мышью на соседнюю клетку (меняется с соседом или съезжает в пустоту), после каждого хода сверху появляется новая линия. Три в ряд исчезают вместе со всеми связанными с ними по сторонам кристаллами того же цвета, цепочки считаются, за большие серии (больше пяти) — бонус. Столбик дорос до верха — конец игры. Режимы «5 цветов» и «4 цвета» с отдельными таблицами 12 лучших результатов, искры при исчезновении, случайные звуки и фон-текстура из оригинала (папка `DiamRes`).
- «Arcan»: звук отскока от биты теперь тот же, что при отскоке от кирпичей и стенок.
- **Новая игра «Snake»** в меню «Передохни» — змейка на мультяшной графике и звуках из iOS-игры «Удафф» (папка `SnakeRes`): поле 24×20 с бордюром, 12 кустов репейника, фрукты каждые 3,7 с ускоряют змею, подарок даёт бонусные очки, немного замедляет змею и укорачивает хвост на 10% (но не короче трёх шариков); фрукт съедается с одинаковым хрустом. Змея ползёт плавно и анимирует поедание: открывает рот, когда еда рядом, фрукт втягивается и исчезает во рту, по телу бежит «комок», а дойдя до хвоста — змея вырастает. Девять скинов (кнопка «Скин»); стрелки или WASD (в любой раскладке) либо щелчок мышью — поворот, пробел или P — пауза; таблица 12 лучших результатов справа, имя спрашивается в конце игры.
- «Lode Runner»: короткое нажатие в сторону, противоположную бегу, только разворачивает бегуна без шага, а удержание — разворачивает и сразу бежит без паузы; копание стало быстрее на 50%.
- Диспетчер задач: при открытии список процессов иногда оставался пустым, пока не переключишь вкладку; теперь содержимое обновляется, как только приходят первые данные.
- Красные пояснения в настройках и в окне разрешений (про запись экрана и системного звука) теперь обычного серого цвета, как остальные.
- «Свернуть всё» теперь сворачивает и «Пуск» с его программами (возвращаются так же). В настройках новый переключатель «Не сворачивать «Пуск» и его программы»: включишь — они остаются на месте, как раньше; по умолчанию выключен.
- «Свернуть всё» больше не вылетает при сворачивании «Пуска» и его программ: свои окна сворачиваются средствами самой программы, а само окно «Пуска» закрывается (кроме случая, когда «Свернуть всё» нажато кнопкой внутри «Пуска»: тогда главное окно остаётся).
- Настройки открываются и из меню программы на верхней панели («Настройки…», ⌘,): появляется окно «Пуска» сразу на настройках. Такой же пункт есть в меню значка «Свернуть всё» в строке меню.
- Новый чистый рабочий стол понимает динамические обои macOS со сменой по времени суток (по положению солнца, по времени или по светлой/тёмной теме): берётся кадр под текущее время; пока новый стол существует, кадр обновляется снимком при смене обоев (система сообщает об этом сама, без постоянного опроса) и раз в 5 минут (с разрешением на запись экрана это работает и для новых динамических обоев macOS). Положение солнца считается приблизительно (долгота по часовому поясу). Анимированные обои-видео по-прежнему показываются одним кадром.
- Новый чистый рабочий стол берёт обои основного стола: после смены обоев на основном столе новые столы больше не показывают старые (обои считываются один раз, в момент создания стола).
- После удаления нового стола и вопроса про его файлы всё запомненное (окно, счётчики проверки, обои) сбрасывается, и следующий новый стол начинает с нуля.
- Новый чистый рабочий стол снимает обои иначе: всё, что система рисует под значками рабочего стола, одним снимком (раньше искалось одно окно обоев, а у новых обоев macOS такого окна может не быть). Что нашлось, пишется в «wallpaper-debug.txt» в папке настроек «Пуска».
- Умный буфер обмена умеет запоминать историю между запусками (Настройки → «Управление», по умолчанию выключено): текст, картинки, файлы и закрепления восстанавливаются после перезапуска (хранится на диске в Application Support без шифрования, пароли по-прежнему пропускаются; при выключении настройки сохранённая история стирается).
- «Создать»: подменю «Изображение» → PNG, JPEG, SVG (всегда), а также Photoshop (.psd), GIMP (.xcf) и Krita (.kra), если есть подходящая программа → размер 1920×1080, 1024×1024, 512×512 или «Свой размер…» (вводится, запоминается последний); меню и в Finder, и по горячей клавише, и в меню значка, и на новом чистом столе.
- Меню «Инструменты» больше не вылезает за окно «Пуска»: сверху остаётся столько же места, сколько снизу, а длинный список (например, при раскрытых играх «Передохни») прокручивается.
- Версия 8.0.

### Version 8.0

**New**
- **Task Manager** (Tools): a familiar Windows-style window. “Processes” tab: “Apps” and “Background processes” (processes of one app are grouped), columns CPU, Memory, Disk (read and write), Network (received and sent per process, data from the system nettop tool), Energy impact (an estimate from CPU load and wake-ups) and process count; right-click a header to choose columns; groups expand into individual processes; click a header to sort, heat tint for busy ones, search, an “End task” button and a right-click menu (“End task”, “Force quit”, “Expand”, “Show in Finder”, “Copy path”). “Details” tab: a table of all processes (PID, name, user, state, CPU, memory, threads, nice, parent) with sorting, search, End task, Force quit, Suspend and Resume, Lower priority and Normal priority. “Performance” tab: last-minute graphs: CPU (overall and per core, model, thread count), memory (composition: apps, wired, compressed, cached, free; swap; memory pressure), disk (read and write speed, used space), network (received and sent, interface picker, IP addresses), GPU and battery (charge, cycles, health, time to empty or full; shown when the computer has them). “Startup” tab: login items and launch agents (the user’s and all users’ LaunchAgents, without Apple’s own) with Name, Type and Status columns; “Disable / Enable”, “Add…” (an app to startup) and “Remove…” buttons, a right-click menu and “Show in Finder”. A disabled login item is removed from the system list and comes back when enabled; an agent is disabled from the next login (`launchctl disable`); a removed agent goes to the Trash. Updated once a second while the window is open. No permissions needed; system processes you have no rights to cannot be ended.
- **Task Manager — control and new tabs.** Right-click a process: suspend / resume, priority (above and below normal; raising it asks for the administrator password), show in Finder, copy path. A warning appears before ending a system process or Start itself. Automatic actions (bolt button): if a process holds more than N % CPU for longer than a set time, you get a notification or the task is ended. Buttons right of the tabs: keep the window on top and a menu-bar icon with a mini CPU graph. Tabs: “History” (accumulated CPU time, network and disk per app since the last reset), “Users” (shown only when the Mac has several accounts), “Services” (launchd daemons and agents with start, stop and restart).

**Improvements**
- The permissions window has been tidied up: every permission has an “Open Settings” button that goes straight to the right Settings pane; App Management and Files & Folders were added; “Other apps’ data” was merged into Full Disk Access; Input Monitoring no longer shows “Granted” when it is not.
- The manual layout-fix shortcut now fixes both the word being typed and the last typed word: before, the combination itself cleared the word from memory before it could act.
- The automatic layout switcher got smarter: short words before a corrected one (“И вот”, “А кто это?”) are now fixed together with it instead of staying in the wrong layout; hyphenated words (“что-то”, “кто-нибудь”) are fixed part by part; punctuation after a word (“привет.”, “привет?”, “привет!”) is typed correctly; website addresses (“github.com”) are left alone; switching to another app resets the word being typed and the undo memory.
- Pressing the shortcut again toggles the word back and forth: after an auto-fix, after fixing the word being typed or the last word, and after fixing selected text (it stays selected), every further press switches the word’s layout as many times as you press, until the next character is typed. A word you return to its typed form after an auto-fix is no longer fixed automatically (up to 500 words); switch it again and it is fixed again.
- “Arcan”: text is readable on any background — dark plates under the header, footer and records, a shadow on the text, a darker field.
- **New game “Arcan”** in the “Take a Break” menu — a classic Arkanoid ported from Qt/C++: the paddle follows the mouse or arrows/A·D, the ball bounces at an angle that depends on where it hits. Bricks take 1, 2 or 3 hits, and bonus bricks give effects: an indestructible wall at the bottom, a big piercing ball with a wide paddle, speed-up, slow-down, an extra ball and an effect reset. Three lives, levels with denser walls, the background changes each level. Pictures and sounds come from the original (the `ArcanRes` folder), a top-12 records table sits on the right, the name is asked at the end of the game.
- **Settings are a separate window with tabs** (they used to be a panel inside Start): “Interface” (language, theme, icons, menu-bar icon, launch at login, the Start window, currency converter), “Controls” (hotkeys, gesture, smart clipboard), “Windows” (Minimize all, windows by ⌃⌥ + arrows, ⌥Tab, thumbnails, windows over the Dock icon), “Finder and desktop” (clean desktop, ⌘X, Enter, “Create”) and “Keyboard layout”. The window is larger, resizable and remembers its position; a “Permissions…” button sits at the bottom left; it opens from the gear in Start, from the icon menu and with ⌘, .
- **Enter in Finder opens the file** (the “Enter in Finder — open file” setting, off by default): Enter launches the selected files and opens folders, as in Windows; rename with ⇧Enter, the context menu or by clicking the name. In text fields, dialogs and sheets Enter stays as usual. When turned on, the app asks for the “Accessibility” permission itself.
- **“Create” in Finder's context menu** (the “Create” in Finder's context menu setting, off by default): a right-click on an empty spot of the desktop or a Finder window gives a “Create” submenu — text document, Markdown document, empty file, HTML page, JSON file, CSV table, RTF document, plus a document, spreadsheet and presentation for the office suites that are installed (Word, Excel, PowerPoint, Pages, Numbers, Keynote, LibreOffice, OnlyOffice, WPS; they are looked up on every right-click, nothing to set up; the blank files live in `FinderTemplates`); the new file is selected right away. Built as a Finder Sync extension (`FinderExt/`, `StartFinderExt.appex` inside the app, sandboxed); the files are created by the app itself. The Finder extension is not shown inside iCloud Drive, so it is absent on a desktop with “Desktop & Documents” sync on; for that case the same “Create” menu (the same file types) is opened with a shortcut (⌃⌥N by default, changeable in settings) and is in the menu of the Start icon in the menu bar and in the Dock (right-click): the file is created in the folder of the active Finder window, or on the desktop if there is none. The same “Create” submenu is in the right-click menu of an empty spot on the new clean desktop (the file is created in that desktop's folder). When turned on, the app asks to enable the extension (a hint and the list of Finder extensions), and the “Permissions” tab got a “Finder extension” row with its status.
- **New game “Pacman”** in the “Take a Break” menu — the classic Pac-Man ported from Qt/C++: the two original mazes (random), five ghosts, dots, power pills (ghosts become edible for 8 seconds and blink before it ends), portals at the edges. Pac-Man and the ghosts move smoothly instead of cell by cell, and Pac-Man chomps as he goes — his mouth opens and closes (on death it opens wide and fades); you can turn around instantly in mid-corridor. Three lives, levels with growing speed, a top-12 records table, arrows/WASD to steer, Space pauses; the default speed is moderate, and the “Difficulty” button (easy / normal / hard) changes it (on “Easy” and “Normal” there are four ghosts, on “Hard” five) and is remembered (pictures and sounds in the `PacmanRes` folder).
- “Diam”: gems can also be dragged diagonally; if a gem returns to its old place (or swaps with a gem of the same colour), no new line is added.
- “Diam”: a line of three vanishes together with every same-colour gem linked to it by sides (no link diagonally); a 2×2 square without a line of three stays.
- **New game “Diam”** in the “Take a Break” menu — the gem game rewritten from iOS: a 6×16 field, drag a gem with the mouse to a neighbouring cell (it swaps with the neighbour or slides into the empty space), and a new line appears on top after every move. Three in a row vanish together with every same-colour gem linked to them by sides, chains are counted, big runs (more than five) give a bonus. A column reaching the top ends the game. “5 colours” and “4 colours” modes with separate top-12 tables, sparks when gems vanish, random sounds and the texture backgrounds of the original (the `DiamRes` folder).
- “Arcan”: the paddle bounce sound is now the same as for bricks and walls.
- **New game “Snake”** in the “Take a Break” menu — a snake with the cartoon graphics and sounds of the iOS game “Udaff” (the `SnakeRes` folder): a 24×20 field with a border, 12 thistle bushes, fruit every 3.7 s speeds the snake up, a gift gives bonus points, slows the snake down a little and shortens the tail by 10% (but never below three segments); every fruit is eaten with the same crunch. The snake glides smoothly and animates eating: it opens its mouth when food is close, the fruit is sucked in and vanishes in the mouth, a lump runs down the body and the snake grows when it reaches the tail. Nine skins (the “Skin” button); arrows or WASD (any layout) or a mouse click turn, Space or P pauses; a top-12 table on the right, the name is asked at the end of the game.
- “Lode Runner”: a short tap in the direction opposite to the run only turns the runner around without a step, while holding the key turns and runs at once with no pause; digging is 50% faster.
- Task Manager: the process list sometimes stayed empty on opening until you switched tabs; it now refreshes as soon as the first data arrives.
- The red notes in Settings and in the permissions window (about Screen & System Audio Recording) now use the regular grey colour like the rest.
- “Minimize All”: now also minimizes Start and its tools (restored the same way). A new Settings switch “Don’t minimize Start and its tools”: turn it on and they stay in place, as before; off by default.
- “Minimize All” no longer crashes when minimizing Start and its tools: the app’s own windows are minimized by the app itself, and the Start window itself is closed (except when “Minimize All” is pressed with the button inside Start: then the main window stays).
- Settings also open from the app menu in the menu bar (“Settings…”, ⌘,): the Start window appears right on the settings. The same item is in the menu of the “Minimize All” menu-bar icon.
- The new clean desktop understands macOS dynamic wallpapers that change through the day (by sun position, time or light/dark appearance): it picks the frame for the current time; while a new desktop exists, the frame is refreshed with a screenshot when the wallpaper changes (the system reports it itself, no polling) and every 5 minutes (with the Screen Recording permission this also works for new macOS dynamic wallpapers). The sun position is approximate (longitude from the time zone). Animated video wallpapers are still shown as a single frame.
- The new clean desktop takes the main desktop’s wallpaper: after you change the wallpaper on the main desktop, new desktops no longer show the old one (the wallpaper is read once, when the desktop is created).
- After a new desktop is removed and its files are dealt with, everything remembered (window, check counters, wallpaper) is reset, so the next new desktop starts from scratch.
- The new clean desktop captures the wallpaper differently: everything the system draws under the desktop icons in one shot (before, a single wallpaper window was looked up, which new macOS wallpapers may not have). What was found is written to “wallpaper-debug.txt” in Start’s settings folder.
- The smart clipboard can remember its history between launches (Settings → Control, off by default): text, images, files and pins are restored after a restart (stored unencrypted in Application Support, passwords are still skipped; turning the setting off erases the saved history).
- “Create”: an “Image” submenu → PNG, JPEG, SVG (always), plus Photoshop (.psd), GIMP (.xcf) and Krita (.kra) when a suitable app is installed → 1920×1080, 1024×1024, 512×512 or “Custom size…” (typed in, the last one is remembered); in Finder, the shortcut menu, the Start icon menu and the new clean desktop.
- The Tools menu no longer overflows the Start window: it leaves the same gap at the top as at the bottom, and a long list (for example with the “Take a break” games expanded) scrolls.
- Version 8.0.

---

### Версия 7.0

**Новое**
- **Автоматический переключатель раскладки** (Настройки, выключен по умолчанию; при включении «Пуск» запрашивает доступ «Управление устройством и доступ к данным»): слово, набранное не в той раскладке («ghbdtn»), после пробела, Tab или Enter заменяется на правильное («привет») и раскладка переключается. Решает системная проверка орфографии, слово исправляется только если набранный вариант не слово, а вариант в другой раскладке слово. Автоисправление можно отключить. Сочетание (по умолчанию ⌃⌥Пробел, меняется в настройках) исправляет слово, которое набираете, выделенный текст или последнее слово. Список программ, в которых переключатель не работает (по умолчанию Терминал, iTerm, Xcode, VS Code, Warp), редактируется в настройках. Набранный текст не хранится и не передаётся, в памяти только текущее слово.
- **Своя клавиша переключения раскладки** (отдельный блок в настройках, не зависит от автоматического переключателя): Globe/fn переключает раскладку сразу, без большой плашки macOS. Для Globe в Системных настройках → Клавиатура → «Нажатие 🌐 для» нужно выбрать «Ничего не делать»; для Globe программа запрашивает доступ «Управление устройством и доступ к данным».
- **Скрыть системную плашку раскладки у курсора** (Настройки): убирает маленькую плашку с буквой («A», «Р») под текстовым курсором, которую macOS (Sonoma и новее) показывает при смене раскладки: она часто запаздывает и показывает не ту раскладку, а флаги «Пуска» берут раскладку напрямую из системы. Если не исчезла сразу — перезапустить программу, в которой печатаете, или перезайти в систему.
- **Флаг раскладки на экране** (встроенный LangFlag, выключен по умолчанию): маленький флаг поверх окон показывает текущую раскладку; клик — следующая раскладка, перетаскивание, размер и возврат в угол через правую кнопку. Разрешений не требует. Тот же флажок можно показать и в строке меню macOS рядом с часами (отдельный выключатель; клик — следующая раскладка, правая кнопка — убрать), выключатель независим от автоматического переключателя раскладки и стоит в настройках выше флага на экране.
- **Окна при наведении на значок в Dock** (Настройки, выключено по умолчанию): если задержать курсор на значке запущенного приложения (около 0,3 с), над значком появляются его окна, в том числе свёрнутые. Клик выводит окно вперёд; на плитке под курсором кнопки «закрыть», «свернуть», «на весь экран». Миниатюры — по выключателю «Миниатюры окон», без разрешения вместо них значки. Нужен доступ «Управление устройством и доступ к данным». Панель не шире двух плиток: следующие окна идут новыми рядами (если ряды не помещаются по высоте экрана, плитки уменьшаются). Снимок окна сохраняется, только когда окно неподвижно: окно в момент сворачивания («джинн») не попадает в миниатюру. Контекстное меню значка (правая кнопка) важнее панели: пока оно открыто, панель не показывается. Для свёрнутых окон показывается приглушённая миниатюра: программа снимает окно, не разворачивая его; если снимок не подходит по пропорциям (искажённый кадр анимации сворачивания) или не получился, берётся последний нормальный снимок, сделанный, пока окно было на экране.
- **Поиск в ⌥Tab (всегда включён):** пока зажат Option, можно печатать название окна или программы — список сужается; ⌫ стирает, ↑↓←→ и Enter выбирают. Поиск не зависит от регистра и раскладки («хром» и «xhjv» находят одно и то же). В списке есть и свёрнутые окна (в конце, с пометкой «— свёрнуто»). Кнопки «закрыть / свернуть / на весь экран» на плитках окон.
- Везде, где запрашивается «Запись экрана и системного звука», в настройках красным написано, для чего (только снимки окон и обоев; звук не записывается).
- **Новые чистые рабочие столы:** на верхней панели «Пуска» справа от замка появляется кнопка «+». Нажатие создаёт новый рабочий стол macOS и переходит на него. На новом столе — собственное окно программы: оно закрывает значки Finder копией обоев и показывает свои значки (файлы лежат в обычной локальной папке «Рабочие столы/Стол N» в домашней папке). Файлы основного стола не затрагиваются, на диске при переключении ничего не меняется, поэтому всё появляется мгновенно и iCloud ничего не перекачивает. Значки можно расставлять в любое место стола (по сетке), положение запоминается; файлы можно перетащить на новый стол из Finder (они переносятся, значок встаёт туда, куда отпустили) и обратно, работают ⌘C, ⌘V и (если включено «⌘X — вырезать») ⌘X, двойной щелчок открывает файл, есть контекстное меню (открыть, показать в Finder, перенести на основной стол, в Корзину, новая папка, обновить и сменить фон). Список столов запоминается: после перезапуска «Пуска» окна возвращаются. Если новый стол удалить (в Mission Control) — или его уже нет при запуске программы, — программа спросит, что сделать с его файлами: переместить в Корзину, перенести на основной стол или оставить папку. Включается в Настройках → «Система» (по умолчанию выключено); нужно разрешение «Управление устройством и доступ к данным» (в ранних версиях macOS: «Универсальный доступ»; программа сама нажимает «+» в Mission Control); точная копия обоев — с разрешением «Запись экрана и системного звука», без него берётся файл обоев. «Полный доступ к диску» больше не нужен; файлы, спрятанные прежней версией, при первом запуске возвращаются.

**Улучшения**
- Значок разрешений на верхней панели (рядом с чашкой) теперь показывает все запрашиваемые разрешения со статусами: полный доступ к диску, «Управление устройством и доступ к данным», «Запись экрана и системного звука» (красным написано, для чего) и «Мониторинг ввода» (статус читается из базы разрешений, а без полного доступа к диску показывается «Статус недоступен», потому что macOS отвечает «да» и при одном «Универсальном доступе»; обычно это разрешение не нужно), а также подсказки про «Управление приложениями» и «Файлы и папки» (статус система программам не показывает, есть кнопка «Открыть настройки»); у каждого есть кнопка «Открыть настройки» (ведёт в нужный раздел Системных настроек), у невыданных ещё «Запросить» и «Проверить снова». Кнопка «Разрешения…» из настроек убрана.
- В левой колонке «Новая категория» опущена вплотную к «Свернуть все окна»; освободившееся место отдано списку категорий.
- Внизу панели «Пуска» в быстрых вызовах программ пять мест вместо четырёх: пятое по умолчанию пустое, с плюсом (промежутки между значками чуть уменьшены, чтобы всё поместилось).
- Флаги раскладки (на экране и в строке меню) обновляются сразу после проверки переключения: если macOS не прислала уведомление о смене раскладки, флаг всё равно покажет верную.
- Переключение раскладки при автоисправлении слов, по сочетанию исправления, флажком и клавишей Globe проверяется: если macOS «потеряла» переключение (частая ошибка сразу после перехода в поле ввода), оно повторяется (до трёх раз).
- В настройках разделы и группы параметров разделены тонкими полупрозрачными линиями.
- Версия 7.0.

---

### Version 7.0

**New**
- **Automatic keyboard layout switcher** (Settings, off by default; when switched on, Start asks for the “Accessibility” permission): a word typed in the wrong layout (“ghbdtn”) is replaced by the right one (“привет”) after Space, Tab or Enter and the layout is switched. The system spell checker decides: a word is fixed only if what was typed is not a word and the other-layout version is. Automatic fixing can be turned off. A shortcut (⌃⌥Space by default, changeable in Settings) fixes the word you are typing, the selected text or the last word. A list of apps where the switcher does not work (Terminal, iTerm, Xcode, VS Code and Warp by default) is editable in Settings. Typed text is never stored or sent; only the current word is kept in memory.
- **Own layout switch key** (a separate block in Settings, independent of the automatic switcher): Globe/fn switches the layout at once, without the big macOS popup. For Globe, set System Settings → Keyboard → “Press 🌐 key to” to “Do Nothing”. Globe needs the “Accessibility” permission.
- **Hide the system layout popup near the cursor** (Settings): removes the small popup with a letter (“A”, “Р”) under the text cursor that macOS (Sonoma and newer) shows when the layout changes: it often lags and shows the wrong layout, while Start’s flags read the layout straight from the system. If it does not disappear at once, restart the app you type in or log out and back in.
- **Layout flag on screen** (built-in LangFlag, off by default): a small flag over all windows shows the current layout; click for the next layout, drag to move, right-click for size and to return it to the corner. No permissions needed. The same flag can also be shown in the macOS menu bar next to the clock (a separate toggle; click for the next layout, right-click to remove it), its toggle is independent of the automatic layout switcher and sits above the on-screen flag in Settings.
- **Windows when hovering an icon in the Dock** (Settings, off by default): hold the cursor on a running app’s icon (about 0.3 s) and its windows, including minimized ones, appear above the icon. Click to bring a window to the front; the tile under the cursor has “close”, “minimize” and “full screen” buttons. Thumbnails follow the “Window thumbnails” toggle; without the permission app icons are shown. Needs the “Accessibility” permission. The panel is never wider than two tiles: more windows go into new rows (tiles shrink only if the rows would not fit the screen height). A window snapshot is saved only while the window is still, so a window caught mid-minimize (the genie effect) never ends up as a thumbnail. The right-click context menu of a Dock icon takes priority: the panel is not shown while it is open. Minimized windows show a dimmed thumbnail: the app captures the window without restoring it; if the capture has the wrong proportions (a distorted frame of the minimize animation) or fails, the last good snapshot taken while the window was on screen is used.
- **Search in ⌥Tab (always on):** while Option is held, type part of a window or app name to narrow the list; ⌫ erases, arrow keys and Enter choose. Search ignores case and keyboard layout (typing in Russian or English finds the same window). Minimized windows are listed too (at the end, marked “— minimized”). “Close / minimize / full screen” buttons on window tiles.
- Wherever “Screen & System Audio Recording” is requested, Settings now says in red what it is for (window and wallpaper snapshots only; no audio is recorded).
- **New clean desktops:** a “+” button appears in the top bar of Start, to the right of the lock. Pressing it creates a new macOS desktop and switches to it. The new desktop gets its own app window: it covers the Finder icons with a copy of the wallpaper and shows its own icons (the files live in a regular local folder “Desktops/Desktop N” in your home folder). The files of the main desktop are not touched and nothing is written to disk when you switch, so everything appears instantly and iCloud transfers nothing. Icons can be arranged anywhere on the desktop (snapped to a grid) and their positions are remembered; drag files onto the new desktop from Finder (they are moved and land where you drop them) and back; ⌘C, ⌘V and (with “⌘X — cut” on) ⌘X work, double-click opens a file, and there is a context menu (open, show in Finder, move to the main desktop, Trash, new folder, refresh and change the wallpaper). The list of desktops is remembered: the windows come back after Start is restarted. If a new desktop is deleted (in Mission Control) — or is already gone when the app starts — the app asks what to do with its files: move to the Trash, move to the main desktop, or keep the folder. Turn it on in Settings → “System” (off by default); needs the “Accessibility” permission (the app presses “+” in Mission Control itself); an exact wallpaper copy needs “Screen & System Audio Recording”, without it the wallpaper file is used. “Full Disk Access” is no longer needed; files hidden by the previous version are restored on first launch.

**Improvements**
- The permissions icon in the top bar (next to the cup) now lists every permission Start asks for with its status: Full Disk Access, Accessibility, Screen & System Audio Recording (in red, with its purpose) and Input Monitoring (its status is read from the permission database, and without Full Disk Access it shows “Status unavailable”, because macOS answers “yes” even with Accessibility alone; usually not needed), plus notes for App Management and Files & Folders (the system does not expose their status; with an “Open Settings” button); every one has an “Open Settings” button that leads to the right Settings pane, missing ones also “Request” and “Check again”. The “Permissions…” button is gone from Settings.
- In the left column “New category” sits right above “Minimize all windows”; the freed space goes to the category list.
- The quick-launch bar at the bottom of the Start panel now has five slots instead of four: the fifth is empty by default, with a plus (gaps between icons are slightly smaller so everything fits).
- The layout flags (on screen and in the menu bar) are updated right after the switch check: if macOS does not send the layout-change notification, the flag still shows the right layout.
- Layout switching when fixing words automatically, by the fix shortcut, by the flag and by the Globe key is verified: if macOS “lost” the switch (a common bug right after focusing a text field), it is repeated (up to three times).
- Settings sections and groups are separated by thin semi-transparent lines.
- Version 7.0.

---

---

### Версия 6.0

**Программа переименована в StartForMac** (`StartForMac.app`: имя в меню, «О программе», Dock и сообщениях). После копирования новой версии в папку «Программы» старую «Пуск» нужно удалить. Настройки, разрешения и список сайтов сохраняются: идентификатор программы прежний. Автозапуск при входе обновляется сам, значок в Dock нужно закрепить заново.

**Новое**
- **Умный буфер обмена:** история последних копирований — текст, картинки и файлы, на 3, 5 или 10 записей (выбор в настройках). Открывается по ⇧⌘V списком у курсора (стрелки или цифры, Enter вставляет, P закрепляет, ⌫ убирает) и значком буфера на верхней панели «Пуска» (клик копирует запись). Закреплённые записи не вытесняются и не считаются в лимите. Пароли не сохраняются: пропускаются скрытые копии и программы-менеджеры паролей; история только в памяти и исчезает при выходе. Включается в Настройках → «Система» (по умолчанию выключено); при включении запрашивается доступ «Управление устройством и доступ к данным» (в ранних версиях macOS: «Универсальный доступ») для автоматической вставки.
- Меню «Инструменты» сдвинуто вправо: его левый край на уровне рамки быстрых вызовов.
- **Калькулятор** убран из «Инструментов» и вынесен на верхнюю панель — значок справа от чашки.
- **Настройки:** выключатели выровнены по правому краю, две нижние кнопки одинаковой ширины и по центру окна.
- **UnRar** (Инструменты): распаковка архивов — RAR и RAR5, 7z, ZIP (в т. ч. с шифрованием), TAR, GZ, BZ2, XZ, ISO, DMG, CAB, ARJ, LZH, WIM и другие. Поддерживаются пароль (если архив защищён, в строке появляется поле для пароля, при неверном — повторный ввод) и многотомные архивы: можно выбрать любой том (.part2.rar, .r01, .7z.002 …) — распаковка начнётся с первого. Архивы добавляются кнопкой или перетаскиванием, распаковываются по очереди с индикатором; результат — рядом с архивом (в папку с его именем) или в выбранную папку. Движок — консольный 7-Zip: берётся из системы, а если его нет, скачивается при первом открытии.
- **Дубликаты и похожие фото** (Инструменты): точные дубликаты ищутся по содержимому (SHA-256), похожие снимки — по уменьшенному «отпечатку» картинки; жёсткие ссылки не считаются копиями. Отмечаете лишнее вручную или кнопкой «Выбрать лишние» (у дубликатов остаётся самая старая копия, у фото — с наибольшим разрешением), в каждой группе всегда остаётся хотя бы одна копия; в Корзину уходит только отмеченное. Папку можно выбрать или перетащить в окно, у файла есть предпросмотр Quick Look.
- **Анализатор диска:** коллектор (значок лотка у объекта или перетаскивание вниз — собрать лишнее и убрать в Корзину одним действием, с суммой освобождаемого места), анализ любой папки или диска («Выбрать папку…» или перетаскивание папки в окно), предпросмотр файла стандартной утилитой macOS (Quick Look, значок глаза); при наведении на сектор диаграммы в центре показываются имя, размер и доля.
- **Переключение окон по ⌥Tab:** для тех, кто пришёл с Windows — переключает фокус между отдельными окнами, а не приложениями целиком, и показывает их миниатюры. Пока Option зажат: Tab / ⇧Tab или стрелки — выбор, Esc — отмена, щелчок мышью — выбрать. Включается в Настройках → «Система» (по умолчанию выключено; миниатюры — отдельным переключателем, по умолчанию выключены, нужен доступ «Запись экрана и системного звука»).
- **⌘X в Finder:** «вырезать» файлы — ⌘X копирует выделенное и помечает как вырезанное, следующая вставка ⌘V перемещает файлы; справа внизу на пару секунд выезжает небольшая плашка «Вырезано» (в цветах текущей темы). Включается в Настройках → «Система» (по умолчанию выключено); нужен доступ «Управление устройством и доступ к данным» (в ранних версиях macOS: «Универсальный доступ»).
- **Окна с клавиатуры (⌃⌥ + стрелки):** активное окно любого приложения встаёт в левую или правую половину экрана (если размер окна меняется; если нет — сдвигается до края), ↑ — на весь экран, ↓ — свернуть в Dock. Включается в Настройках → «Система» (по умолчанию выключено); нужен доступ «Управление устройством и доступ к данным» (в ранних версиях macOS: «Универсальный доступ»).
- **Новая игра «Lode Runner»** в меню «Передохни»: собрать всё золото, уходя от охранников, и подняться по появившейся лестнице наверх. Бегун копает яму пробелом — с той стороны, куда смотрит; охранник в яме выбывает, яма зарастает. Простые звуки: копание, золото, лестница, конец уровня. Игра помнит уровень, жизни и очки даже после выхода из программы. При запуске игра стоит на паузе, пауза снимается любой клавишей. 15 уровней, на каждом по три охранника, они бегут плавно и ищут кратчайший путь; стрелки или WASD — бег, P — пауза.
- **Рекорды** у JezzBall и Lode Runner: таблица 12 лучших результатов справа от поля, имя спрашивается в конце игры, как в «Тетрисе».
- **Новая игра «JezzBall»** в меню «Передохни»: Простые звуки: построение стены, закрытие участка, потеря жизни, конец уровня и игры. по полю летают шарики, щелчок строит стену, которая растёт сразу в обе стороны; если шарик заденет растущую половину — она разрушается и теряется жизнь. Участки без шариков закрашиваются, нужно закрыть 75% поля. Правый клик или пробел поворачивают стену, на каждом уровне на один шарик и одну жизнь больше, пауза включается сама при потере фокуса.

**Улучшения**
- Версия 6.0.

---

### Version 6.0

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

---

### Версия 5.0

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

### Version 5.0

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

---

### Версия 4.1

**Новое**
- **Опорная пара валют для конвертера в поиске.** В настройках Пуска появился раздел «Конвертер валют в поиске»: выбираются основная и вторая валюта (по умолчанию рубль и доллар). Если в поиске набрана одна валюта без «в …», например `100 долларов`, она переводится в основную, а основная — во вторую. Раньше рубль и доллар были заданы жёстко.

**Улучшения**
- Версия 4.1.

---

### Version 4.1

**New**
- **Reference currency pair for the search converter.** Start's Settings now has a “Currency converter in search” section: choose a main and a second currency (ruble and dollar by default). If the search has a single currency without “to …”, e.g. `100 dollars`, it is converted to the main currency, and the main one to the second. Before, the ruble and the dollar were hard-coded.

**Improvements**
- Version 4.1.

---

---

### Версия 4.0

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

### Version 4.0

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

---

### Версия 3.0

**Новое**
- **Калькулятор, единицы и валюты в строке поиска.** Наберите `15% от 8400`, `2+2*3`, `sqrt(144)`, `5 миль в км`, `72 f в c`, `3 гб в мб` или `100 usd в руб` — ответ появится крупной карточкой над результатами, клик копирует число, Enter копирует и закрывает окно. Курсы валют берутся из интернета (не чаще раза в час), без связи показываются последние сохранённые.
- **Поиск по всему компьютеру.** Кроме приложений, строка поиска находит файлы и папки через системный Spotlight (домашняя папка, iCloud Drive и внешние диски; файлы, не скачанные из iCloud, помечены значком облака) и показывает их отдельным блоком «Файлы и папки», как в Spotlight на iPhone: значок, имя, папка и тип. Ищет и по именам, и по тексту внутри файлов (то, что проиндексировал Spotlight); найденные по тексту помечены «в тексте». Клик открывает файл, правый клик — «Показать в Finder» и «Копировать путь»; Enter открывает первое приложение, а если приложений нет, — первый файл. Текст в строке поиска не пропадает, если «Пуск» свернули и открыли снова (или переключились в другую программу); очищается кнопкой с крестиком в конце строки.
- **Не давать компьютеру уснуть**: кнопка с чашкой рядом с настройками (включается и из меню значка в строке меню). Пока включена, Мак и экран не засыпают от бездействия (как Amphetamine); чашка и значок в строке меню становятся голубыми, а рядом с чашкой появляется подпись «Не давать компьютеру уснуть». Закрытие крышки по-прежнему усыпляет Мак.

---

### Version 3.0

**New**
- **Calculator, units and currencies in the search field.** Type `15% of 8400`, `2+2*3`, `sqrt(144)`, `5 miles to km`, `72 f to c`, `3 gb to mb` or `100 usd to rub` — the answer appears as a large card above the results; click copies the number, Enter copies it and closes the window. Currency rates come from the internet (at most once an hour); offline, the last saved rates are used.
- **Search the whole computer.** Besides apps, the search field finds files and folders through system Spotlight (home folder, iCloud Drive and external drives; files not yet downloaded from iCloud get a cloud icon) and shows them in a separate “Files and folders” block, like Spotlight on iPhone: icon, name, folder and kind. It searches both names and text inside files (whatever Spotlight has indexed); items found by text are marked “in text”. Click opens the file; right click gives “Show in Finder” and “Copy path”. Enter opens the first app, or the first file when there are no apps. The search text is kept when “Пуск” is hidden and opened again (or you switch to another app); it is cleared with the ✕ button at the end of the field.
- **Keep the Mac awake**: a cup button next to Settings (also available from the menu-bar icon menu). While on, the Mac and its display do not sleep from inactivity (like Amphetamine); the cup and the menu-bar icon turn blue, and a “Keep the Mac awake” label appears next to the cup. Closing the lid still puts the Mac to sleep.

---

---

### Версия 2.0

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

### Version 2.0

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
