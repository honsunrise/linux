#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

MAP_HEADER = [
    "feature_id",
    "kind",
    "vendor_evidence",
    "provider",
    "vendor_disable",
    "target_config",
    "target_dt",
    "target_artifact",
    "test_id",
]
RESULTS_HEADER = [
    "feature_id",
    "status",
    "candidate_id",
    "evidence_sha256",
    "evidence_path",
]
KINDS = {"config", "node", "module", "firmware", "userspace", "hardware"}
PROVIDERS = {
    "mainline",
    "linux-sunxi",
    "ported-bsp",
    "external-module",
    "external-package",
}
RESULT_STATUSES = {"pending", "blocked", "pass", "not-applicable"}
CONFIG_RE = re.compile(r"^(CONFIG_[A-Z0-9_]+)=(y|m|n)$")
HEX_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SRI_SHA256_RE = re.compile(r"^sha256-[A-Za-z0-9+/]{43}=$")
SOURCE_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
STORE_BASENAME_RE = re.compile(r"^[0-9a-z]{32}-.+$")

REQUIRED_HARDWARE_TESTS = {
    "boot.sh",
    "ufs.sh",
    "gmac.sh",
    "k3s-cilium.sh",
    "serial-ramoops-watchdog.sh",
    "clock-power-performance.sh",
    "pcie-nvme.sh",
    "usb-typec.sh",
    "display-hdmi.sh",
    "gpu.sh",
    "npu.sh",
    "media-camera.sh",
    "audio.sh",
    "wifi-bluetooth.sh",
    "board-io-security.sh",
}
REQUIRED_EXACT_FEATURES = {
    "module:pvrsrvkm",
    "module:aic_load_fw",
    "module:aic8800_fdrv",
    "module:aw_nna_vip",
    "module:nna_vip2",
    "firmware:rgx.fw.36.56.104.183",
    "firmware:rgx.sh.36.56.104.183",
    "userspace:libVK_IMG.so.24.2.6603887",
    "userspace:libsrv_um.so.24.2.6603887",
    "userspace:libNBGlinker.so",
    "userspace:libVIPhal.so",
    "userspace:vpm_run",
} | {f"hardware:{name}" for name in REQUIRED_HARDWARE_TESTS}


class CheckError(RuntimeError):
    pass


@dataclass(frozen=True)
class MapRow:
    feature_id: str
    kind: str
    vendor_evidence: list[str]
    provider: str
    vendor_disable: list[str]
    target_config: list[str]
    target_dt: list[dict[str, Any]]
    target_artifact: list[dict[str, Any]]
    test_id: list[str]
    line: int


