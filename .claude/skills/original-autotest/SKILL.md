---
name: original-autotest
description: Автотест оригинальных «Корсаров» (ENGINE.exe + fix\capture.ps1) на Windows 11 по SSH — окно, мышь, клавиатура, клик по кнопке меню, проверка по скриншотам. Использовать при правках capture.ps1/overlay.c в corsairs-original-fix, когда надо проверить, что игра реагирует на ввод.
---

# Автотест corsairs-original-fix

Репозиторий: `$W/corsairs-original-fix` (`W=/media/roman/383be9ee-c114-4bf8-8956-66b985661cb4/home/remake-linux`). Игра на Windows: `ssh -i "$WIN_KEY" "$WIN_USER@$WIN_HOST"`, рабочая папка там `C:\Users\User\cof\`, игра `C:\Program Files\1C\Корсары\fix\`.
Переменные окружения: `WIN_HOST` (адрес Windows-машины), `WIN_USER`, `WIN_KEY` (путь к ssh-ключу) — в репозитории их значений нет.

## Правила
- **Одна гипотеза за прогон.** Не запускать серии. Перед прогоном написать пользователю и в `docs/click-input-research.md` (таблица гипотез), что пробуем; после — вывод и результат в тот же файл.
- **Успех — только по скриншотам**, не по хешам: хеш меняется от курсора и счётчика FPS (строки «WORKS/DEAD» в логе ненадёжны).
- Тест короткий (~15 с), в нём один клик на «Создатели».
- Перед прогоном: `ssh … 'taskkill /f /im ENGINE.exe'` (вторая копия даёт FPS 0 и мёртвый ввод; если процесс запущен пользователем — спросить).
- Команды по ssh — по одной ps1 за вызов (`;` ломает). Пути с пробелами обходить через `cps.ps1`.

## Как устроен автотест
`fix.ini` (ключи `frame`, `autotest`, `skipintro`): `autotest=1` (с кликом) или `2` (без клика, только hover), `3` (перетаскивание окна за заголовок), `4` (свободный курсор), `5` (видео 6 с со звуком, `volumedetect`), `6` (заставки при `skipintro=0`: кадры `i_3s…i_30s`, Esc на 4 с); `frame=3` (настоящая рамка, по умолчанию), `1` (полоса, окно со сдвигом) или `0` (как оригинал, окно 0,0). Игру запускает `capture.ps1 -Launch` приостановленной (патчи `CreateWindowExA`/`GetWindowRect` до старта), `play.ps1` её сам не стартует. `Auto-Step` в capture.ps1 после старта игры по времени: 1_start, курсор на кнопку, 2_button1, 3_button2, 4_menu, курсор на «Создатели» (Left+400, Top+479) и клик (`mouse_event`), 5_afterclick, Esc, 6_afteresc, ↓×2, 7_afterdown, затем игра закрывается. Скриншоты: `Documents\My Games\Sea Dogs\auto`. Лог: `Documents\My Games\Sea Dogs\Logs\fps.log`.

## Прогон
1. Деплой изменённых файлов: `scp capture.ps1 overlay.bin` в `cof\`, затем `powershell -File C:\Users\User\cof\dep.ps1` (копирует в `fix\`). Проверка парсера: `pe2.ps1` → «errors: 0».
2. `scripts/run_autotest.sh <frame> <autotest>` — выставляет fix.ini, запускает игру через планировщик (`runauto.ps1` → `go.ps1` → `play.vbs`), ждёт строку «autotest: Down» (до ~45 с). Скрипты .ps1 лежат в `scripts/`, их надо один раз положить в `C:\Users\User\cof\` (scp).
3. Скриншоты: `cps.ps1` (копия в `cof\shots`), затем `scp` в локальную папку. Проверять, что у файлов 6_ и 7_ свежее время (иначе прогон оборвался).
4. Склеить кадры и посмотреть глазами:
   `ffmpeg -y -i 4_menu.png -i 5_afterclick.png -i 6_afteresc.png -i 7_afterdown.png -filter_complex "[0][1]hstack[a];[2][3]hstack[b];[a][b]vstack,scale=900:-1" cmp.png`; окно при frame=1 можно вырезать `crop=830:620:880:433`.
5. Лог: `lc.ps1` (кадры/клики/`pic:`), `l14.ps1` (всё с последнего старта), `l10.ps1` (autotest-строки + идёт ли ENGINE).
6. В конце вернуть `fix.ini`: `sf2.ps1` (frame=1, без autotest).

## Предупреждения
- **`dep.ps1` — только после `pe2.ps1` → «errors: 0».** Парсер не ловит ошибки C# в `Add-Type`: если там предупреждение компилятора (оно считается ошибкой), скрипт тихо не стартует, а игра не запускается вообще (при `-Launch` — тоже). Проверка: запустить `capture.ps1 -GameDir … -NoFps` без `-WindowStyle Hidden`.
- `dep.ps1` копирует `capture.ps1`, `overlay.bin`, `play.ps1`, `settings.ps1`; после правки `overlay.c` сначала `./build_overlay.sh`.
- После теста вернуть `fix.ini` без `autotest` (`rm.ps1`) и с `skipintro=1`; убедиться, что ENGINE.exe не запущен.
- Автотесты 3–6 запускаются так же, как 1–2 (`run_autotest.sh <frame> <autotest>`); для 6 нужно сначала поставить `skipintro=0`.

## Что считается успехом
- 4_menu: меню. Курсор над кнопкой — кнопка подсвечена (hover).
- 5_afterclick (autotest=1): открыт экран «Создатели» (кнопка «Выход» внизу). При autotest=2 — только подсветка.
- 6_afteresc: снова меню. 7_afterdown: выделение сдвинулось стрелками.

## Если что-то не так
- Нет строк `autotest:` и лог молчит — capture.ps1 мог молча завершиться (главный цикл в try/catch пишет `main loop died`).
- «FPS 0» в OSD при GAME 30 — известно, не разобрано.
- `[CapNative]::Windows(pid)` блокируется SendMessage при неотвечающей игре — не вызывать в цикле логов.
- Диагностика: в логе `cursor fix: changed N, modules M…` (ожидается changed ≥5 при frame=1), `click:`, `input:`, `pic:` раз в секунду.

## Все команды (копировать как есть)
```bash
K=$WIN_KEY; U=$WIN_USER@$WIN_HOST; S="ssh -i $K $U"
R=/media/roman/383be9ee-c114-4bf8-8956-66b985661cb4/home/remake-linux/corsairs-original-fix
SK=/home/roman/Documents/remake/.claude/skills/original-autotest/scripts
T=/tmp/claude-1000; mkdir -p $T/shots

