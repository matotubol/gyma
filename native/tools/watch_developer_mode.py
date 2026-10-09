"""Inspect a paired Watch, or reveal its Developer Mode toggle from Windows.

Requires pymobiledevice3==11.12.0. No Apple credentials are used. --reveal
performs developer pairing (the Watch must approve Trust), then sends only
AMFI action 0. Enabling Developer Mode and restarting remain manual.

Protocol references:
https://github.com/doronz88/pymobiledevice3/blob/v11.12.0/pymobiledevice3/services/companion.py
https://github.com/doronz88/pymobiledevice3/blob/v11.12.0/pymobiledevice3/services/amfi.py
"""

from __future__ import annotations

import argparse
import asyncio
import importlib.metadata
import logging
from pathlib import Path
import re
import sys
from typing import Any

from pymobiledevice3 import usbmux
from pymobiledevice3.lockdown import DeviceClass, LockdownClient, create_using_usbmux


REQUIRED_VERSION = "11.12.0"
IO_TIMEOUT = 30
TRUST_TIMEOUT = 60
LOCKDOWN_PORT = 62078
PROXY_SERVICE = "com.apple.companion_proxy"
AMFI_SERVICE = "com.apple.amfi.lockdown"
PAIRING_CACHE = Path(__file__).resolve().parents[1] / "build/device-tools/pairing"


class DeviceCheckError(RuntimeError):
    """A diagnostic message that contains no private device identifiers."""


async def bounded(awaitable, timeout: float = IO_TIMEOUT):
    return await asyncio.wait_for(awaitable, timeout)


def single_usb_device(devices):
    candidates = [device for device in devices if device.connection_type == "USB"]
    if not candidates:
        raise DeviceCheckError("No USB device found. Connect and unlock the iPhone, then trust this computer.")
    if len(candidates) != 1:
        raise DeviceCheckError("Multiple USB Apple devices found. Disconnect the others and retry.")
    return candidates[0]


def single_watch(registry: Any) -> str:
    if not isinstance(registry, list) or not registry:
        raise DeviceCheckError("The iPhone reports no paired Watch. Keep the paired Watch unlocked and nearby.")
    if len(registry) != 1:
        raise DeviceCheckError("Multiple paired Watches reported. This helper cannot safely choose the forwarding target.")
    identifier = registry[0]
    # Identifiers become local pairing-record filenames; accept no path separators.
    if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9-]{8,80}", identifier):
        raise DeviceCheckError("The paired Watch registry has an unexpected format; no action was taken.")
    return identifier


def verify_watch(watch, expected_udid: str) -> None:
    if watch.device_class != DeviceClass.WATCH or watch.udid != expected_udid:
        raise DeviceCheckError("The forwarded connection does not match the expected Apple Watch; no reveal request was sent.")


async def companion_request(iphone, request: dict[str, Any]) -> dict[str, Any]:
    # A fresh service for each request avoids the fork's documented socket-lifetime bug.
    async with await iphone.start_lockdown_service(PROXY_SERVICE) as connection:
        response = await connection.send_recv_plist(request)
    if not isinstance(response, dict) or response.get("Error"):
        raise DeviceCheckError("The iPhone's Watch connection rejected the request. Unlock both devices and retry.")
    return response


class WatchTransport:
    def __init__(self, iphone):
        self.iphone = iphone
        self.forwarded: dict[int, int] = {}
        self.service_names: dict[int, str] = {LOCKDOWN_PORT: "com.apple.mobile.lockdownd"}
        self.connections = []

    async def connect(self, remote_port: int):
        if remote_port not in self.forwarded:
            request: dict[str, Any] = {
                "Command": "StartForwardingServicePort",
                "GizmoRemotePortNumber": remote_port,
                "IsServiceLowPriority": False,
                "PreferWifi": False,
            }
            if remote_port in self.service_names:
                request["ForwardedServiceName"] = self.service_names[remote_port]
            response = await bounded(companion_request(self.iphone, request))
            port = response.get("CompanionProxyServicePort")
            if type(port) is not int or not 0 < port <= 65535:
                raise DeviceCheckError("The iPhone did not provide a usable Watch forwarding port.")
            self.forwarded[remote_port] = port
        # The forwarding listener can take a moment to become ready.
        for attempt in range(10):
            try:
                connection = await bounded(self.iphone.create_service_connection(self.forwarded[remote_port]))
                self.connections.append(connection)
                return connection
            except (OSError, ConnectionError):
                if attempt == 9:
                    raise
                await asyncio.sleep(0.1)

    async def close(self):
        for connection in reversed(self.connections):
            try:
                await bounded(connection.close(), 3)
            except Exception:
                pass
        for remote_port in reversed(self.forwarded):
            try:
                await bounded(companion_request(self.iphone, {
                    "Command": "StopForwardingServicePort",
                    "GizmoRemotePortNumber": remote_port,
                }), 5)
            except Exception:
                print("A temporary Watch connection could not be cleaned up; disconnect/reconnect the iPhone if retrying.", flush=True)


class WatchLockdown(LockdownClient):
    """Keep Watch identity/pairing separate from the iPhone's USB transport."""

    def __init__(self, *args, transport: WatchTransport, **kwargs):
        self.transport = transport
        super().__init__(*args, **kwargs)

    async def create_service_connection(self, port: int):
        return await self.transport.connect(port)

    async def get_service_connection_attributes(self, name: str, include_escrow_bag: bool = False):
        attributes = await super().get_service_connection_attributes(name, include_escrow_bag)
        port = attributes.get("Port")
        if type(port) is not int or not 0 < port <= 65535:
            raise DeviceCheckError("The Watch returned an invalid service port.")
        self.transport.service_names[port] = name
        return attributes


