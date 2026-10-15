"""Regression checks for dependency leaks and misplaced sources."""

from pathlib import Path
import tempfile
import unittest

from check_architecture import check


class ArchitectureTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.write("apple/Packages/GymaCore/Sources/GymaCore/Workout/Workout.swift", "import Foundation")
        self.write("apple/Packages/GymaCore/Tests/GymaCoreTests/Workout/WorkoutTests.swift", "import XCTest\n@testable import GymaCore")
        for platform in ("iOS", "watchOS"):
            self.write(f"apple/{platform}/App/GymaApp.swift", "import SwiftUI")

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_feature_components_and_service_adapters_are_allowed(self):
        self.write("apple/iOS/Features/Workout/WorkoutView.swift", "import SwiftUI\nimport GymaCore")
        self.write("apple/watchOS/Services/Runtime.swift", "import HealthKit")
        self.assertEqual(check(self.root), [])

    def test_core_rejects_platform_dependency_even_with_import_attribute(self):
        self.write("apple/Packages/GymaCore/Sources/GymaCore/Workout/Workout.swift", "@preconcurrency import HealthKit")
        self.assertTrue(any("core must not depend on HealthKit" in error for error in check(self.root)))

    def test_feature_rejects_raw_storage_and_device_integrations(self):
        self.write("apple/iOS/Features/Workout/WorkoutView.swift", "import UserNotifications\nlet files = FileManager.default")
        errors = check(self.root)
        self.assertTrue(any("UserNotifications" in error for error in errors))
        self.assertTrue(any("FileManager" in error for error in errors))

    def test_scoped_and_access_modified_imports_respect_module_boundaries(self):
        self.write("apple/Packages/GymaCore/Sources/GymaCore/Workout/Workout.swift", "public import struct Foundation.Date")
        self.assertEqual(check(self.root), [])
        self.write("apple/iOS/Features/Workout/WorkoutView.swift", "import class UserNotifications.UNUserNotificationCenter\ninternal import HealthKit")
        errors = check(self.root)
        self.assertTrue(any("UserNotifications" in error for error in errors))
        self.assertTrue(any("HealthKit" in error for error in errors))

    def test_comments_and_strings_do_not_create_false_dependencies(self):
        self.write("apple/iOS/Features/Workout/WorkoutView.swift", '''import SwiftUI
/* outer /* import HealthKit */ FileManager */
// URLSession
let example = #"UserDefaults says \\"hello\\""#
let label = """
import Security
WCSession
"""
''')
        self.assertEqual(check(self.root), [])

    def test_nested_interpolation_masks_strings_and_resumes_at_real_code(self):
        path = "apple/iOS/Features/Workout/WorkoutView.swift"
        source = r'''import SwiftUI
let ordinary = "Value: \(render("FileManager"))"
let nested = "Value: \(render("Nested \(render("URLSession"))"))"
let raw = ##"Value \##(render(#"UserDefaults"#))"##
let multiline = """
Value \(render("""
WCSession
"""))
"""
let comment = "Value \(render(/* " ) /* nested */ */ "HKHealthStore"))"
'''
        self.write(path, source)
        self.assertEqual(check(self.root), [])
        self.write(path, source + "import Security\nlet files = FileManager.default")
        errors = check(self.root)
        self.assertTrue(any("Security" in error for error in errors))
        self.assertTrue(any("FileManager" in error for error in errors))

    def test_unowned_and_catch_all_files_are_rejected(self):
        self.write("apple/Packages/GymaCore/Sources/GymaCore/Models.swift", "import Foundation")
        self.write("apple/iOS/Features/Screen.swift", "import SwiftUI")
        self.write("apple/watchOS/Other/Screen.swift", "import SwiftUI")
        errors = check(self.root)
        self.assertTrue(any("owning core domain" in error for error in errors))
        self.assertTrue(any("owning feature or responsibility" in error for error in errors))
        self.assertTrue(any("owning folder" in error for error in errors))
        self.assertTrue(any("use App, Features/<feature>" in error for error in errors))

    def test_missing_source_tree_fails(self):
        self.assertTrue(any("missing Swift sources" in error for error in check(self.root / "missing")))

    def test_support_is_only_a_test_fixture_location(self):
        self.write("apple/Packages/GymaCore/Tests/GymaCoreTests/Support/Fixture.swift", "import GymaCore")
        self.assertEqual(check(self.root), [])
        self.write("apple/Packages/GymaCore/Sources/GymaCore/Support/Helper.swift", "import Foundation")
        self.assertTrue(any("owning core domain" in error for error in check(self.root)))


if __name__ == "__main__":
    unittest.main()
