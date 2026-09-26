#!/usr/bin/env python3
"""Packaging orchestration regressions; cryptographic/browser proofs run separately."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("bundle_execution_host", Path(__file__).with_name("bundle-execution-host.py"))
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="matind-package-regression-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "Preview.app"
        (self.app / "Contents").mkdir(parents=True)
        self.frontend = self.root / "frontend"
        self.target = self.frontend / "apps/desktop/local-server/target"
        stale = self.target / "debug/matind-local-service"
        stale.parent.mkdir(parents=True)
        stale.write_bytes(b"OLD BUILD MUST NEVER SHIP")
        self.artifact = self.target / "aarch64-apple-darwin/debug/matind-local-service"
        self.artifact.parent.mkdir(parents=True)
        self.artifact.write_bytes(b"CURRENT CARGO ARTIFACT")
        self.module = self.root / "module"
        self.module.mkdir()
        (self.module / "driver.mjs").write_text("export {}")
        self.node = self.root / "node"
        self.node.write_bytes(b"test node")

    def invoke(self, distribution="direct", build_configuration="LocalOperations", extra_environment=None):
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "APP_CONFIG_NAME": "本机", "MATIND_DISTRIBUTION": distribution,
            "MATIND_BUILD_CONFIGURATION": build_configuration,
        }))
        environment = dict(os.environ)
        environment.pop("CARGO_BUILD_TARGET", None)
        environment["CARGO_TARGET_DIR"] = str(self.root / "unrelated-global-target")
        environment.update(extra_environment or {})
        artifact = {"reason": "compiler-artifact", "target": {"name": "matind-local-service", "kind": ["bin"]}, "executable": str(self.artifact)}
        def command(args, **kwargs):
            return subprocess.CompletedProcess(args, 0, stdout=json.dumps(artifact) + "\n" if args[0] == "cargo" else "", stderr="")
        arguments = ["bundle", "--app", str(self.app), "--frontend", str(self.frontend), "--module", str(self.module), "--node", str(self.node), "--public-root", "A" * 43, "--development"]
        with patch.object(sys, "argv", arguments), patch.dict(os.environ, environment, clear=True), patch.object(subprocess, "run", side_effect=command) as commands, contextlib.redirect_stdout(io.StringIO()):
            bundle.main()
        return commands

    def test_packages_the_reported_cargo_artifact_even_with_global_target_override(self):
        commands = self.invoke()
        self.assertEqual((self.app / "Contents/Helpers/matind-local-service").read_bytes(), b"CURRENT CARGO ARTIFACT")
        cargo = next(call for call in commands.call_args_list if call.args[0][0] == "cargo")
        self.assertIn("--target-dir", cargo.args[0])
        self.assertNotIn("CARGO_TARGET_DIR", cargo.kwargs["env"])

    def test_browser_packaging_refuses_a_sandbox_application(self):
        with self.assertRaises(SystemExit):
            self.invoke(distribution="sandbox")
        self.assertFalse((self.app / "Contents/Helpers").exists())

    def test_development_root_only_belongs_to_local_operations(self):
        with self.assertRaises(SystemExit):
            self.invoke(build_configuration="ReleaseOperations")

    def test_ambient_cross_target_is_not_silently_packaged(self):
        with self.assertRaises(SystemExit):
            self.invoke(extra_environment={"CARGO_BUILD_TARGET": "x86_64-unknown-linux-gnu"})


if __name__ == "__main__":
    unittest.main()
