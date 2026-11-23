# Weekly Wi-Fi radio scheduling

This guide describes QuantumGrid's opt-in weekly schedule for an existing AW1000 Wi-Fi radio. A schedule controls the radio device, so every BSS attached to that radio follows the same state.

## Before enabling

- Keep wired or independent out-of-band management available. Turning off a radio disconnects all clients on it.
- The radio must already be configured enabled and be live/up when an enabled schedule is first saved. QuantumGrid records that manual enabled state as the restore baseline.
- Check the router clock and NTP. Schedule times use the router's local timezone, not the browser timezone.
- Do not schedule away the only management path.

## Configure

Open **Wi-Fi**, expand the selected radio's **Weekly radio schedule**, choose weekdays, set radio-on and radio-off times, enable automatic control and acknowledge the disconnect warning before saving.

Weekdays are Monday through Sunday. Start is inclusive; end is exclusive. A Monday–Friday 08:00–22:00 schedule keeps the radio on during that interval and off outside it. Overnight windows work across midnight, such as Friday 22:00 to Saturday 06:00. Start and end must differ; disable a schedule to return to manual control.

Saving persists policy. The worker evaluates it on the next cycle, which runs every 30 seconds. It reloads Wi-Fi and verifies live `network.wireless` status via ubus before logging a change as applied. The page does not claim the radio changed immediately on save.

## Manual-state preservation

An enabled schedule is accepted only after a manual enabled/live radio is verified. QuantumGrid stores a baseline for that original state. Outside the selected window it sets the UCI `disabled` option; inside the window it removes that option. Disabling the schedule restores the saved manual state, reloads Wi-Fi and clears the one-shot baseline after the restore completes.

Do not manually alter the disabled state while a schedule is active. To make a permanent manual change, disable the schedule through the control centre and wait for baseline restoration before changing the radio manually.

## Verify

From SSH over a trusted management path:

~~~sh
date
/etc/init.d/quantumgrid-radio-scheduler status
logread -e quantumgrid-radio-scheduler
uci show quantumgrid-radio
ubus call network.wireless status
~~~

The log reports successful live-state verification, invalid or duplicate records, unavailable runtime inventory, commit/reload failures and rollback outcomes. Missing runtime inventory is fail-closed: no radio changes are made. The service is enabled at first boot but is inert until an enabled schedule exists. It does not reload Wi-Fi continuously when desired and current states already match.

## Disable normally

Prefer the Wi-Fi control centre: uncheck **Enable automatic weekly radio control**, acknowledge and save. The next cycle restores the saved manual state. Check the log and ubus output before relying on wireless management again.

## Emergency recovery

If the Wi-Fi session is lost, use wired or serial/out-of-band console access. Replace `radio0` with the actual radio section name. Enabled schedules can only be created from an enabled manual baseline, so removing the UCI `disabled` option restores the standard enabled configuration:

~~~sh
uci set quantumgrid-radio.radio0.enabled='0'
uci -q delete wireless.radio0.disabled
uci -q delete quantumgrid-radio.radio0.base_disabled
uci commit wireless
uci commit quantumgrid-radio
wifi reload
ubus call network.wireless status
~~~

This is an emergency manual path, not the preferred schedule-disable operation. If reload or runtime verification still fails, use the AW1000 recovery/UART guide and avoid repeated remote toggles.

## Safety and validation limits

Schedule changes use LuCI's authenticated HTTPS session and same-origin POST. The controller validates existing `wifi-device` sections, times, weekdays, duplicates and baseline state. It never creates radios, SSIDs, VLANs or firewall rules.

CI tests the pure schedule evaluator and scheduler transaction with mocked UCI/ubus dependencies, including start boundaries, overnight windows, baseline restoration, reload rollback and missing telemetry. This does not replace physical AW1000 validation. Test actual RF shutdown/startup, client reconnection, management reachability and recovery on a recoverable device before production use.
