#!/bin/bash
# Запуск программы из NameLess UI: qs-app.sh <команда…>
# Quickshell стартует облегчённо (qs-light.sh: без стека NVIDIA, EGL только Mesa, свой jemalloc) и запомнил прежние значения
# в QS_ORIG_* / QS_UNSET_*. Программы, которые он запускает, должны получить окружение сессии, а не облегчённое.
for v in GBM_BACKEND __GLX_VENDOR_LIBRARY_NAME LIBVA_DRIVER_NAME __EGL_VENDOR_LIBRARY_FILENAMES MALLOC_CONF; do
    o="QS_ORIG_$v"; u="QS_UNSET_$v"
    if [[ -n "${!o+x}" ]]; then export "$v=${!o}"; elif [[ -n "${!u:-}" ]]; then unset "$v"; fi
    unset "$o" "$u"
done
exec "$@"