@dataclass(frozen=True)
class ResultRow:
    feature_id: str
    status: str
    candidate_id: str
    evidence_sha256: str
    evidence_path: str
    line: int


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(
    argv: list[str],
    *,
    cwd: Path | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(
        argv,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and proc.returncode:
        command = " ".join(argv)
        raise CheckError(
            f"command failed ({proc.returncode}): {command}\n{proc.stderr.strip()}"
        )
    return proc


def require_regular(path: Path, what: str) -> Path:
    if path.is_symlink() or not path.is_file():
        raise CheckError(f"{what} is not a regular non-symlink file: {path}")
    return path


def resolve_relative_regular(base: Path, relative: str, what: str) -> Path:
    rel = Path(relative)
    if rel.is_absolute() or not relative or ".." in rel.parts:
        raise CheckError(f"unsafe {what} path: {relative!r}")
    base_real = base.resolve(strict=True)
    candidate = base / rel
    resolved = candidate.resolve(strict=True)
    if not resolved.is_relative_to(base_real):
        raise CheckError(f"{what} escapes {base}: {relative!r}")
    return require_regular(candidate, what)


def parse_json_array(raw: str, field: str, line: int) -> list[Any]:
    if "\t" in raw or "\n" in raw or "\r" in raw:
        raise CheckError(f"map line {line}: {field} contains tab/newline")
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise CheckError(f"map line {line}: invalid {field} JSON: {exc}") from exc
    if not isinstance(value, list):
        raise CheckError(f"map line {line}: {field} must be a JSON array")
    canonical = json.dumps(value, separators=(",", ":"), ensure_ascii=False)
    if raw != canonical:
        raise CheckError(
            f"map line {line}: {field} is not canonical compact JSON: {raw!r}"
        )
    return value


def validate_feature_id(feature_id: str, kind: str, line: int) -> None:
    prefix, separator, value = feature_id.partition(":")
    if not separator or prefix != kind or not value:
        raise CheckError(
            f"map line {line}: feature_id {feature_id!r} does not match kind {kind!r}"
        )
    if kind == "config" and not re.fullmatch(r"CONFIG_[A-Z0-9_]+", value):
        raise CheckError(f"map line {line}: invalid config feature_id {feature_id!r}")
    if kind == "node" and (not value.startswith("/") or ".." in Path(value).parts):
        raise CheckError(f"map line {line}: invalid node feature_id {feature_id!r}")
    if kind == "firmware":
        firmware_path = Path(value)
        if firmware_path.is_absolute() or ".." in firmware_path.parts:
            raise CheckError(f"map line {line}: invalid firmware feature_id {feature_id!r}")
    if kind == "hardware" and Path(value).name != value:
        raise CheckError(f"map line {line}: hardware ID must be a script basename")
    if kind in {"module", "userspace"} and ("/" in value or "\x00" in value):
        raise CheckError(f"map line {line}: invalid {kind} feature_id {feature_id!r}")


def parse_map(path: Path) -> list[MapRow]:
    require_regular(path, "parity map")
    rows: list[MapRow] = []
    seen: set[str] = set()
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle, delimiter="\t", lineterminator="\n")
        try:
            header = next(reader)
        except StopIteration as exc:
            raise CheckError("parity map is empty") from exc
        if header != MAP_HEADER:
            raise CheckError(f"invalid map header: {header!r}")
        for line, fields in enumerate(reader, start=2):
            if len(fields) != len(MAP_HEADER):
                raise CheckError(
                    f"map line {line}: expected {len(MAP_HEADER)} fields, got {len(fields)}"
                )
            values = dict(zip(MAP_HEADER, fields, strict=True))
            feature_id = values["feature_id"]
            kind = values["kind"]
            provider = values["provider"]
            if feature_id in seen:
                raise CheckError(f"map line {line}: duplicate feature_id {feature_id!r}")
            seen.add(feature_id)
            if kind not in KINDS:
                raise CheckError(f"map line {line}: invalid kind {kind!r}")
            if provider not in PROVIDERS:
                raise CheckError(f"map line {line}: invalid provider {provider!r}")
            validate_feature_id(feature_id, kind, line)
            arrays = {
                name: parse_json_array(values[name], name, line)
                for name in (
                    "vendor_evidence",
                    "vendor_disable",
                    "target_config",
                    "target_dt",
                    "target_artifact",
                    "test_id",
                )
            }
            if not arrays["vendor_evidence"]:
                raise CheckError(f"map line {line}: vendor_evidence cannot be empty")
            for evidence in arrays["vendor_evidence"]:
                if not isinstance(evidence, str) or not re.fullmatch(r"[^:\t\n]+:.+", evidence):
                    raise CheckError(
                        f"map line {line}: invalid vendor_evidence element {evidence!r}"
                    )
            for disabled in arrays["vendor_disable"]:
                if not isinstance(disabled, str) or not (
                    re.fullmatch(r"CONFIG_[A-Z0-9_]+=n", disabled)
                    or re.fullmatch(r"path:[^:\t\n]+:unselected", disabled)
                ):
                    raise CheckError(
                        f"map line {line}: invalid vendor_disable element {disabled!r}"
                    )
                if disabled.startswith("path:"):
                    disabled_path = Path(disabled[5:-11])
                    if disabled_path.is_absolute() or ".." in disabled_path.parts:
                        raise CheckError(
                            f"map line {line}: unsafe vendor_disable path {disabled!r}"
                        )
            config_assignments: set[str] = set()
            for assignment in arrays["target_config"]:
                if not isinstance(assignment, str):
                    raise CheckError(f"map line {line}: target_config values must be strings")
                match = CONFIG_RE.fullmatch(assignment)
                if not match:
                    raise CheckError(
                        f"map line {line}: invalid target_config element {assignment!r}"
                    )
                symbol = match.group(1)
                if symbol in config_assignments:
                    raise CheckError(
                        f"map line {line}: duplicate target config symbol {symbol}"
                    )
                config_assignments.add(symbol)
                if match.group(2) == "n" and assignment not in arrays["vendor_disable"]:
                    raise CheckError(
                        f"map line {line}: {assignment} lacks matching vendor_disable evidence"
                    )
            for assertion in arrays["target_dt"]:
                if not isinstance(assertion, dict) or set(assertion) != {
                    "blob",
                    "path",
                    "status",
                }:
                    raise CheckError(
                        f"map line {line}: invalid target_dt object {assertion!r}"
                    )
                blob = assertion["blob"]
                node_path = assertion["path"]
                if not isinstance(blob, str) or not (
                    blob == "base"
                    or (Path(blob).name == blob and blob.endswith(".dtbo"))
                ):
                    raise CheckError(f"map line {line}: invalid DT blob {blob!r}")
                if not isinstance(node_path, str) or not node_path.startswith("/"):
                    raise CheckError(f"map line {line}: invalid target DT path {node_path!r}")
                if assertion["status"] != "okay":
                    raise CheckError(
                        f"map line {line}: target_dt status must be 'okay'"
                    )
            for artifact in arrays["target_artifact"]:
                if not isinstance(artifact, dict) or set(artifact) != {
                    "path",
                    "sha256",
                    "elf_machine",
                }:
                    raise CheckError(
                        f"map line {line}: invalid target_artifact object {artifact!r}"
                    )
                artifact_path = artifact["path"]
                if not isinstance(artifact_path, str):
                    raise CheckError(f"map line {line}: artifact path must be a string")
                parts = Path(artifact_path).parts
                if (
                    not parts
                    or Path(artifact_path).is_absolute()
                    or ".." in parts
                    or not STORE_BASENAME_RE.fullmatch(parts[0])
                ):
                    raise CheckError(
                        f"map line {line}: invalid artifact path {artifact_path!r}"
                    )
                expected_hash = artifact["sha256"]
                if expected_hash != "candidate" and not (
                    isinstance(expected_hash, str)
                    and HEX_SHA256_RE.fullmatch(expected_hash)
                ):
                    raise CheckError(
                        f"map line {line}: invalid artifact SHA-256 {expected_hash!r}"
                    )
                if artifact["elf_machine"] not in {"AArch64", None}:
                    raise CheckError(
                        f"map line {line}: invalid elf_machine {artifact['elf_machine']!r}"
                    )
            for test_id in arrays["test_id"]:
                if not isinstance(test_id, str) or Path(test_id).name != test_id:
                    raise CheckError(f"map line {line}: invalid test_id {test_id!r}")
            if not any(
                arrays[name]
                for name in (
                    "vendor_disable",
                    "target_config",
                    "target_dt",
                    "target_artifact",
                    "test_id",
                )
            ):
                raise CheckError(f"map line {line}: stub row {feature_id!r}")
            rows.append(
                MapRow(
                    feature_id=feature_id,
                    kind=kind,
                    vendor_evidence=arrays["vendor_evidence"],
                    provider=provider,
                    vendor_disable=arrays["vendor_disable"],
                    target_config=arrays["target_config"],
                    target_dt=arrays["target_dt"],
                    target_artifact=arrays["target_artifact"],
                    test_id=arrays["test_id"],
                    line=line,
                )
            )
    if not rows:
        raise CheckError("parity map has no rows")
    return rows


def parse_config(path: Path) -> dict[str, str]:
    require_regular(path, "kernel config")
    config: dict[str, str] = {}
    set_re = re.compile(r"^(CONFIG_[A-Z0-9_]+)=(.*)$")
    unset_re = re.compile(r"^# (CONFIG_[A-Z0-9_]+) is not set$")
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            stripped = line.rstrip("\n")
            match = set_re.fullmatch(stripped)
            if match:
                config[match.group(1)] = match.group(2)
                continue
            match = unset_re.fullmatch(stripped)
            if match:
                config[match.group(1)] = "n"
    return config


def fdt_children(blob: Path, node_path: str) -> list[str]:
    proc = run(["fdtget", "-l", str(blob), node_path], check=False)
    if proc.returncode:
        raise CheckError(
            f"cannot list FDT node {node_path} in {blob}: {proc.stderr.strip()}"
        )
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


def fdt_status(blob: Path, node_path: str) -> str | None:
    proc = run(["fdtget", "-t", "s", str(blob), node_path, "status"], check=False)
    if proc.returncode:
        return None
    return proc.stdout.strip()


def enumerate_fdt_nodes(blob: Path) -> dict[str, str | None]:
    nodes: dict[str, str | None] = {"/": fdt_status(blob, "/")}
    pending = ["/"]
    while pending:
        parent = pending.pop()
        for child in fdt_children(blob, parent):
            child_path = f"/{child}" if parent == "/" else f"{parent}/{child}"
            if child_path in nodes:
                raise CheckError(f"duplicate FDT path {child_path} in {blob}")
            nodes[child_path] = fdt_status(blob, child_path)
            pending.append(child_path)
    return nodes


def compile_vendor_dts(source_worktree: Path, tempdir: Path) -> Path:
    vendor_dts = source_worktree / "scripts/a733-vendor-reference.dts"
    require_regular(vendor_dts, "normalized vendor DTS")
    output = tempdir / "vendor-reference.dtb"
    proc = run(
        ["dtc", "-q", "-I", "dts", "-O", "dtb", "-o", str(output), str(vendor_dts)],
        check=False,
    )
    if proc.returncode:
        raise CheckError(f"normalized vendor DTS is unparseable: {proc.stderr.strip()}")
    return require_regular(output, "compiled normalized vendor DTS")


def validate_required_feature_set(rows: list[MapRow]) -> None:
    feature_ids = {row.feature_id for row in rows}
    missing = sorted(REQUIRED_EXACT_FEATURES - feature_ids)
    if missing:
        raise CheckError("map lacks required feature rows: " + ", ".join(missing))
    if not any(
        row.kind == "firmware" and "aic8800" in row.feature_id.lower()
        for row in rows
    ):
        raise CheckError("map lacks AIC8800 firmware coverage")
    if not any(
        row.kind == "firmware"
        and row.feature_id.lower().endswith((".nb", ".nbg"))
        for row in rows
    ):
        raise CheckError("map lacks NPU NBG firmware/model coverage")


def validate_unique_targets(rows: list[MapRow]) -> None:
    owners: dict[tuple[str, str], MapRow] = {}
    for row in rows:
        targets: list[tuple[str, str]] = []
        targets.extend(("config", value.split("=", 1)[0]) for value in row.target_config)
        targets.extend(
            ("dt", f"{value['blob']}:{value['path']}") for value in row.target_dt
        )
        targets.extend(("artifact", value["path"]) for value in row.target_artifact)
        for target in targets:
            previous = owners.get(target)
            if previous:
                raise CheckError(
                    f"double-provider target {target[1]!r}: "
                    f"{previous.feature_id}/{previous.provider} and "
                    f"{row.feature_id}/{row.provider}"
                )
            owners[target] = row


def validate_test_scripts(
    source_worktree: Path,
    rows: Iterable[MapRow],
    results: dict[str, ResultRow] | None,
) -> None:
    test_root = source_worktree / "scripts/a733-hw-tests"
    for row in rows:
        if not row_enforced(row, results):
            continue
        for test_id in row.test_id:
            script = resolve_relative_regular(test_root, test_id, "hardware test script")
            if not os.access(script, os.X_OK):
                raise CheckError(f"hardware test script is not executable: {script}")


def row_enforced(row: MapRow, results: dict[str, ResultRow] | None) -> bool:
    if results is None:
        return True
    return results[row.feature_id].status in {"pass", "not-applicable"}


def validate_config_coverage(
    rows: list[MapRow],
    reference: dict[str, str],
    target: dict[str, str],
    results: dict[str, ResultRow] | None,
) -> None:
    row_by_id = {row.feature_id: row for row in rows}
    expected = {
        f"config:{symbol}"
        for symbol, value in reference.items()
        if value in {"y", "m"} and target.get(symbol, "n") != value
    }
    missing = sorted(expected - row_by_id.keys())
    if missing:
        raise CheckError("unmapped vendor config differences: " + ", ".join(missing))
    for row in rows:
        if row.kind != "config":
            continue
        symbol = row.feature_id.split(":", 1)[1]
        if reference.get(symbol) not in {"y", "m"}:
            raise CheckError(
                f"map line {row.line}: {symbol} is not y/m in vendor reference config"
            )
        if not row_enforced(row, results):
            continue
        if not row.target_config:
            raise CheckError(f"config row {row.feature_id} has no target_config assertion")
        for assignment in row.target_config:
            match = CONFIG_RE.fullmatch(assignment)
            assert match
            actual = target.get(match.group(1), "n")
            if actual != match.group(2):
                raise CheckError(
                    f"{row.feature_id}: target config {match.group(1)}={actual}, "
                    f"expected {match.group(2)}"
                )
            if match.group(2) == "n" and not (
                row.target_dt or row.target_artifact or row.test_id
            ):
                raise CheckError(
                    f"{row.feature_id}: disabled vendor symbol has no replacement assertion"
                )


def parse_results(path: Path, rows: list[MapRow]) -> dict[str, ResultRow]:
    require_regular(path, "results TSV")
    parsed: dict[str, ResultRow] = {}
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle, delimiter="\t", lineterminator="\n")
        try:
            header = next(reader)
        except StopIteration as exc:
            raise CheckError("results TSV is empty") from exc
        if header != RESULTS_HEADER:
            raise CheckError(f"invalid results header: {header!r}")
        for line, fields in enumerate(reader, start=2):
            if len(fields) != len(RESULTS_HEADER):
                raise CheckError(f"results line {line}: invalid field count")
            feature_id, status, candidate_id, evidence_sha, evidence_path = fields
            if feature_id in parsed:
                raise CheckError(f"results line {line}: duplicate {feature_id}")
            if status not in RESULT_STATUSES:
                raise CheckError(f"results line {line}: invalid status {status!r}")
            if status == "pending":
                if candidate_id or evidence_sha or evidence_path:
                    raise CheckError(
                        f"results line {line}: pending row must have empty evidence columns"
                    )
            elif not (
                candidate_id and HEX_SHA256_RE.fullmatch(evidence_sha) and evidence_path
            ):
                raise CheckError(f"results line {line}: non-pending row lacks evidence")
            parsed[feature_id] = ResultRow(
                feature_id,
                status,
                candidate_id,
                evidence_sha,
                evidence_path,
                line,
            )
    expected = {row.feature_id for row in rows}
    if parsed.keys() != expected:
        missing = sorted(expected - parsed.keys())
        extra = sorted(parsed.keys() - expected)
        raise CheckError(f"results/map mismatch; missing={missing}, extra={extra}")
    return parsed