async def reveal_toggle(watch, expected_udid: str):
    verify_watch(watch, expected_udid)
    # This is precisely pymobiledevice3 AmfiService's reveal operation, with
    # explicit connection cleanup. Actions 1 and 2 are deliberately never sent.
    async with await watch.start_lockdown_service(AMFI_SERVICE) as connection:
        response = await connection.send_recv_plist({"action": 0})
    if not isinstance(response, dict) or response.get("success") is not True:
        raise DeviceCheckError("The Watch did not confirm revealing Developer Mode. No enable/restart request was sent.")


async def inspect_or_reveal(reveal: bool):
    iphone = None
    watch = None
    transport = None
    stage = "finding the USB iPhone"
    try:
        device = single_usb_device(await bounded(usbmux.list_devices()))
        stage = "opening the trusted iPhone connection"
        iphone = await bounded(create_using_usbmux(serial=device.serial, connection_type="USB", autopair=False))
        if iphone.device_class != DeviceClass.IPHONE:
            raise DeviceCheckError("The connected USB device is not an iPhone. Connect the Watch's paired iPhone.")
        if not iphone.paired:
            raise DeviceCheckError("This computer is not trusted by the iPhone. Trust it in Apple Devices/iTunes, then retry.")
        print(f"iPhone connected (iOS {iphone.product_version}); identifiers and device names are hidden.", flush=True)
        stage = "reading the paired Watch registry"
        registry = await bounded(companion_request(iphone, {"Command": "GetDeviceRegistry"}))
        watch_udid = single_watch(registry.get("PairedDevicesArray"))
        print("One paired Watch found. Checking the Watch connection.", flush=True)
        transport = WatchTransport(iphone)
        stage = "connecting to the paired Watch"
        connection = await transport.connect(LOCKDOWN_PORT)
        watch = await bounded(WatchLockdown.create(
            service=connection,
            identifier=watch_udid,
            system_buid=iphone.system_buid,
            autopair=False,
            pairing_records_cache_folder=PAIRING_CACHE,
            port=LOCKDOWN_PORT,
            transport=transport,
        ))
        verify_watch(watch, watch_udid)
        print(f"Verified Apple Watch (watchOS {watch.product_version}).", flush=True)
        if not watch.paired:
            if not reveal:
                print("Watch developer pairing is not established. Run with --reveal to pair and reveal the toggle.", flush=True)
                return
            stage = "waiting for the Watch Trust confirmation"
            print("Accept the Trust/pairing request ON THE WATCH. Waiting up to 60 seconds.", flush=True)
            await bounded(watch.pair(timeout=TRUST_TIMEOUT), TRUST_TIMEOUT + 5)
            if not await bounded(watch.validate_pairing()):
                raise DeviceCheckError("Watch pairing could not be validated. Unlock the Watch and retry.")
            verify_watch(watch, watch_udid)
        stage = "reading the Watch Developer Mode status"
        try:
            enabled = await bounded(watch.get_developer_mode_status())
        except Exception:
            enabled = None
        if enabled:
            print("Developer Mode is already enabled ON THE WATCH.", flush=True)
            return
        print("Watch Developer Mode is " + ("disabled." if enabled is False else "not yet readable."), flush=True)
        if not reveal:
            print("Inspection complete; no new pairing or Developer Mode changes requested.", flush=True)
            return
        stage = "revealing the Watch Developer Mode toggle"
        await bounded(reveal_toggle(watch, watch_udid))
        print("The Watch confirmed the reveal request. On the Watch open Settings > Privacy & Security > Developer Mode.", flush=True)
        print("Turn it on, restart when prompted, then confirm Turn On/Trust on the Watch. This helper does not restart either device.", flush=True)
    except DeviceCheckError:
        raise
    except TimeoutError:
        raise DeviceCheckError(f"Timed out while {stage}. Keep both devices unlocked, connected and nearby, then retry.") from None
    except Exception as error:
        # Library errors can contain full UDIDs, pairing details or personal names.
        # Emit the exception class and operation, never the raw exception payload.
        raise DeviceCheckError(f"Failed while {stage} ({type(error).__name__}). Unlock both devices, check Trust prompts, then retry.") from None
    finally:
        if watch is not None:
            try:
                await bounded(watch.close(), 3)
            except Exception:
                pass
        if transport is not None:
            await transport.close()
        if iphone is not None:
            try:
                await bounded(iphone.close(), 3)
            except Exception:
                pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--inspect", action="store_true", help="Read connection/status only (the default).")
    modes.add_argument("--reveal", action="store_true", help="Pair with the Watch if required and reveal its Developer Mode toggle.")
    args = parser.parse_args()
    logging.disable(logging.CRITICAL)
    if importlib.metadata.version("pymobiledevice3") != REQUIRED_VERSION:
        print(f"Use the isolated device-tools environment with pymobiledevice3=={REQUIRED_VERSION}.", file=sys.stderr)
        return 2
    try:
        asyncio.run(inspect_or_reveal(args.reveal))
    except DeviceCheckError as error:
        print(str(error), file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("Stopped. No enable/restart request was sent.", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
