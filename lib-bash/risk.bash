#!/usr/bin/env bash
# Risk module — pure predicate, no I/O.
# Interface: _bash_ai_is_risky(cmd) → 0 if risky, 1 if safe
# ponytail: 14 grep patterns, O(n) scan; add per-pattern table if throughput matters

_bash_ai_is_risky() {
    local cmd="$1"
    if printf '%s' "$cmd" | grep -Eq 'rm[[:space:]]+[^;|&]*-.*r.*f[^;|&]*[[:space:]]+/(\*)?([[:space:]]|;|\||&|$)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq 'rm[[:space:]]+[^;|&]*-.*r.*f[^;|&]*[[:space:]]+~([/][*]?)?([[:space:]]|;|\||&|$)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq 'mkfs\.'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq 'dd[[:space:]].*of=/dev/(sda|nvme|mmc)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Fq ':(){:|:&};:'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq '(^|[;|&[:space:]])shutdown([[:space:]]|;|\||&|$)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq '(^|[;|&[:space:]])reboot([[:space:]]|;|\||&|$)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq '(^|[;|&[:space:]])halt([[:space:]]|;|\||&|$)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq '(^|[;|&[:space:]])poweroff([[:space:]]|;|\||&|$)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq 'init[[:space:]]+(0|6)([[:space:]]|;|$)'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push.*--force'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+reset[[:space:]]+--hard'; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq 'chmod[[:space:]]+.*-R.*777.*[[:space:]]+/[[:space:]]*$' || printf '%s' "$cmd" | grep -Eq 'chmod[[:space:]]+.*777.*[[:space:]]+/[[:space:]]*($|;)' ; then return 0; fi
    if printf '%s' "$cmd" | grep -Eq 'chmod.*-R.*777'; then
        if printf '%s' "$cmd" | grep -Eq '[[:space:]]/[[:space:]]*($|;|\||&)' ; then return 0; fi
    fi
    if printf '%s' "$cmd" | grep -Eq 'chown[[:space:]]+.*-R'; then return 0; fi
    return 1
}
