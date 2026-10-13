#!/usr/bin/env python3
"""Launch the Release Watch app in a disposable simulator and verify its screen.

Run from native after building GymaWatch for watchOS Simulator. Requires Xcode
and an available watchOS 26+ simulator. Missing runtimes, crashes and missing
body content are failures; process survival alone does not establish success.
No physical devices, signing settings or user simulator data are modified.
"""

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


BUNDLE_ID = "com.mato.gyma.watchkitapp"
APP_NAME = "GymaWatch"
OCR_SOURCE = r'''
import Foundation
import Vision

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["en-US"]
request.usesLanguageCorrection = false
request.minimumTextHeight = 0.015
// Ignore the clock/title and bottom system chrome. A navigation title over an
// otherwise black view must fail even though the app process is still alive.
request.regionOfInterest = CGRect(x: 0, y: 0.08, width: 1, height: 0.70)
try VNImageRequestHandler(url: URL(fileURLWithPath: CommandLine.arguments[1]))
    .perform([request])
let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
let data = try JSONEncoder().encode(text)
print(String(decoding: data, as: UTF8.self))
'''


class SmokeFailure(RuntimeError):
    pass


class Smoke:
    def __init__(self, output):
        self.output = output.resolve()
        self.output.mkdir(parents=True, exist_ok=True)
        self.log = self.output / "commands.log"
        self.device = None
        self.started = time.time()
        self.results = []

    def run(self, args, *, timeout=60, check=True, filename=None):
        args = [str(arg) for arg in args]
        print("+ " + " ".join(args), flush=True)
        with self.log.open("a", encoding="utf-8") as log:
            log.write("\n+ " + " ".join(args) + "\n")
            try:
                result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
            except subprocess.TimeoutExpired as error:
                log.write(f"Timed out after {timeout} seconds\n")
                raise SmokeFailure(f"Command timed out after {timeout}s: {args}") from error
            log.write(result.stdout + result.stderr)
            if filename:
                (self.output / filename).write_text(result.stdout + result.stderr, encoding="utf-8")
            if check and result.returncode:
                raise SmokeFailure(f"Command failed ({result.returncode}): {args}\n{result.stdout}{result.stderr}")
            return result

    def simctl(self, *args, **kwargs):
        return self.run(["xcrun", "simctl", *args], **kwargs)

    def create_device(self):
        inventory = json.loads(self.simctl("list", "--json", filename="simulators.json").stdout)
        runtimes = sorted(
            (item for item in inventory["runtimes"]
             if item.get("isAvailable") and ".watchOS-" in item["identifier"]
             and int(item["version"].split(".")[0]) >= 26),
            key=lambda item: tuple(int(part) for part in item["version"].split(".")), reverse=True,
        )
        for runtime in runtimes:
            devices = inventory["devices"].get(runtime["identifier"], [])
            # Prefer a roomy screen for deterministic text recognition. This
            # device is created fresh; no existing simulator is erased or used.
            devices = sorted(devices, key=lambda item: ("46mm" in item["name"], "45mm" in item["name"]), reverse=True)
            for device in devices:
                if device.get("isAvailable") and device.get("deviceTypeIdentifier"):
                    self.device = self.simctl(
                        "create", "Gyma launch smoke", device["deviceTypeIdentifier"], runtime["identifier"]
                    ).stdout.strip()
                    (self.output / "selected-device.json").write_text(json.dumps({
                        "udid": self.device, "runtime": runtime, "type": device["deviceTypeIdentifier"],
                    }, indent=2), encoding="utf-8")
                    self.simctl("bootstatus", self.device, "-b", timeout=180)
                    return
        raise SmokeFailure("Watch launch smoke unavailable: no available watchOS 26+ simulator device/runtime. See simulators.json; this check did not pass.")

    def build_ocr(self):
        source = self.output / "ReadScreen.swift"
        source.write_text(OCR_SOURCE, encoding="utf-8")
        self.ocr = self.output / "read-screen"
        self.run(["xcrun", "--sdk", "macosx", "swiftc", source, "-o", self.ocr], timeout=120)

    def assert_alive(self, pid):
        # Simulator application PIDs are host processes. Check executable name
        # too, so a recycled PID or a zombie cannot make a crash look healthy.
        result = self.run(["ps", "-p", str(pid), "-o", "stat=", "-o", "comm="], check=False)
        state, _, command = result.stdout.strip().partition(" ")
        if result.returncode or "Z" in state or APP_NAME not in command:
            raise SmokeFailure(f"Watch app exited during launch (PID {pid}). See simulator.log and crash reports.")

    def screenshot(self, name):
        path = self.output / f"{name}.png"
        self.simctl("io", self.device, "screenshot", path)
        return path

    def check_scenario(self, name, expected_text):
        result = self.simctl(
            "launch", "--terminate-running-process",
            f"--stdout={self.output / (name + '-stdout.log')}",
            f"--stderr={self.output / (name + '-stderr.log')}",
            self.device, BUNDLE_ID, "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        )
        match = re.search(rf"{re.escape(BUNDLE_ID)}:\s*(\d+)", result.stdout)
        if not match:
            raise SmokeFailure(f"Watch launch did not return an application PID: {result.stdout}")
        pid = int(match.group(1))
        # Watch first-run startup can take a few seconds. Demand a live process
        # throughout, and retry the actual screenshot only for rendering delay.
        for _ in range(10):
            time.sleep(1)
            self.assert_alive(pid)
        recognized = []
        for attempt in range(1, 4):
            path = self.screenshot(f"{name}-{attempt}")
            recognized = json.loads(self.run([self.ocr, path], timeout=45).stdout)
            (self.output / f"{name}-{attempt}-text.json").write_text(json.dumps(recognized, indent=2), encoding="utf-8")
            visible = re.sub(r"[^a-z0-9]", "", " ".join(recognized).lower())
            self.assert_alive(pid)
            if all(re.sub(r"[^a-z0-9]", "", text.lower()) in visible for text in expected_text):
                shutil.copyfile(path, self.output / f"{name}.png")
                self.results.append({"scenario": name, "status": "passed", "pid": pid, "bodyText": recognized})
                print(f"PASS: {name}; visible body text: {recognized}", flush=True)
                self.simctl("terminate", self.device, BUNDLE_ID)
                return
            time.sleep(3)
        raise SmokeFailure(f"{name}: expected body text {expected_text}, but recognized {recognized}. See screenshots for a blank view, wrong screen or system dialog.")

    def seed_pending_finish_workout(self):
        # Use the real persisted journal format, without injecting app-only test
        # code. A queued finish deliberately suppresses Health authorization,
        # while exercising restored workout data and the exercise menu itself.
        now = time.time() - 978307200  # Swift Date's 2001 reference epoch.
        workout_id = "watch-smoke-workout"
        store_id = "watch-smoke-store"
        entries = [("watch-smoke-pull-ups", "Pull ups"), ("watch-smoke-row", "Seated row")]
        journal = {
            "retiredStoreIDs": [],
            "snapshot": {
                "storeID": store_id, "revision": 1, "generatedAt": now,
                "isTruncated": False, "totalExerciseCount": len(entries),
                "catalog": [{"id": key, "name": name, "muscle": "back", "iconKey": "barbell", "custom": True} for key, name in entries],
                "activeWorkout": {
                    "id": workout_id, "start": now - 60, "shift": "off", "energy": "good",
                    "exercises": [{"exerciseID": key, "sets": [], "target": {
                        "sets": 3, "repsMin": 8, "repsMax": 12, "restSeconds": 90, "reason": "",
                    }} for key, _ in entries],
                },
            },
            "pending": {
                "id": "watch-smoke-finish", "storeID": store_id, "workoutID": workout_id,
                "basedOnRevision": 1, "createdAt": now, "action": {"finishWorkout": {}},
            },
        }
        container = Path(self.simctl("get_app_container", self.device, BUNDLE_ID, "data").stdout.strip())
        directory = container / "Library" / "Application Support" / "GymaConnectivity"
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "watch-journal.json").write_text(json.dumps(journal), encoding="utf-8")
        (self.output / "pending-finish-fixture.json").write_text(json.dumps(journal, indent=2), encoding="utf-8")

    def diagnostics(self):
        if self.device:
            for args, filename in [
                (("io", self.device, "screenshot", self.output / "last-screen.png"), None),
                (("spawn", self.device, "log", "show", "--last", "5m", "--style", "compact", "--predicate",
                  f'process == "{APP_NAME}" OR eventMessage CONTAINS[c] "{BUNDLE_ID}"'), "simulator.log"),
            ]:
                try:
                    self.simctl(*args, check=False, filename=filename)
                except (SmokeFailure, OSError) as error:
                    print(f"Diagnostic collection failed: {error}", flush=True)
        reports = Path.home() / "Library" / "Logs" / "DiagnosticReports"
        if reports.exists():
            for report in reports.glob(f"{APP_NAME}*"):
                if report.is_file() and report.stat().st_mtime >= self.started:
                    shutil.copy2(report, self.output / report.name)

    def cleanup(self):
        if self.device:
            for operation in ("shutdown", "delete"):
                try:
                    self.simctl(operation, self.device, check=False)
                except (SmokeFailure, OSError) as error:
                    print(f"Simulator cleanup failed: {error}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", type=Path, default=Path("build/watch-smoke"))
    args = parser.parse_args()
    smoke = Smoke(args.output)
    status = "failed"
    failure = None
    try:
        if sys.platform != "darwin":
            raise SmokeFailure("Watch launch smoke requires macOS and Xcode; it has not run on this host.")
        if not args.app.is_dir():
            raise SmokeFailure(f"Watch Simulator app is missing: {args.app}")
        smoke.build_ocr()
        smoke.create_device()
        smoke.simctl("install", smoke.device, args.app.resolve(), timeout=90)
        smoke.check_scenario("fresh-no-workout", ["No workout ready"])
        smoke.seed_pending_finish_workout()
        smoke.check_scenario("restored-workout-pending-finish", ["Pull ups"])
        status = "passed"
    except (SmokeFailure, OSError, ValueError) as error:
        failure = str(error)
        print(f"::error::{failure}", flush=True)
    finally:
        smoke.diagnostics()
        smoke.cleanup()
        (smoke.output / "result.json").write_text(json.dumps({
            "status": status, "error": failure, "scenarios": smoke.results,
            "scope": "Simulator startup and visible body content; physical-device installation, Health authorization and workout interactions still require device testing.",
        }, indent=2), encoding="utf-8")
    return 0 if status == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
