#!/bin/bash

set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "Usage: $0 <iphone-device-id> <watch-device-id> <evidence-directory> [backgrounded|terminated|hold-inbox]" >&2
    exit 64
fi

iphone_id="$1"
watch_id="$2"
evidence_dir="$3"
scenario="${4:-backgrounded}"
phone_bundle_id="com.drewreilly.wellspent.connectivityspike"
watch_bundle_id="com.drewreilly.wellspent.connectivityspike.watchkitapp"
phone_state="$evidence_dir/phone-state.json"
watch_state="$evidence_dir/watch-state.json"
classification_state="$evidence_dir/classification.json"

case "$scenario" in
    backgrounded) scenario_label="P2" ;;
    terminated) scenario_label="P3" ;;
    hold-inbox) scenario_label="P4" ;;
    *)
        echo "Unknown scenario: $scenario" >&2
        exit 64
        ;;
esac

mkdir -p "$evidence_dir"

watch_probe_pids() {
    xcrun devicectl device info processes \
        --device "$watch_id" \
        --timeout 60 \
        | awk '/\/WellSpentConnectivitySpikeWatch.app\/WellSpentConnectivitySpikeWatch[[:space:]]*$/ { print $1 }'
}

stop_watch_probe() {
    local watch_pids
    watch_pids="$({ watch_probe_pids; } 2>/dev/null || true)"
    [[ -n "$watch_pids" ]] || return 0
    for watch_pid in $watch_pids; do
        xcrun devicectl device process terminate \
            --device "$watch_id" \
            --pid "$watch_pid" \
            --kill \
            --timeout 60
    done

    for attempt in $(seq 1 12); do
        sleep 1
        if [[ -z "$({ watch_probe_pids; } 2>/dev/null || true)" ]]; then
            return
        fi
    done

    echo "Watch probe process did not terminate" >&2
    exit 1
}

phone_probe_pids() {
    xcrun devicectl device info processes \
        --device "$iphone_id" \
        --timeout 60 \
        | awk '/\/WellSpentConnectivitySpikePhone.app\/WellSpentConnectivitySpikePhone[[:space:]]*$/ { print $1 }'
}

stop_phone_probe() {
    local phone_pids
    phone_pids="$({ phone_probe_pids; } 2>/dev/null || true)"
    [[ -n "$phone_pids" ]] || return 0
    for phone_pid in $phone_pids; do
        xcrun devicectl device process terminate \
            --device "$iphone_id" \
            --pid "$phone_pid" \
            --kill \
            --timeout 60
    done

    for attempt in $(seq 1 12); do
        sleep 1
        if [[ -z "$({ phone_probe_pids; } 2>/dev/null || true)" ]]; then
            return
        fi
    done

    echo "iPhone probe process did not terminate" >&2
    exit 1
}

launch_watch_probe() {
    local environment_variables="$1"
    if ! xcrun devicectl device process launch \
        --device "$watch_id" \
        --activate \
        --environment-variables "$environment_variables" \
        "$watch_bundle_id" \
        --timeout 30; then
        echo "Watch launch command timed out; checking whether the fresh process started"
        sleep 2
        local fresh_watch_processes
        fresh_watch_processes="$(xcrun devicectl device info processes \
            --device "$watch_id" \
            --timeout 60)"
        if [[ "$fresh_watch_processes" != *"/WellSpentConnectivitySpikeWatch.app/WellSpentConnectivitySpikeWatch"* ]]; then
            echo "Fresh Watch probe process did not start" >&2
            exit 1
        fi
    fi
}

echo "Launching a Watch sanitizer to cancel transfers left by earlier runs"
stop_watch_probe
launch_watch_probe \
    '{"WC_PROBE_RESET_ON_LAUNCH":"1","WC_PROBE_AUTOMATION_DISABLE_FAST_PATH":"1","WC_PROBE_AUTOMATION_CANCEL_PENDING_TRANSFERS":"1"}'
sleep 8
stop_watch_probe

if [[ "$scenario" == "hold-inbox" ]]; then
    phone_launch_environment='{"WC_PROBE_RESET_ON_LAUNCH":"1","WC_PROBE_AUTOMATION_DISABLE_FAST_PATH":"1","WC_PROBE_AUTOMATION_CANCEL_PENDING_TRANSFERS":"1","WC_PROBE_AUTOMATION_HOLD_INBOX_BEFORE_APPLY":"1"}'
else
    phone_launch_environment='{"WC_PROBE_RESET_ON_LAUNCH":"1","WC_PROBE_AUTOMATION_DISABLE_FAST_PATH":"1","WC_PROBE_AUTOMATION_CANCEL_PENDING_TRANSFERS":"1"}'
fi

echo "Launching and resetting the iPhone probe without a debugger"
xcrun devicectl device process launch \
    --device "$iphone_id" \
    --terminate-existing \
    --activate \
    --environment-variables "$phone_launch_environment" \
    "$phone_bundle_id" \
    --timeout 30

