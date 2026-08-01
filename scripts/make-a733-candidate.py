#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import sys
import tempfile
from pathlib import Path
from types import ModuleType
from typing import Any


def load_checker() -> ModuleType:
    path = Path(__file__).with_name("check-a733-parity.py")
    spec = importlib.util.spec_from_file_location("a733_parity_checker", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load parity checker from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


checker = load_checker()


def atomic_write(path: Path, content: str, mode: int = 0o444) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate an immutable A733 source/Nix/toplevel candidate manifest"
    )
    parser.add_argument("--map", required=True, type=Path)
    parser.add_argument("--source-worktree", required=True, type=Path)
    parser.add_argument("--nix-worktree", required=True, type=Path)
    parser.add_argument("--source-tag", required=True)
    parser.add_argument("--source-hash", required=True)
    parser.add_argument("--toplevel", required=True, type=Path)
    parser.add_argument("--boot-config", required=True, type=Path)
    parser.add_argument("--candidate-dir", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        source_worktree = args.source_worktree.resolve(strict=True)
        nix_worktree = args.nix_worktree.resolve(strict=True)
        candidate_dir = args.candidate_dir.resolve(strict=True)
        if not candidate_dir.is_dir() or candidate_dir.is_symlink():
            raise checker.CheckError(f"invalid candidate directory: {candidate_dir}")
        rows = checker.parse_map(args.map)
        checker.validate_required_feature_set(rows)
        checker.validate_unique_targets(rows)
        source_sha = checker.git_clean_head(source_worktree, "source")
        nix_commit = checker.git_clean_head(nix_worktree, "Nix")
        tag_sha = checker.run(
            ["git", "rev-parse", f"{args.source_tag}^{{commit}}"],
            cwd=source_worktree,
        ).stdout.strip()
        if tag_sha != source_sha:
            raise checker.CheckError("source tag does not resolve to source HEAD")
        if not checker.SRI_SHA256_RE.fullmatch(args.source_hash):
            raise checker.CheckError("source hash is not a Nix SHA-256 SRI")
        toplevel = args.toplevel.resolve(strict=True)
        if toplevel.parent != Path("/nix/store") or not toplevel.is_dir():
            raise checker.CheckError(f"invalid NixOS toplevel: {toplevel}")
        candidate_id = hashlib.sha256(
            f"{source_sha}\n{nix_commit}\n{toplevel}\n".encode()
        ).hexdigest()
        if candidate_dir.name != candidate_id:
            raise checker.CheckError(
                f"candidate directory {candidate_dir.name} != computed {candidate_id}"
            )
        boot_config = args.boot_config.resolve(strict=True)
        if boot_config.parent != candidate_dir or args.boot_config.is_symlink():
            raise checker.CheckError("boot config must be a direct regular candidate file")
        checker.require_regular(args.boot_config, "boot config evidence")
        existing = {entry.resolve() for entry in candidate_dir.iterdir()}
        if existing != {boot_config}:
            raise checker.CheckError(
                "new candidate directory may contain only the boot config evidence"
            )
        default_label, blocks = checker.parse_extlinux(boot_config)
        vendor_init = f"{toplevel}/specialisation/a733-vendor-6.6/init"
        if checker.block_init_values(blocks[default_label]) != [vendor_init]:
            raise checker.CheckError(
                "extlinux DEFAULT does not point to the candidate vendor specialisation"
            )
        mainline_init = f"{toplevel}/init"
        mainline_labels = [
            label
            for label, lines in blocks.items()
            if checker.block_init_values(lines) == [mainline_init]
        ]
        if len(mainline_labels) != 1:
            raise checker.CheckError(
                f"expected one candidate mainline extlinux label, got {mainline_labels}"
            )
        evaluated_source_hash = checker.run(
            [
                "nix",
                "eval",
                "--impure",
                "--raw",
                ".#nixosConfigurations.seldon-1.config.boot.kernelPackages.kernel.src.outputHash",
            ],
            cwd=nix_worktree,
        ).stdout.strip()
        if evaluated_source_hash != args.source_hash:
            raise checker.CheckError(
                "supplied source hash differs from current Nix kernel source hash"
            )
        kernelrelease = checker.run(
            [
                "nix",
                "eval",
                "--impure",
                "--raw",
                ".#nixosConfigurations.seldon-1.config.boot.kernelPackages.kernel.modDirVersion",
            ],
            cwd=nix_worktree,
        ).stdout.strip()
        if not kernelrelease:
            raise checker.CheckError("Nix kernelrelease evaluation was empty")
        closure = checker.closure_paths(toplevel)
        artifacts_by_path: dict[str, dict[str, Any]] = {}
        for row in rows:
            for expected in row.target_artifact:
                artifact_path = expected["path"]
                if Path(artifact_path).parts[0] not in closure:
                    continue
                try:
                    _path, digest, machine = checker.resolve_artifact(
                        artifact_path, closure
                    )
                except checker.CheckError:
                    continue
                if expected["sha256"] != "candidate" and digest != expected["sha256"]:
                    raise checker.CheckError(
                        f"fixed artifact hash mismatch for {artifact_path}"
                    )
                if machine != expected["elf_machine"]:
                    raise checker.CheckError(
                        f"artifact ELF machine mismatch for {artifact_path}"
                    )
                artifacts_by_path[artifact_path] = {
                    "path": artifact_path,
                    "sha256": digest,
                    "elf_machine": machine,
                }
        artifacts = [
            artifacts_by_path[path] for path in sorted(artifacts_by_path)
        ]
        boot_relative = boot_config.relative_to(candidate_dir).as_posix()
        candidate = {
            "schema_version": 1,
            "candidate_id": candidate_id,
            "source_sha": source_sha,
            "source_tag": args.source_tag,
            "source_hash": args.source_hash,
            "nix_commit": nix_commit,
            "toplevel": str(toplevel),
            "kernelrelease": kernelrelease,
            "mainline_extlinux_label": mainline_labels[0],
            "boot_config": {
                "path": boot_relative,
                "sha256": checker.sha256_file(boot_config),
            },
            "artifacts": artifacts,
        }
        checker.validate_candidate_schema(candidate)
        candidate_json = json.dumps(candidate, indent=2, ensure_ascii=False) + "\n"
        results_lines = ["\t".join(checker.RESULTS_HEADER)]
        results_lines.extend(
            f"{row.feature_id}\tpending\t\t\t" for row in rows
        )
        results_tsv = "\n".join(results_lines) + "\n"
        os.chmod(boot_config, 0o444)
        atomic_write(candidate_dir / "candidate.json", candidate_json)
        atomic_write(candidate_dir / "results.tsv", results_tsv)
    except (checker.CheckError, OSError, ValueError) as exc:
        print(f"A733 candidate generation failed: {exc}", file=sys.stderr)
        return 1
    print(candidate_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
