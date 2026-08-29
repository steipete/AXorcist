#!/usr/bin/env python3
"""Evaluate the real manifest and resolve versioned graphs using offline Git mirrors.

No production sources are compiled, and no user SwiftPM/Git configuration is used.
--manifest supports checking a historical manifest without changing the checkout.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile


AXORCIST_URL = "https://github.com/openclaw/AXorcist.git"
COMMANDER_URL = "https://github.com/steipete/Commander.git"
LOG_URL = "https://github.com/apple/swift-log.git"
FIXTURE_VERSION = "0.1.6"  # Synthetic tag in disposable repositories only.


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


class Harness:
    def __init__(self, root, manifest):
        self.root = root
        self.manifest = manifest
        # Do not inherit credentials, Git overrides, or SwiftPM mirror settings.
        self.env = {
            key: os.environ[key]
            for key in ("PATH", "TMPDIR", "DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS")
            if key in os.environ
        }
        self.env.update(
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_TERMINAL_PROMPT="0",
            GIT_ALLOW_PROTOCOL="file",
            GIT_AUTHOR_NAME="AXorcist Fixture",
            GIT_AUTHOR_EMAIL="fixture@example.invalid",
            GIT_COMMITTER_NAME="AXorcist Fixture",
            GIT_COMMITTER_EMAIL="fixture@example.invalid",
            XDG_CONFIG_HOME=str(root / "xdg"),
            CLANG_MODULE_CACHE_PATH=str(root / "modules"),
        )

    def run(self, args, cwd):
        with subprocess.Popen(
            [str(arg) for arg in args],
            cwd=cwd,
            env=self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        ) as process:
            try:
                stdout, stderr = process.communicate(timeout=600)
            except subprocess.TimeoutExpired:
                # Stop only this invocation's process group, including compilers.
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
                raise
        require(
            process.returncode == 0,
            f"Command failed ({process.returncode}): {args}\n"
            f"{stdout[-4000:]}{stderr[-6000:]}",
        )
        return stdout

    def package(self, path, state, *args, cache=None, scratch=None, mode="shared"):
        command = [
            "swift", "package", "--package-path", path,
            "--cache-path", cache or state / "cache",
            "--config-path", state / "config",
            "--security-path", state / "security",
            "--disable-keychain", "--disable-netrc", "--manifest-cache", mode,
        ]
        if scratch is not None:
            command += ["--scratch-path", scratch]
        return self.run(command + list(args), path)

    def dump(self, path, state, **options):
        return json.loads(self.package(path, state, "dump-package", **options))

    def copy_manifest(self, path):
        path.mkdir(parents=True, exist_ok=True)
        (path / "Package.swift").write_bytes(self.manifest)

    def assert_remote(self, manifest):
        dependencies = manifest["dependencies"]
        commander = [
            dependency for dependency in dependencies
            if any(
                entry["identity"] == "commander"
                for kind in ("sourceControl", "fileSystem")
                for entry in dependency.get(kind, [])
            )
        ]
        require(len(commander) == 1, f"Expected one Commander dependency: {dependencies}")
        dependency = commander[0]
        require("sourceControl" in dependency, f"Commander became filesystem: {dependency}")
        entry = dependency["sourceControl"][0]
        require(entry["requirement"] == {"exact": ["0.2.4"]}, f"Not exact 0.2.4: {entry}")
        require(
            entry["location"] == {"remote": [{"urlString": COMMANDER_URL}]},
            f"Commander URL changed: {entry}",
        )

    def matrix(self, mode, across_paths=False):
        base = self.root / f"matrix-{mode}-{'shared-paths' if across_paths else 'isolated-paths'}"
        layouts = (
            "ordinary/.build/checkouts/AXorcist",
            "custom/scratch/checkouts/AXorcist",
            "developer/AXorcist",
            "path with spaces/custom scratch/checkouts/AXorcist",
        )
        for index, layout in enumerate(layouts):
            path = base / layout
            state = base / f"state-{index}"
            self.copy_manifest(path)
            sibling = path.parent / "Commander"
            for phase in ("absent", "present", "removed"):
                if phase == "present":
                    sibling.mkdir()
                elif phase == "removed":
                    sibling.rmdir()
                manifest = self.dump(
                    path, state, cache=base / "shared-cache" if across_paths else None,
                    scratch=state / "scratch", mode=mode,
                )
                try:
                    self.assert_remote(manifest)
                except AssertionError as error:
                    raise AssertionError(f"{mode}, {layout}, sibling {phase}: {error}") from error
            print(f"  PASS {mode}: {layout}: absent -> present -> removed", flush=True)

    def git(self, path, *args):
        return self.run([
            "git", "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false",
            "-c", f"core.hooksPath={self.root / 'empty-hooks'}", *args,
        ], path).strip()

    def commit(self, path, version):
        self.git(path, "add", ".")
        self.git(path, "commit", "--no-gpg-sign", "-m", "Fixture " + version)
        self.git(path, "tag", version)
        return self.git(path, "rev-parse", "HEAD")

    def library(self, name, product):
        path = self.root / "repositories" / name
        write(path / "Package.swift", f'''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "{name}",
    products: [.library(name: "{product}", targets: ["{product}"])],
    targets: [.target(name: "{product}")]
)
''')
        write(path / "Sources" / product / "Fixture.swift", "// Graph-only fixture.\n")
        self.git(path, "init", "--template=", "-b", "main")
        return path

    def repositories(self):
        commander = self.library("Commander", "Commander")
        commander_revision = self.commit(commander, "0.2.4")
        write(commander / "newer-release.txt", "Must not select 0.2.5 or main.\n")
        self.commit(commander, "0.2.5")
        logging = self.library("swift-log", "Logging")
        log_revision = self.commit(logging, "1.5.4")
        axorcist = self.root / "repositories" / "AXorcist"
        self.copy_manifest(axorcist)
        manifest = self.dump(axorcist, self.root / "repository-state")
        # Only target placeholders are needed to validate the dependency graph.
        for target in manifest["targets"]:
            filename = "main.swift" if target["type"] == "executable" else "Fixture.swift"
            target_path = (axorcist / target["path"]).resolve()
            require(target_path.is_relative_to(axorcist), f"Target escapes fixture: {target_path}")
            write(target_path / filename, "// Graph-only fixture.\n")
        self.git(axorcist, "init", "--template=", "-b", "main")
        axorcist_revision = self.commit(axorcist, FIXTURE_VERSION)
        self.mirrors = {
            AXORCIST_URL: axorcist, COMMANDER_URL: commander, LOG_URL: logging,
        }
        self.expected = {
            "axorcist": (FIXTURE_VERSION, axorcist_revision),
            "commander": ("0.2.4", commander_revision),
            "swift-log": ("1.5.4", log_revision),
        }

    def mirror(self, path, state):
        for original, repository in self.mirrors.items():
            self.package(
                path, state, "config", "set-mirror",
                "--original", original, "--mirror", repository.as_uri(),
            )

    def consumer(self, path, local=False):
        override = '\n        .package(path: "../Commander"),' if local else ""
        write(path / "Package.swift", f'''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Consumer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "{AXORCIST_URL}", exact: "{FIXTURE_VERSION}"),{override}
    ],
    targets: [.target(name: "Consumer")]
)
''')
        write(path / "Sources/Consumer/Fixture.swift", "// Graph-only fixture.\n")

    def check_graph(self, path, state, *, scratch=None, local=None, root_axorcist=False):
        graph = json.loads(self.package(
            path, state, "show-dependencies", "--format", "json", scratch=scratch,
        ))
        nodes = {}

        def visit(node):
            for child in node["dependencies"]:
                require(
                    nodes.get(child["identity"], child) == child,
                    f"Conflicting graph entries for {child['identity']}",
                )
                nodes[child["identity"]] = child
                visit(child)

        visit(graph)
        pins = {
            pin["identity"]: pin
            for pin in json.loads((path / "Package.resolved").read_text())["pins"]
        }
        expected = dict(self.expected)
        if root_axorcist:
            del expected["axorcist"]
        require(set(nodes) == set(expected), f"Unexpected graph: {nodes}")
        if local is None:
            require(set(pins) == set(expected), f"Unexpected pins: {pins}")
        for identity, (version, revision) in expected.items():
            node = nodes[identity]
            if identity == "commander" and local is not None:
                require(Path(node["path"]).resolve() == local.resolve(), f"Override unused: {node}")
                require(node["version"] == "unspecified", f"Override still versioned: {node}")
                continue
            require(node["version"] == version, f"Wrong graph version: {node}")
            pin = pins[identity]
            require(pin["kind"] == "remoteSourceControl", f"Not versioned: {pin}")
            require(pin["state"] == {"revision": revision, "version": version}, f"Wrong pin: {pin}")
        if not root_axorcist:
            ax_path = Path(nodes["axorcist"]["path"])
            require((ax_path / "Package.swift").read_bytes() == self.manifest, "Manifest changed")
        return nodes

    def graph(self, custom):
        base = self.root / ("graph custom with spaces" if custom else "graph-default")
        path, state = base / "Consumer", base / "state"
        scratch = base / "custom scratch" if custom else None
        self.consumer(path)
        self.mirror(path, state)
        build = scratch or path / ".build"
        require(not (build / "checkouts/Commander").exists(), "Sibling already exists")
        for iteration in range(2):
            self.package(path, state, "resolve", scratch=scratch)
            nodes = self.check_graph(path, state, scratch=scratch)
            ax_path = Path(nodes["axorcist"]["path"])
            commander_path = Path(nodes["commander"]["path"])
            require(ax_path.parent == build / "checkouts", f"Wrong scratch layout: {ax_path}")
            require(commander_path == ax_path.parent / "Commander", "No real Commander sibling")
            for mode in ("shared", "none"):
                self.assert_remote(self.dump(
                    ax_path, state / "checkout-probe", scratch=state / "probe-scratch", mode=mode,
                ))
            print(f"  PASS {base.name}: resolution {iteration + 1}, Commander exact 0.2.4", flush=True)

    def overrides(self, root_axorcist):
        base = self.root / ("edit-axorcist" if root_axorcist else "edit-consumer")
        path, state = base / "Workspace", base / "state"
        if root_axorcist:
            shutil.copytree(self.mirrors[AXORCIST_URL], path, ignore=shutil.ignore_patterns(".git", ".build"))
        else:
            self.consumer(path)
        self.mirror(path, state)
        original = (path / "Package.swift").read_bytes()
        self.package(path, state, "resolve")
        self.check_graph(path, state, root_axorcist=root_axorcist)
        sibling = base / "Commander"
        self.git(base, "clone", self.mirrors[COMMANDER_URL], sibling)
        self.package(path, state, "edit", "Commander", "--path", "../Commander")
        self.check_graph(path, state, local=sibling, root_axorcist=root_axorcist)
        require((path / "Package.swift").read_bytes() == original, "edit changed manifest")
        workspace = json.loads((path / ".build/workspace-state.json").read_text())
        commander = next(
            entry for entry in workspace["object"]["dependencies"]
            if entry["packageRef"]["identity"] == "commander"
        )
        require(commander["state"]["name"] == "edited", f"Workspace not edited: {commander}")
        self.package(path, state, "unedit", "Commander")
        self.check_graph(path, state, root_axorcist=root_axorcist)
        require((path / "Package.swift").read_bytes() == original, "edit/unedit changed manifest")
        require(sibling.is_dir(), "unedit removed developer checkout")
        print(f"  PASS {base.name}: resolve -> edit ../Commander -> unedit", flush=True)

    def path_override(self):
        base = self.root / "root-path-override"
        path, state, sibling = base / "Consumer", base / "state", base / "Commander"
        self.consumer(path)
        self.mirror(path, state)
        self.package(path, state, "resolve")
        self.git(base, "clone", self.mirrors[COMMANDER_URL], sibling)
        self.consumer(path, local=True)
        self.package(path, state, "resolve")
        self.check_graph(path, state, local=sibling)
        self.consumer(path)
        self.package(path, state, "resolve")
        self.check_graph(path, state)
        print("  PASS root .package(path:) override -> remove override -> exact 0.2.4", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest", type=Path,
        default=Path(__file__).resolve().parents[1] / "Package.swift",
    )
    parser.add_argument("--suite", choices=("all", "matrix", "graph", "overrides"), default="all")
    args = parser.parse_args()
    manifest = args.manifest.read_bytes()
    failures = []
    with tempfile.TemporaryDirectory(prefix="axorcist-commander-") as temporary:
        harness = Harness(Path(temporary).resolve(), manifest)
        cases = []
        if args.suite in ("all", "matrix"):
            cases += [
                (f"matrix {mode}", lambda mode=mode: harness.matrix(mode))
                for mode in ("shared", "none")
            ]
            # Reuse a cache while moving identical manifest bytes between paths.
            cases.append((
                "shared cache across paths", lambda: harness.matrix("shared", across_paths=True),
            ))
        if args.suite in ("all", "graph", "overrides"):
            print("SETUP offline versioned repositories", flush=True)
            harness.repositories()
        if args.suite in ("all", "graph"):
            cases += [
                ("default graph", lambda: harness.graph(False)),
                ("custom graph", lambda: harness.graph(True)),
            ]
        if args.suite in ("all", "overrides"):
            cases += [
                ("AXorcist workspace edit", lambda: harness.overrides(True)),
                ("consumer workspace edit", lambda: harness.overrides(False)),
                ("root path override", harness.path_override),
            ]
        for name, case in cases:
            print(f"RUN {name}", flush=True)
            try:
                case()
            except (AssertionError, subprocess.TimeoutExpired) as error:
                failures.append(name)
                print(f"FAIL {name}: {error}", flush=True)
    require(not failures, "Failed suites: " + ", ".join(failures))
    print("test-commander-dependency: ok", flush=True)


if __name__ == "__main__":
    main()