def parse_extlinux(path: Path) -> tuple[str, dict[str, list[str]]]:
    default: str | None = None
    blocks: dict[str, list[str]] = {}
    current: str | None = None
    with path.open(encoding="utf-8") as handle:
        for raw in handle:
            stripped = raw.strip()
            if not stripped or stripped.startswith("#"):
                continue
            key, _, value = stripped.partition(" ")
            key_upper = key.upper()
            value = value.strip()
            if key_upper == "DEFAULT":
                if default is not None:
                    raise CheckError("extlinux config has multiple DEFAULT directives")
                default = value
            elif key_upper == "LABEL":
                if not value or value in blocks:
                    raise CheckError(f"invalid or duplicate extlinux LABEL {value!r}")
                current = value
                blocks[current] = []
            elif current is not None:
                blocks[current].append(stripped)
    if default is None or default not in blocks:
        raise CheckError("extlinux DEFAULT does not name an existing LABEL")
    return default, blocks


def block_init_values(lines: list[str]) -> list[str]:
    values: list[str] = []
    for line in lines:
        if line.split(None, 1)[0].upper() != "APPEND":
            continue
        values.extend(re.findall(r"(?:^|\s)init=([^\s]+)", line))
    return values


def closure_paths(toplevel: Path) -> dict[str, Path]:
    proc = run(["nix-store", "-qR", str(toplevel)])
    closure: dict[str, Path] = {}
    for raw in proc.stdout.splitlines():
        store_path = Path(raw)
        if not store_path.is_absolute() or store_path.parent != Path("/nix/store"):
            raise CheckError(f"invalid closure store path: {raw!r}")
        if store_path.name in closure:
            raise CheckError(f"duplicate closure basename: {store_path.name}")
        closure[store_path.name] = store_path
    if toplevel.name not in closure:
        raise CheckError("toplevel is absent from its nix-store closure")
    return closure


