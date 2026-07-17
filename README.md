# Niri config — RU / EN

Переработанный конфиг CachyOS/Noctalia.  
Reworked CachyOS/Noctalia config.

## Главное / Highlights

- Фокус при наведении полностью выключен / Focus-follows-mouse is disabled.
- `Mod+D` — launcher, `Mod+Return` — Kitty, `Mod+F` — fullscreen.
- `Mod+стрелки` — фокус, `Mod+Shift+стрелки` — перенос окна.
- `Mod+Ctrl+Up/Down` — рабочие столы; `Mod+1…9` — прямой выбор.
- `Mod+Ctrl+Left/Right` — мониторы; с `Shift` переносит окно.
- `Mod+C` — центр; `Mod+-/=` — ширина; с `Shift` — высота.
- US + русская фонетическая, переключение `Alt+Shift`.

## Установка / Install

1. Сделайте копию `~/.config/niri` / Back up `~/.config/niri`.
2. Скопируйте `config.kdl` и `cfg/` в `~/.config/niri/`.
3. Выполните `niri msg outputs` и исправьте `DP-1`/`DP-2` в `cfg/display.kdl`.
4. Проверьте: `niri validate -c ~/.config/niri/config.kdl`.

Если ваша версия niri не принимает `-c`, используйте `niri validate` после копирования.  
If your niri version does not accept `-c`, run `niri validate` after copying.