# 0. один раз: вспомогательные скрипты на Windows (в папку cof)
scp -i $K $SK/*.ps1 $U:C:/Users/User/cof/

# 1. деплой: правки → cof → fix
scp -i $K $R/capture.ps1 $R/overlay.bin $U:C:/Users/User/cof/
$S 'powershell -ExecutionPolicy Bypass -File C:\Users\User\cof\pe2.ps1'    # парсер: errors: 0
$S 'powershell -ExecutionPolicy Bypass -File C:\Users\User\cof\dep.ps1'    # копия в Корсары\fix

# 2. пересборка оверлея после правки overlay.c (на Linux)
(cd $R && ./build_overlay.sh)

# 3. убить зависшие копии игры
$S 'taskkill /f /im ENGINE.exe'

# 4. прогон: frame (0|1) и autotest (1 с кликом, 2 без)
$SK/run_autotest.sh 1 1

# 5. скриншоты на Linux
$S 'powershell -ExecutionPolicy Bypass -File C:\Users\User\cof\cps.ps1'
rm -f $T/shots/*.png; scp -q -i $K "$U:C:/Users/User/cof/shots/*.png" $T/shots/
cd $T/shots && ffmpeg -loglevel error -y -i 4_menu.png -i 5_afterclick.png -i 6_afteresc.png -i 7_afterdown.png \
  -filter_complex "[0][1]hstack[a];[2][3]hstack[b];[a][b]vstack,scale=900:-1" cmp.png     # и посмотреть cmp.png

# 6. логи
$S 'powershell -ExecutionPolicy Bypass -File C:\Users\User\cof\lc.ps1'     # pic/click, последний запуск
$S 'powershell -ExecutionPolicy Bypass -File C:\Users\User\cof\l14.ps1'    # всё, кроме osd, с последнего старта
$S 'powershell -ExecutionPolicy Bypass -File C:\Users\User\cof\l10.ps1'    # autotest-строки, идёт ли ENGINE
$S 'tasklist | findstr /i ENGINE.exe'

# 7. вернуть настройки пользователю (frame=3, без autotest, skipintro=1)
$S 'powershell -ExecutionPolicy Bypass -File C:\Users\User\cof\sf2.ps1'
```
Что внутри `run_autotest.sh`: пишет `sf.ps1` (в `fix.ini` меняет `frame=` и `autotest=`), копирует его в `cof`, запускает; считает строки «autotest: Down» в логе до и после, запускает `runauto.ps1` (`schtasks /create … go.ps1 /it`, `/run`, `/delete`: игре нужна интерактивная сессия пользователя) и каждые 3 с (до 15 раз) ждёт новую строку «autotest: Down»; в конце печатает последние строки autotest из лога.
