"""Safety checks for the optional Windows device helper; no device access."""

import importlib.util
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock

HAS_DEVICE_TOOLS = importlib.util.find_spec("pymobiledevice3") is not None
if HAS_DEVICE_TOOLS:
    import watch_developer_mode as helper


@unittest.skipUnless(HAS_DEVICE_TOOLS, "optional pymobiledevice3 environment is not installed")
class WatchSelectionTests(unittest.TestCase):
    def test_multiple_usb_devices_are_rejected(self):
        devices = [SimpleNamespace(connection_type="USB") for _ in range(2)]
        with self.assertRaises(helper.DeviceCheckError):
            helper.single_usb_device(devices)

    def test_usb_selection_ignores_network_duplicates(self):
        usb = SimpleNamespace(connection_type="USB")
        network = SimpleNamespace(connection_type="Network")
        self.assertIs(helper.single_usb_device([network, usb]), usb)

    def test_multiple_watches_are_rejected(self):
        with self.assertRaises(helper.DeviceCheckError):
            helper.single_watch(["aaaaaaaa", "bbbbbbbb"])

    def test_watch_pairing_filename_cannot_escape_cache(self):
        for identifier in ("../secrets", r"..\secrets", "", {"UDID": "aaaaaaaa"}):
            with self.subTest(identifier=identifier):
                with self.assertRaises(helper.DeviceCheckError):
                    helper.single_watch([identifier])


@unittest.skipUnless(HAS_DEVICE_TOOLS, "optional pymobiledevice3 environment is not installed")
class WatchRevealTests(unittest.IsolatedAsyncioTestCase):
    def make_watch(self, device_class=None, udid="aaaaaaaa"):
        connection = AsyncMock()
        connection.__aenter__.return_value = connection
        connection.send_recv_plist.return_value = {"success": True}
        watch = SimpleNamespace(
            device_class=device_class or helper.DeviceClass.WATCH,
            udid=udid,
            start_lockdown_service=AsyncMock(return_value=connection),
        )
        return watch, connection

    async def test_phone_never_receives_watch_reveal_request(self):
        watch, connection = self.make_watch(helper.DeviceClass.IPHONE)
        with self.assertRaises(helper.DeviceCheckError):
            await helper.reveal_toggle(watch, "aaaaaaaa")
        watch.start_lockdown_service.assert_not_awaited()
        connection.send_recv_plist.assert_not_awaited()

    async def test_other_watch_never_receives_reveal_request(self):
        watch, _ = self.make_watch(udid="bbbbbbbb")
        with self.assertRaises(helper.DeviceCheckError):
            await helper.reveal_toggle(watch, "aaaaaaaa")
        watch.start_lockdown_service.assert_not_awaited()

    async def test_reveal_sends_only_action_zero_and_closes_service(self):
        watch, connection = self.make_watch()
        await helper.reveal_toggle(watch, "aaaaaaaa")
        watch.start_lockdown_service.assert_awaited_once_with("com.apple.amfi.lockdown")
        connection.send_recv_plist.assert_awaited_once_with({"action": 0})
        connection.__aexit__.assert_awaited_once()

    async def test_rejected_reveal_is_not_reported_as_success(self):
        watch, connection = self.make_watch()
        connection.send_recv_plist.return_value = {"success": False}
        with self.assertRaises(helper.DeviceCheckError):
            await helper.reveal_toggle(watch, "aaaaaaaa")
        connection.__aexit__.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