def elf_machine(path: Path) -> str | None:
    with path.open("rb") as handle:
        if handle.read(4) != b"\x7fELF":
            return None
    proc = run(["readelf", "-h", str(path)])
    match = re.search(r"^\s*Machine:\s*(.+?)\s*$", proc.stdout, re.MULTILINE)
    if not match:
        raise CheckError(f"cannot determine ELF machine for {path}")
    machine = match.group(1)
    if machine != "AArch64":
        raise CheckError(f"unexpected ELF machine for {path}: {machine}")
    return machine


def resolve_artifact(
    artifact_path: str, closure: dict[str, Path]
) -> tuple[Path, str, str | None]:
    parts = Path(artifact_path).parts
    store_path = closure.get(parts[0])
    if store_path is None:
        raise CheckError(
            f"artifact first component is not in toplevel closure: {artifact_path}"
        )
    relative = Path(*parts[1:])
    path = resolve_relative_regular(store_path, str(relative), "candidate artifact")
    return path, sha256_file(path), elf_machine(path)


def validate_candidate_schema(candidate: dict[str, Any]) -> None:
    expected_keys = [
        "schema_version",
        "candidate_id",
        "source_sha",
        "source_tag",
        "source_hash",
        "nix_commit",
        "toplevel",
        "kernelrelease",
        "mainline_extlinux_label",
        "boot_config",
        "artifacts",
    ]
    if set(candidate) != set(expected_keys) or len(candidate) != len(expected_keys):
        raise CheckError(f"candidate.json keys do not match schema: {list(candidate)}")
    if candidate["schema_version"] != 1:
        raise CheckError("candidate schema_version must be 1")
    if not HEX_SHA256_RE.fullmatch(candidate["candidate_id"]):
        raise CheckError("invalid candidate_id")
    if not SOURCE_SHA_RE.fullmatch(candidate["source_sha"]):
        raise CheckError("invalid source_sha")
    if not isinstance(candidate["source_tag"], str) or not candidate["source_tag"]:
        raise CheckError("invalid source_tag")
    if not SRI_SHA256_RE.fullmatch(candidate["source_hash"]):
        raise CheckError("invalid source_hash")
    if not SOURCE_SHA_RE.fullmatch(candidate["nix_commit"]):
        raise CheckError("invalid nix_commit")
    if not isinstance(candidate["kernelrelease"], str) or not candidate["kernelrelease"]:
        raise CheckError("invalid kernelrelease")
    if not isinstance(candidate["mainline_extlinux_label"], str):
        raise CheckError("invalid mainline_extlinux_label")
    boot_config = candidate["boot_config"]
    if not isinstance(boot_config, dict) or set(boot_config) != {"path", "sha256"}:
        raise CheckError("invalid boot_config object")
    if not HEX_SHA256_RE.fullmatch(boot_config.get("sha256", "")):
        raise CheckError("invalid boot_config SHA-256")
    artifacts = candidate["artifacts"]
    if not isinstance(artifacts, list):
        raise CheckError("candidate artifacts must be an array")
    paths: list[str] = []
    for artifact in artifacts:
        if not isinstance(artifact, dict) or set(artifact) != {
            "path",
            "sha256",
            "elf_machine",
        }:
            raise CheckError(f"invalid candidate artifact object: {artifact!r}")
        if not HEX_SHA256_RE.fullmatch(artifact.get("sha256", "")):
            raise CheckError(f"invalid candidate artifact hash: {artifact!r}")
        if artifact.get("elf_machine") not in {"AArch64", None}:
            raise CheckError(f"invalid candidate ELF machine: {artifact!r}")
        paths.append(artifact.get("path", ""))
    if paths != sorted(set(paths)):
        raise CheckError("candidate artifacts must be uniquely sorted by path")