if [[ "$scenario" == "terminated" ]]; then
    echo "Terminating the iPhone probe after its Home-screen launch"
    sleep 2
    stop_phone_probe
elif [[ "$scenario" == "backgrounded" ]]; then
    echo "Backgrounding the iPhone probe by foregrounding Settings"
    xcrun devicectl device process launch \
        --device "$iphone_id" \
        --terminate-existing \
        --activate \
        com.apple.Preferences \
        --timeout 30
fi

echo "Launching the Watch probe; Start will queue after an 8-second delay"
launch_watch_probe \
    '{"WC_PROBE_RESET_ON_LAUNCH":"1","WC_PROBE_AUTOMATION_QUEUE_START_ON_ACTIVATION":"1","WC_PROBE_AUTOMATION_QUEUE_START_DELAY_SECONDS":"8","WC_PROBE_AUTOMATION_DISABLE_FAST_PATH":"1","WC_PROBE_AUTOMATION_CANCEL_PENDING_TRANSFERS":"1"}'

if [[ "$scenario" == "hold-inbox" ]]; then
    echo "Waiting for the iPhone to persist—but not apply—the mutation"
    held_state_confirmed=false
    for attempt in $(seq 1 150); do
        rm -f "$phone_state"
        if xcrun devicectl device copy from \
            --device "$iphone_id" \
            --source 'Library/Application Support/WellSpentConnectivitySpike/state.json' \
            --destination "$phone_state" \
            --domain-type appDataContainer \
            --domain-identifier "$phone_bundle_id" \
            --remove-existing-content true \
            --timeout 20 >/dev/null 2>&1; then
            phone_held="$({
                jq -r '
                    (.inbox | length) == 1 and
                    .inbox[0].status == "received" and
                    .canonicalSnapshot.canonicalGeneration == 0 and
                    ([.events[] | select(.code == "phone_inbox_persisted")] | length) == 1 and
                    ([.events[] | select(.code == "phone_inbox_apply_held")] | length) >= 1 and
                    ([.events[] | select(.code == "phone_ack_queued")] | length) == 0
                ' "$phone_state"
            } 2>/dev/null || echo false)"
            if [[ "$phone_held" == "true" ]]; then
                held_mutation_id="$(jq -r '.inbox[0].envelope.payload.mutationID' "$phone_state")"
                rm -f "$evidence_dir/watch-state-held.json"
                if xcrun devicectl device copy from \
                    --device "$watch_id" \
                    --source 'Library/Application Support/WellSpentConnectivitySpike/state.json' \
                    --destination "$evidence_dir/watch-state-held.json" \
                    --domain-type appDataContainer \
                    --domain-identifier "$watch_bundle_id" \
                    --remove-existing-content true \
                    --timeout 30 >/dev/null 2>&1; then
                    watch_held="$({
                        jq -r --arg mutation_id "$held_mutation_id" '
                            (.outbox | length) == 1 and
                            .outbox[0].payload.mutationID == $mutation_id and
                            (.acknowledgements | length) == 0
                        ' "$evidence_dir/watch-state-held.json"
                    } 2>/dev/null || echo false)"
                    if [[ "$watch_held" == "true" ]]; then
                        cp "$phone_state" "$evidence_dir/phone-state-held.json"
                        held_state_confirmed=true
                        break
                    fi
                fi
            fi
        fi
        sleep 4
    done

    if [[ "$held_state_confirmed" != "true" ]]; then
        echo "P4 did not reach the persisted-before-apply boundary" >&2
        exit 1
    fi

    echo "Held inbox is durable; terminating and relaunching the iPhone without the hold"
    stop_phone_probe
    xcrun devicectl device process launch \
        --device "$iphone_id" \
        --terminate-existing \
        --activate \
        --environment-variables \
            '{"WC_PROBE_AUTOMATION_DISABLE_FAST_PATH":"1"}' \
        "$phone_bundle_id" \
        --timeout 30
fi

