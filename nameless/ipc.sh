#!/bin/sh
# Вызов окна NameLess из ярлыка меню приложений: ipc.sh <цель> <функция>
# Оболочка не запущена или не отвечает — запускается (qs-light.sh, если есть) и вызов повторяется до 6 с.
cfg=nameless
call() { timeout 3 qs -c "$cfg" ipc call "$@" 2>/dev/null; }
call "$@" && exit 0
ql="$HOME/.config/hypr/Scripts/qs-light.sh"; [ -x "$ql" ] || ql=qs
# своего экземпляра нет — поднимаем; живой, но занятый, не трогаем
if ! timeout 2 qs -c "$cfg" ipc show >/dev/null 2>&1; then
    setsid -f "$ql" -c "$cfg" >>"$HOME/.cache/nameless.log" 2>&1 </dev/null
fi
for _ in $(seq 60); do call "$@" && exit 0; sleep 0.1; done
exit 1