def git_clean_head(worktree: Path, what: str) -> str:
    status = run(["git", "status", "--porcelain"], cwd=worktree).stdout
    if status:
        raise CheckError(f"{what} worktree is not clean:\n{status}")
    return run(["git", "rev-parse", "HEAD"], cwd=worktree).stdout.strip()


def validate_candidate(
    candidate_path: Path,
    source_worktree: Path,
    nix_worktree: Path,
    rows: list[MapRow],
    results: dict[str, ResultRow],
) -> tuple[dict[str, Any], Path, dict[str, Path]]:
    require_regular(candidate_path, "candidate.json")
    try:
        candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise CheckError(f"invalid candidate JSON: {exc}") from exc
    if not isinstance(candidate, dict):
        raise CheckError("candidate.json must contain an object")
    validate_candidate_schema(candidate)
    candidate_dir = candidate_path.parent
    if candidate_dir.name != candidate["candidate_id"]:
        raise CheckError("candidate directory basename does not match candidate_id")
    source_head = git_clean_head(source_worktree, "source")
    nix_head = git_clean_head(nix_worktree, "Nix")
    if source_head != candidate["source_sha"]:
        raise CheckError("source worktree HEAD does not match candidate source_sha")
    if nix_head != candidate["nix_commit"]:
        raise CheckError("Nix worktree HEAD does not match candidate nix_commit")
    tag_sha = run(
        ["git", "rev-parse", f"{candidate['source_tag']}^{{commit}}"],
        cwd=source_worktree,
    ).stdout.strip()
    if tag_sha != source_head:
        raise CheckError("source tag does not resolve to candidate source_sha")
    toplevel = Path(candidate["toplevel"])
    if toplevel.parent != Path("/nix/store") or not toplevel.exists():
        raise CheckError(f"invalid or missing candidate toplevel: {toplevel}")
    computed_id = hashlib.sha256(
        f"{source_head}\n{nix_head}\n{toplevel}\n".encode()
    ).hexdigest()
    if computed_id != candidate["candidate_id"]:
        raise CheckError("candidate_id does not match source/Nix/toplevel identity")
    built = run(
        [
            "nix",
            "build",
            "--impure",
            "--no-link",
            "--print-out-paths",
            ".#nixosConfigurations.seldon-1.config.system.build.toplevel",
        ],
        cwd=nix_worktree,
    ).stdout.splitlines()
    if built != [str(toplevel)]:
        raise CheckError(f"current Nix build output differs from candidate: {built}")
    evaluated_source_hash = run(
        [
            "nix",
            "eval",
            "--impure",
            "--raw",
            ".#nixosConfigurations.seldon-1.config.boot.kernelPackages.kernel.src.outputHash",
        ],
        cwd=nix_worktree,
    ).stdout.strip()
    if evaluated_source_hash != candidate["source_hash"]:
        raise CheckError("current Nix kernel source hash differs from candidate")
    evaluated_kernelrelease = run(
        [
            "nix",
            "eval",
            "--impure",
            "--raw",
            ".#nixosConfigurations.seldon-1.config.boot.kernelPackages.kernel.modDirVersion",
        ],
        cwd=nix_worktree,
    ).stdout.strip()
    if evaluated_kernelrelease != candidate["kernelrelease"]:
        raise CheckError("current Nix kernelrelease differs from candidate")
    boot = resolve_relative_regular(
        candidate_dir, candidate["boot_config"]["path"], "boot config evidence"
    )
    if sha256_file(boot) != candidate["boot_config"]["sha256"]:
        raise CheckError("boot config evidence hash mismatch")
    default, blocks = parse_extlinux(boot)
    expected_vendor_init = f"{toplevel}/specialisation/a733-vendor-6.6/init"
    if block_init_values(blocks[default]) != [expected_vendor_init]:
        raise CheckError("extlinux DEFAULT is not the candidate vendor recovery")
    expected_mainline_init = f"{toplevel}/init"
    mainline_labels = [
        label
        for label, lines in blocks.items()
        if block_init_values(lines) == [expected_mainline_init]
    ]
    if mainline_labels != [candidate["mainline_extlinux_label"]]:
        raise CheckError("recorded mainline extlinux label is not unique or does not match")
    closure = closure_paths(toplevel)
    manifest_by_path = {artifact["path"]: artifact for artifact in candidate["artifacts"]}
    for artifact_path, manifest in manifest_by_path.items():
        path, digest, machine = resolve_artifact(artifact_path, closure)
        if digest != manifest["sha256"]:
            raise CheckError(f"candidate artifact hash mismatch: {path}")
        if machine != manifest["elf_machine"]:
            raise CheckError(f"candidate artifact ELF machine mismatch: {path}")
    for row in rows:
        if not row_enforced(row, results):
            continue
        for expected in row.target_artifact:
            manifest = manifest_by_path.get(expected["path"])
            if manifest is None:
                raise CheckError(
                    f"{row.feature_id}: target artifact absent from candidate manifest"
                )
            expected_hash = expected["sha256"]
            if expected_hash != "candidate" and manifest["sha256"] != expected_hash:
                raise CheckError(f"{row.feature_id}: fixed artifact hash mismatch")
            if manifest["elf_machine"] != expected["elf_machine"]:
                raise CheckError(f"{row.feature_id}: artifact ELF assertion mismatch")
    return candidate, candidate_dir, closure


