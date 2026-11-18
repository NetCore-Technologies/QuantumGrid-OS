
# AW1000 RJ11 phone port

QuantumGrid supports the Arcadyan AW1000's built-in analogue FXS socket through the
open-source [openwrt-aw1000-phone](https://github.com/Perz3us/openwrt-aw1000-phone)
project. The upstream implementation is licensed GPL-2.0-only and is integrated as a
pinned OpenWrt feed rather than copied or forked into this repository.

## Hardware and service requirements

- Arcadyan AW1000 on the qualcommax/ipq807x target.
- Quectel RG500Q-EA modem fitted and working.
- A SIM plan and carrier that provision VoLTE voice calling.
- A kernel module built against the exact firmware kernel.
- A legally obtained Skyworks Si3226x/Si32261 SLIC DSP patch file.

The upstream implementation provides the kmod-aw1000-fxs kernel driver, fxsd line daemon
and luci-app-fxs management page. The optional SIP service is a separate component.
The phone stack does not make a data-only SIM or unsupported carrier offer voice service.

## Build integration

The normal QuantumGrid build and configurator register the upstream phone feed at tag
v0.9.0, update OpenWrt feeds and select the three packages automatically:

- kmod-aw1000-fxs
- fxsd
- luci-app-fxs

The external source is checked out under third_party/openwrt-aw1000-phone and is ignored
by Git. You can update the pinned source deliberately by setting QG_AW1000_PHONE_REF when
running scripts/setup-aw1000-phone-feed.sh; review compatibility and licensing before
changing the pin.

## First boot is deliberately safe

QuantumGrid disables the phone service during first-boot defaults. This avoids an unexpected
modem reconfiguration and mobile-data interruption before the line is ready.

1. Check that all three phone packages are installed.
2. Obtain the SLIC patch from an authorized source. QuantumGrid does not bundle it: the
   upstream project documents that the patch contains proprietary Skyworks code.
3. Copy it to the router, for example:

   ```sh
   mkdir -p /etc/fxs
   scp si3226x_patch.bin root@192.168.1.1:/etc/fxs/si3226x_patch.bin
   ```

4. Confirm the file is present and non-empty:

   ```sh
   test -s /etc/fxs/si3226x_patch.bin && echo "SLIC patch present"
   ```

5. Enable the service intentionally:

   ```sh
   uci set fxs.main.patch='/etc/fxs/si3226x_patch.bin'
   uci set fxs.main.enabled='1'
   uci commit fxs
   /etc/init.d/fxsd enable
   /etc/init.d/fxsd restart
   ```

The first start can switch the modem's PCM audio mode and restart the RG500Q-EA. Mobile
internet may be unavailable for about a minute while the modem restarts. Do this during a
maintenance window, not during an important download, call or remote session.

## Management

Open Services → Phone (RJ11) in LuCI, or use:

/cgi-bin/luci/admin/services/fxs/status

The native service provides line status, calls, call history, settings, caller ID, call waiting,
speed dial, contacts, call policies, do-not-disturb, optional recording and optional SIP
integration. SIP and recording should be enabled only after reviewing the local network,
storage and privacy implications.

The QuantumGrid Phone page links directly to this native management surface. This is
intentional: the upstream page already exposes the service's real UBUS controls and ACLs;
the QuantumGrid panel must not pretend that simulated browser controls are connected to the
FXS hardware.

## Electrical and calling safety

The analogue phone pair can carry approximately 46 V DC on-hook and a higher voltage while
ringing. Never touch exposed RJ11 contacts or connect test leads to the line while it is
powered. Use an ordinary compatible telephone and an intact cable.

The upstream project explicitly says emergency calling has not been tested. Do not rely on
this experimental router feature as your only emergency calling path. Keep an independent,
certified means of contacting emergency services.

## Upstream references

- [AW1000 FXS driver, daemon, LuCI app and GPL-2.0 license](https://github.com/Perz3us/openwrt-aw1000-phone)
- [Hardware notes and SLIC/PCM details](https://github.com/Perz3us/openwrt-aw1000-phone/blob/v0.9.0/docs/hardware.md)
- [Upstream issues and compatibility reports](https://github.com/Perz3us/openwrt-aw1000-phone/issues)
