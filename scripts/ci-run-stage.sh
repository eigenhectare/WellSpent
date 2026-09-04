#!/bin/bash
# Sourced by ci.sh and its fail-fast regression test.
run_stage() {
    local stage="$1"
    shift
    local start="${SECONDS}"
    echo "Starting ${stage}"
    # A function invoked directly in an `if` condition disables errexit inside
    # that function. Run it independently so an early failed gate cannot be
    # hidden by a later successful command.
    ( set -e; "$@" ) > "${run_root}/logs/${stage}.log" 2>&1 &
    local stage_pid="$!"
    if wait "${stage_pid}"; then
        printf '%s\tpassed\t%s\n' "${stage}" "$((SECONDS - start))" >> "${report}"
        echo "Passed ${stage} ($((SECONDS - start))s)"
    else
        local status="$?"
        printf '%s\tfailed\t%s\n' "${stage}" "$((SECONDS - start))" >> "${report}"
        tail -n 80 "${run_root}/logs/${stage}.log" >&2
        echo "Failed ${stage}; evidence retained in ${run_root}" >&2
        return "${status}"
    fi
}