def validate_results_evidence(
    rows: list[MapRow],
    results: dict[str, ResultRow],
    candidate: dict[str, Any],
    candidate_dir: Path,
    allow_pending: bool,
) -> None:
    nonfinal: list[str] = []
    rows_by_id = {row.feature_id: row for row in rows}
    for feature_id, result in results.items():
        if result.status in {"pending", "blocked"}:
            nonfinal.append(feature_id)
            continue
        if result.candidate_id != candidate["candidate_id"]:
            raise CheckError(f"{feature_id}: evidence candidate_id mismatch")
        evidence = resolve_relative_regular(
            candidate_dir, result.evidence_path, f"evidence for {feature_id}"
        )
        if sha256_file(evidence) != result.evidence_sha256:
            raise CheckError(f"{feature_id}: evidence hash mismatch")
        if result.status == "not-applicable" and not rows_by_id[feature_id].vendor_disable:
            raise CheckError(
                f"{feature_id}: not-applicable lacks vendor_disable/BOM evidence mapping"
            )
    if nonfinal and not allow_pending:
        raise CheckError(
            "final parity rejects pending/blocked rows: " + ", ".join(sorted(nonfinal))
        )
    if nonfinal:
        print(
            "NON_FINAL: pending/blocked rows allowed for subsystem milestone: "
            + ", ".join(sorted(nonfinal)),
            file=sys.stderr,
        )