poll_for_convergence() {
    local maximum_attempts="$1"
    for attempt in $(seq 1 "$maximum_attempts"); do
        rm -f "$phone_state"
        if xcrun devicectl device copy from \
            --device "$iphone_id" \
            --source 'Library/Application Support/WellSpentConnectivitySpike/state.json' \
            --destination "$phone_state" \
            --domain-type appDataContainer \
            --domain-identifier "$phone_bundle_id" \
            --remove-existing-content true \
            --timeout 20 >/dev/null 2>&1; then
            phone_converged="$({
                jq -r --arg scenario "$scenario" '
                    (.inbox | length) == 1 and
                    ([.inbox[] | select(.status == "terminal")] | length) == 1 and
                    .canonicalSnapshot.canonicalGeneration == 1 and
                    .mutationBlocked == false and
                    ([.events[] | select(
                        .code == "phone_inbox_persisted" and
                        .transport == "userInfo" and
                        ($scenario != "backgrounded" or .reachable == false)
                    )] | length) == 1 and
                    ([.events[] | select(.code == "phone_ack_queued")] | length) >= 1
                ' "$phone_state"
            } 2>/dev/null || echo false)"

            rm -f "$watch_state"
            if [[ "$phone_converged" == "true" ]] \
                && xcrun devicectl device copy from \
                    --device "$watch_id" \
                    --source 'Library/Application Support/WellSpentConnectivitySpike/state.json' \
                    --destination "$watch_state" \
                    --domain-type appDataContainer \
                    --domain-identifier "$watch_bundle_id" \
                    --remove-existing-content true \
                    --timeout 30 >/dev/null 2>&1; then
                phone_mutation_id="$(jq -r '.inbox[0].envelope.payload.mutationID' "$phone_state")"
                watch_converged="$({
                    jq -r --arg mutation_id "$phone_mutation_id" '
                        (.outbox | length) == 0 and
                        (.acknowledgements | length) == 1 and
                        .acknowledgements[0].mutationID == $mutation_id and
                        ([.events[] | select(
                            (.code | startswith("watch_local_commit_start")) and
                            .mutationID == $mutation_id
                        )] | length) == 1 and
                        ([.events[] | select(
                            (.code | startswith("watch_ack_")) and
                            .mutationID == $mutation_id
                        )] | length) >= 1
                    ' "$watch_state"
                } 2>/dev/null || echo false)"

                if [[ "$watch_converged" != "true" ]]; then
                    sleep 4
                    continue
                fi

                jq '{
                    inbox: (.inbox | length),
                    terminal: ([.inbox[] | select(.status == "terminal")] | length),
                    receivedTransport: .inbox[0].receivedTransport,
                    generation: .canonicalSnapshot.canonicalGeneration,
                    persistedReachable: ([.events[] | select(.code == "phone_inbox_persisted")][0].reachable),
                    acknowledgementsQueued: ([.events[] | select(.code == "phone_ack_queued")] | length),
                    mutationBlocked: .mutationBlocked
                }' "$phone_state"
                jq '{
                    outbox: (.outbox | length),
                    acknowledgements: (.acknowledgements | length),
                    mutationID: .acknowledgements[0].mutationID,
                    acknowledgementTransport: ([.events[] | select(.code | startswith("watch_ack_"))][0].transport)
                }' "$watch_state"
                jq -n \
                    --arg scenario "$scenario_label" \
                    --arg delivery_mode "$delivery_mode" \
                    --slurpfile phone "$phone_state" \
                    --slurpfile watch "$watch_state" \
                    '{
                        scenario: $scenario,
                        deliveryMode: $delivery_mode,
                        mutationID: $phone[0].inbox[0].envelope.payload.mutationID,
                        watchCommittedAt: ([
                            $watch[0].events[] | select(.code == "watch_local_commit_start")
                        ][0].at),
                        phonePersistedAt: ([
                            $phone[0].events[] | select(.code == "phone_inbox_persisted")
                        ][0].at),
                        deliveryDelaySeconds: (([
                            $phone[0].events[] | select(.code == "phone_inbox_persisted")
                        ][0].at | fromdateiso8601) - ([
                            $watch[0].events[] | select(.code == "watch_local_commit_start")
                        ][0].at | fromdateiso8601))
                    }' >"$classification_state"
                return 0
            fi
        fi

        sleep 4
    done

    return 1
}

if [[ "$scenario" == "terminated" ]]; then
    delivery_mode="system_wake"
elif [[ "$scenario" == "hold-inbox" ]]; then
    delivery_mode="resume_after_held_inbox"
else
    delivery_mode="background_transition"
fi

if poll_for_convergence 150; then
    echo "$scenario_label detached run passed ($delivery_mode)"
    exit 0
fi

if [[ "$scenario" == "terminated" ]]; then
    echo "No system wake within 600 seconds; relaunching the iPhone probe without resetting state"
    delivery_mode="manual_relaunch"
    xcrun devicectl device process launch \
        --device "$iphone_id" \
        --terminate-existing \
        --activate \
        --environment-variables \
            '{"WC_PROBE_AUTOMATION_DISABLE_FAST_PATH":"1"}' \
        "$phone_bundle_id" \
        --timeout 30
    if poll_for_convergence 150; then
        echo "$scenario_label detached run passed ($delivery_mode)"
        exit 0
    fi
fi

echo "$scenario_label did not converge within its delivery windows" >&2
if [[ -f "$phone_state" ]]; then
    jq '{inbox: (.inbox | length), generation: .canonicalSnapshot.canonicalGeneration, mutationBlocked}' \
        "$phone_state" >&2 || true
fi
if [[ -f "$watch_state" ]]; then
    jq '{outbox: (.outbox | length), acknowledgements: (.acknowledgements | length)}' \
        "$watch_state" >&2 || true
fi
exit 1
