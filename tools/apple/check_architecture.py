"""Check Gyma's source ownership and dependency boundaries without an Apple SDK.

This is a structural guard, not a Swift parser or a replacement for code review.
Run from any directory: python tools/apple/check_architecture.py
"""

from pathlib import Path
import re
import sys


CORE_DOMAINS = {
    "State", "Workout", "Exercises", "Coach", "Program", "Calendar",
    "Progress", "Profile", "Connectivity", "Persistence",
}
APP_AREAS = {"App", "Features", "Services", "UI"}
DEVICE_MODULES = {"WatchConnectivity", "HealthKit", "UserNotifications", "Security"}
CATCH_ALL_NAMES = {"Models.swift", "Helpers.swift", "Utils.swift", "Presentation.swift"}
IMPORT = re.compile(
    r"^\s*(?:@\w+(?:\([^\n]*?\))?\s+)*"
    r"(?:(?:public|internal|package|fileprivate|private)\s+)?import\s+"
    r"(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(\w+)",
    re.MULTILINE,
)
DIRECT_IO = re.compile(r"\b(?:FileManager|URLSession|UserDefaults|WCSession|HKHealthStore)\b")


def code_only(source: str) -> str:
    """Mask comments and strings so examples and labels do not trigger checks.

    Recognizes nested Swift block comments, raw strings and multiline strings.
    String interpolation is masked too; compiler/review covers that limitation.
    """
    token = re.compile(r'//[^\n]*|/\*|(?P<hashes>\#*)(?P<quote>"""|")')
    block_boundary = re.compile(r"/\*|\*/")

    def block_comment_end(position: int) -> int:
        depth = 1
        while depth and position < len(source):
            boundary = block_boundary.search(source, position)
            if boundary is None:
                return len(source)
            depth += 1 if boundary[0] == "/*" else -1
            position = boundary.end()
        return position

    result = list(source)
    position = 0
    while match := token.search(source, position):
        start = match.start()
        end = match.end()
        if match[0] == "/*":
            end = block_comment_end(end)
        elif not match[0].startswith("//"):
            # String frames hold their delimiter/escape; interpolation frames
            # hold parenthesis depth. An explicit stack avoids recursive parsing.
            stack = [(match["quote"] + match["hashes"], "\\" + match["hashes"])]
            while stack and end < len(source):
                frame = stack[-1]
                if isinstance(frame, int):
                    if source[end] == "(":
                        stack[-1] += 1
                        end += 1
                    elif source[end] == ")":
                        if frame == 1:
                            stack.pop()
                        else:
                            stack[-1] -= 1
                        end += 1
                    elif nested := token.match(source, end):
                        end = nested.end()
                        if nested[0] == "/*":
                            end = block_comment_end(end)
                        elif not nested[0].startswith("//"):
                            stack.append((nested["quote"] + nested["hashes"], "\\" + nested["hashes"]))
                    else:
                        end += 1
                    continue
                delimiter, escape = frame
                if source.startswith(escape + "(", end):
                    stack.append(1)
                    end += len(escape) + 1
                elif source.startswith(escape, end):
                    end += len(escape) + 1
                elif source.startswith(delimiter, end):
                    end += len(delimiter)
                    stack.pop()
                else:
                    end += 1
        for index in range(start, min(end, len(source))):
            if result[index] != "\n":
                result[index] = " "
        position = end
    return "".join(result)


def check(root: Path) -> list[str]:
    errors = []
    core = root / "apple/Packages/GymaCore"
    areas = [
        (core / "Sources/GymaCore", CORE_DOMAINS, {"Foundation", "CoreFoundation"}),
        (core / "Tests/GymaCoreTests", CORE_DOMAINS | {"Support"}, {"Foundation", "XCTest", "GymaCore"}),
    ]
    for directory, domains, allowed_imports in areas:
        files = sorted(directory.rglob("*.swift"))
        if not files:
            errors.append(f"{directory.relative_to(root)}: missing Swift sources")
        for path in files:
            relative = path.relative_to(directory)
            label = path.relative_to(root).as_posix()
            if len(relative.parts) < 2 or relative.parts[0] not in domains:
                errors.append(f"{label}: place this file in its owning core domain")
            imports = set(IMPORT.findall(code_only(path.read_text(encoding="utf-8"))))
            for module in sorted(imports - allowed_imports):
                errors.append(f"{label}: core must not depend on {module}")

    for platform in ("iOS", "watchOS"):
        directory = root / "apple" / platform
        files = sorted(directory.rglob("*.swift"))
        if not files:
            errors.append(f"apple/{platform}: missing Swift sources")
        for path in files:
            relative = path.relative_to(directory)
            label = path.relative_to(root).as_posix()
            if len(relative.parts) < 2 or relative.parts[0] not in APP_AREAS:
                errors.append(f"{label}: use App, Features/<feature>, Services or UI")
            elif relative.parts[0] == "Features" and len(relative.parts) < 3:
                errors.append(f"{label}: give the feature an owning folder")
            if relative.parts[0] in {"Features", "UI"}:
                source = code_only(path.read_text(encoding="utf-8"))
                for module in sorted(set(IMPORT.findall(source)) & DEVICE_MODULES):
                    errors.append(f"{label}: move {module} integration into Services")
                if found := DIRECT_IO.search(source):
                    errors.append(f"{label}: move direct {found[0]} I/O into Services")

    for path in sorted((root / "apple").rglob("*.swift")):
        if any(part.startswith(".") or part in {"build", "Generated"} for part in path.relative_to(root).parts):
            continue
        if path.name in CATCH_ALL_NAMES:
            errors.append(f"{path.relative_to(root).as_posix()}: name the owning feature or responsibility")
    return errors


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    errors = check(root)
    if errors:
        print("Architecture checks failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("Architecture checks passed: core dependencies, feature ownership and device I/O boundaries.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