def validate_dt(
    rows: list[MapRow],
    source_worktree: Path,
    base_dtb: Path,
    overlay_dir: Path | None,
    results: dict[str, ResultRow] | None,
) -> None:
    require_regular(base_dtb, "base DTB")
    with tempfile.TemporaryDirectory(prefix="a733-parity-") as raw_temp:
        tempdir = Path(raw_temp)
        vendor_blob = compile_vendor_dts(source_worktree, tempdir)
        vendor_nodes = enumerate_fdt_nodes(vendor_blob)
        vendor_okay = {
            f"node:{path}" for path, status in vendor_nodes.items() if status == "okay"
        }
        map_ids = {row.feature_id for row in rows}
        missing = sorted(vendor_okay - map_ids)
        if missing:
            raise CheckError("unmapped vendor okay DT nodes: " + ", ".join(missing))
        blob_cache: dict[str, Path] = {"base": base_dtb}
        base_nodes = enumerate_fdt_nodes(base_dtb)
        target_owners: dict[tuple[str, str], MapRow] = {}
        for row in rows:
            for assertion in row.target_dt:
                target_owners[(assertion["blob"], assertion["path"])] = row
                if not row_enforced(row, results):
                    continue
                blob_name = assertion["blob"]
                if blob_name not in blob_cache:
                    if overlay_dir is None:
                        raise CheckError(
                            f"{row.feature_id}: overlay assertion without --overlay-dir"
                        )
                    overlay = require_regular(
                        overlay_dir / blob_name, f"overlay {blob_name}"
                    )
                    composed = tempdir / f"composed-{blob_name}"
                    run(
                        [
                            "fdtoverlay",
                            "-i",
                            str(base_dtb),
                            "-o",
                            str(composed),
                            str(overlay),
                        ]
                    )
                    blob_cache[blob_name] = composed
                actual = fdt_status(blob_cache[blob_name], assertion["path"])
                if actual != assertion["status"]:
                    raise CheckError(
                        f"{row.feature_id}: {blob_name}:{assertion['path']} "
                        f"status={actual!r}, expected {assertion['status']!r}"
                    )
        if overlay_dir is not None and overlay_dir.exists():
            if overlay_dir.is_symlink() or not overlay_dir.is_dir():
                raise CheckError(f"invalid overlay directory: {overlay_dir}")
            base_available = {
                path for path, status in base_nodes.items() if status in {None, "okay"}
            }
            for overlay in sorted(overlay_dir.glob("*.dtbo")):
                require_regular(overlay, "compiled test overlay")
                composed = blob_cache.get(overlay.name)
                if composed is None:
                    composed = tempdir / f"coverage-{overlay.name}"
                    run(
                        [
                            "fdtoverlay",
                            "-i",
                            str(base_dtb),
                            "-o",
                            str(composed),
                            str(overlay),
                        ]
                    )
                nodes = enumerate_fdt_nodes(composed)
                enabled = {
                    path for path, status in nodes.items() if status in {None, "okay"}
                }
                changed = enabled - base_available
                changed |= {
                    path
                    for path in enabled & base_nodes.keys()
                    if base_nodes[path] not in {None, "okay"}
                }
                unmapped = sorted(
                    path
                    for path in changed
                    if (overlay.name, path) not in target_owners
                )
                if unmapped:
                    raise CheckError(
                        f"overlay {overlay.name} enables unmapped nodes: {unmapped}"
                    )


