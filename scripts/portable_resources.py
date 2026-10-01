import json
import re
from pathlib import Path
import shlex
import subprocess
import sys


def portable_accessor(bundle_name):
    return f'''import Foundation

extension Foundation.Bundle {{
    static nonisolated let module: Bundle = {{
        let bundleName = "{bundle_name}"
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            executableDirectory.appendingPathComponent(bundleName),
            executableDirectory.deletingLastPathComponent()
                .appendingPathComponent("Resources").appendingPathComponent(bundleName)
        ]
        for candidate in candidates.compactMap({{ $0 }}) {{
            if let bundle = Bundle(url: candidate) {{ return bundle }}
        }}
        Swift.fatalError("Could not load resource bundle: \\(bundleName)")
    }}()
}}
'''


def rewrite_accessors(build_directory, check_only=False):
    accessors = sorted(build_directory.glob("*.build/DerivedSources/resource_bundle_accessor.swift"))
    if not accessors:
        raise ValueError("No SwiftPM resource accessors found")
    for accessor in accessors:
        source = accessor.read_text()
        match = re.search(r'(?:appendingPathComponent\(|let bundleName = )"([A-Za-z0-9_.-]+\.bundle)"', source)
        if not match or "static nonisolated let module: Bundle" not in source:
            raise ValueError(f"Unrecognized resource accessor: {accessor.parent.parent.name}")
        replacement = portable_accessor(match[1])
        if check_only:
            if source != replacement:
                raise ValueError(f"Resource accessor was regenerated: {accessor.parent.parent.name}")
        elif source != replacement:
            accessor.write_text(replacement)
    return len(accessors)


def command_arguments(manifest, command):
    block = re.search(r'^  "' + re.escape(command) + r'":\n(.*?)(?=^  "|\Z)', manifest, re.M | re.S)
    if not block or "    tool: shell\n" not in block[1]:
        raise ValueError(f"Missing SwiftPM compiler command: {command}")
    arguments = re.search(r'^    args: (\[.*\])$', block[1], re.M)
    if not arguments:
        raise ValueError(f"Missing SwiftPM compiler arguments: {command}")
    result = json.loads(arguments[1])
    if not result or not all(isinstance(argument, str) for argument in result):
        raise ValueError(f"Invalid SwiftPM compiler arguments: {command}")
    return [argument for argument in result if argument != "-parseable-output"]


def rebuild_resources(build_directory, manifest_path):
    manifest_path = manifest_path.resolve()
    manifest = manifest_path.read_text()
    platform = build_directory.resolve().parent.name
    link_arguments = command_arguments(manifest, f"C.flow-qwen-{platform}-release.exe")
    link_lists = [Path(argument[1:]) for argument in link_arguments
                  if argument.startswith("@") and argument.endswith("Objects.LinkFileList")]
    if len(link_lists) != 1:
        raise ValueError("Expected one engine object link list")
    linked_modules = {Path(path).parent.name for path in shlex.split(link_lists[0].read_text())}
    modules = sorted(path.parent.parent.name.removesuffix(".build") for path in
                     build_directory.glob("*.build/DerivedSources/resource_bundle_accessor.swift")
                     if path.parent.parent.name in linked_modules)
    if not modules:
        raise ValueError("No linked resource modules found")
    commands = [command_arguments(manifest, f"C.{module}-{platform}-release.module") for module in modules]
    commands.append(link_arguments)
    count = rewrite_accessors(build_directory)
    for arguments in commands:
        subprocess.run(arguments, cwd=manifest_path.parent.parent, check=True)
    rewrite_accessors(build_directory, check_only=True)
    return count


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[2] != "--check":
        count = rebuild_resources(Path(sys.argv[1]), Path(sys.argv[2]))
    else:
        count = rewrite_accessors(Path(sys.argv[1]), check_only="--check" in sys.argv[2:])
    print(f"RESOURCE PATHS PASS: {count} portable accessors")
