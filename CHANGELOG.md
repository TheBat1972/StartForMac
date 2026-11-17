# Что нового / What's new

Русский · [English](#english)

## Русский

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