def validate_map_artifacts_without_candidate(rows: list[MapRow]) -> None:
    for row in rows:
        for artifact in row.target_artifact:
            if artifact["sha256"] == "candidate":
                continue
            if not HEX_SHA256_RE.fullmatch(artifact["sha256"]):
                raise CheckError(f"{row.feature_id}: malformed fixed artifact hash")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Strict Allwinner A733 vendor-to-mainline parity gate"
    )
    parser.add_argument("--map", required=True, type=Path)
    parser.add_argument("--source-worktree", required=True, type=Path)
    parser.add_argument("--nix-worktree", type=Path)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--dtb", required=True, type=Path)
    parser.add_argument("--overlay-dir", type=Path)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--results", type=Path)
    parser.add_argument("--allow-pending", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        source_worktree = args.source_worktree.resolve(strict=True)
        rows = parse_map(args.map)
        validate_required_feature_set(rows)
        validate_unique_targets(rows)
        candidate_requested = args.candidate is not None or args.results is not None
        if (args.candidate is None) != (args.results is None):
            raise CheckError("--candidate and --results must be supplied together")
        if candidate_requested and args.nix_worktree is None:
            raise CheckError("candidate validation requires --nix-worktree")
        results = parse_results(args.results, rows) if args.results else None
        validate_test_scripts(source_worktree, rows, results)
        reference = parse_config(
            source_worktree / "scripts/a733-vendor-reference.config"
        )
        target = parse_config(args.config)
        validate_config_coverage(rows, reference, target, results)
        validate_dt(
            rows,
            source_worktree,
            args.dtb,
            args.overlay_dir,
            results,
        )
        validate_map_artifacts_without_candidate(rows)
        if candidate_requested:
            assert args.candidate is not None
            assert args.results is not None
            assert args.nix_worktree is not None
            candidate, candidate_dir, _closure = validate_candidate(
                args.candidate,
                source_worktree,
                args.nix_worktree.resolve(strict=True),
                rows,
                results or {},
            )
            validate_results_evidence(
                rows,
                results or {},
                candidate,
                candidate_dir,
                args.allow_pending,
            )
        elif args.allow_pending:
            raise CheckError("--allow-pending is only valid with candidate/results")
    except (CheckError, OSError, ValueError) as exc:
        print(f"A733 parity check failed: {exc}", file=sys.stderr)
        return 1
    print("A733 parity check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
