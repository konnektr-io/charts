#!/usr/bin/env python3
"""
bump-chart.py — bump Konnektr Helm chart versions in konnektr-io/charts.

Why this exists
---------------
Releasing a new app version means editing the right field in the right file.
The charts are inconsistent about where the deployed image tag comes from:

  graph / ktrlplane / db-query-operator
      image tag is derived from Chart.yaml `appVersion` (values.yaml tag is "").
      -> bump `appVersion` (+ chart `version`) in Chart.yaml.

  porkbun-webhook (dir: cert-manager-porkbun-webhook)
      image tag is HARD-CODED in values.yaml as `image.tag` (appVersion is cosmetic).
      -> bump `image.tag` in values.yaml (+ chart `version` in Chart.yaml).

Sub-chart dependencies (e.g. ktrlplane -> db-query-operator) are bumped under
`dependencies` in the parent Chart.yaml.

Usage
-----
  # app-version bump (graph / ktrlplane / db-query-operator)
  python3 scripts/bump-chart.py graph --app-version 1.27.0 [--chart-version 0.14.1] [--push]

  # bump a sub-chart dependency (e.g. after a db-query-operator release)
  python3 scripts/bump-chart.py ktrlplane --dep db-query-operator=0.10.2 [--push]

  # porkbun-webhook image tag (the real release lever for that chart)
  python3 scripts/bump-chart.py porkbun-webhook --image-tag v0.1.6 [--push]

  # combine
  python3 scripts/bump-chart.py ktrlplane --app-version 0.3.11 --dep db-query-operator=0.10.2 --push

Flags
-----
  --app-version X     set Chart.yaml appVersion (auto-bumps chart version patch if --chart-version omitted)
  --chart-version X   set Chart.yaml version explicitly (skips auto-bump)
  --image-tag X       set values.yaml image.tag (porkbun-webhook only)
  --dep name=ver ...  bump one or more dependency versions in Chart.yaml
  --dry-run           print the diff, do not write files
  --push              git add + commit + push to main (requires current branch == main)
"""
import os
import re
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR_MAP = {"porkbun-webhook": "cert-manager-porkbun-webhook"}
IMAGE_TAG_CHARTS = {"cert-manager-porkbun-webhook"}  # image tag lives in values.yaml

# ---------------------------------------------------------------------------
# YAML line editing (no PyYAML dependency; targets specific keys only)
# ---------------------------------------------------------------------------

def replace_scalar(line: str, new_value: str) -> str:
    """Replace the scalar value on a `key: value` line, preserving quote style."""
    m = re.match(r'^(\s*[\w.\-]+\s*:\s*)(["\']?)(.*?)(["\']?)\s*$', line)
    if not m:
        return line
    prefix, q1, _old, q2 = m.groups()
    quote = q1 if q1 else ""  # keep original quoting (or none)
    return f"{prefix}{quote}{new_value}{quote}"


def set_top_level(lines, key, value):
    """Set a top-level (column-0) `key:` in Chart.yaml. Returns True if changed."""
    changed = False
    pat = re.compile(r'^' + re.escape(key) + r'\s*:\s*')
    for i, line in enumerate(lines):
        if pat.match(line):
            new_line = replace_scalar(line, value)
            if new_line != line:
                lines[i] = new_line
                changed = True
            break  # only the first (top-level) occurrence
    return changed


def bump_patch(version: str) -> str:
    """Increment the last numeric segment: 0.14.0 -> 0.14.1, 0.1.5 -> 0.1.6."""
    parts = version.split(".")
    if not parts or not parts[-1].isdigit():
        # can't auto-bump non-numeric tail; leave as-is and let caller notice
        return version
    parts[-1] = str(int(parts[-1]) + 1)
    return ".".join(parts)


def set_dep_version(lines, dep_name, value):
    """Set `version:` inside the `- name: <dep_name>` entry under `dependencies:`."""
    in_deps = False
    i = 0
    while i < len(lines):
        line = lines[i]
        if re.match(r'^dependencies:', line):
            in_deps = True
            i += 1
            continue
        if in_deps:
            # deps block ends at the next non-indented, non-list line
            if line[:1] not in ("", " ", "-") and not line.startswith(" "):
                in_deps = False
                i += 1
                continue
            m = re.match(r'^(\s*)-\s*name:\s*(\S+)', line)
            if m and m.group(2) == dep_name:
                base_indent = len(line) - len(line.lstrip())
                j = i + 1
                while j < len(lines):
                    l2 = lines[j]
                    if not l2.strip():
                        j += 1
                        continue
                    ind = len(l2) - len(l2.lstrip())
                    if ind <= base_indent:
                        break
                    vm = re.match(r'^(\s*)version:\s*', l2)
                    if vm:
                        new_line = replace_scalar(l2, value)
                        if new_line != l2:
                            lines[j] = new_line
                            return True
                        return True
                    j += 1
        i += 1
    return False


def set_image_tag(lines, value):
    """Set `tag:` inside the `image:` block of values.yaml."""
    in_image = False
    base_indent = None
    for idx, line in enumerate(lines):
        m = re.match(r'^(\s*)image:\s*$', line)
        if m:
            in_image = True
            base_indent = len(line) - len(line.lstrip())
            continue
        if in_image:
            if not line.strip():
                continue
            ind = len(line) - len(line.lstrip())
            if ind <= base_indent:
                in_image = False
                continue
            tm = re.match(r'^(\s*)tag:\s*', line)
            if tm:
                new_line = replace_scalar(line, value)
                if new_line != line:
                    lines[idx] = new_line
                    return True
                return True
    return False


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def read_text(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write_text(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def git(*args, check=True):
    return subprocess.run(["git", *args], cwd=REPO_ROOT, check=check,
                          capture_output=True, text=True)


def current_branch():
    return git("rev-parse", "--abbrev-ref", "HEAD").stdout.strip()


def main(argv):
    import argparse
    p = argparse.ArgumentParser(description="Bump a Konnektr Helm chart version.")
    p.add_argument("chart", help="chart directory name (e.g. graph, ktrlplane, porkbun-webhook)")
    p.add_argument("--app-version", help="new Chart.yaml appVersion")
    p.add_argument("--chart-version", help="explicit Chart.yaml version (skip auto-bump)")
    p.add_argument("--image-tag", help="new values.yaml image.tag (porkbun-webhook)")
    p.add_argument("--dep", action="append", default=[], metavar="name=version",
                   help="bump a dependency version (repeatable)")
    p.add_argument("--dry-run", action="store_true", help="print diff, do not write")
    p.add_argument("--push", action="store_true", help="commit + push to main (needs branch=main)")
    args = p.parse_args(argv)

    # resolve chart dir
    chart_dir = DIR_MAP.get(args.chart, args.chart)
    chart_path = os.path.join(REPO_ROOT, chart_dir)
    if not os.path.isdir(chart_path):
        sys.exit(f"error: no chart directory '{chart_dir}' in {REPO_ROOT}")
    chart_yaml = os.path.join(chart_path, "Chart.yaml")
    values_yaml = os.path.join(chart_path, "values.yaml")
    if not os.path.isfile(chart_yaml):
        sys.exit(f"error: {chart_yaml} not found")

    deps = []
    for d in args.dep:
        if "=" not in d:
            sys.exit(f"error: --dep must be name=version, got '{d}'")
        deps.append((d.split("=", 1)[0], d.split("=", 1)[1]))

    # Load
    chart_lines = read_text(chart_yaml).splitlines()
    values_lines = read_text(values_yaml).splitlines() if os.path.isfile(values_yaml) else None

    changes = []  # (file, label, old, new)
    is_image_tag_chart = chart_dir in IMAGE_TAG_CHARTS

    # --- image tag (porkbun-webhook) ---
    if args.image_tag:
        if not is_image_tag_chart:
            sys.exit(f"error: --image-tag only applies to {sorted(IMAGE_TAG_CHARTS)}")
        if values_lines is None:
            sys.exit(f"error: {values_yaml} not found")
        # capture old tag for the message
        old_tag = next((l for l in values_lines if re.match(r'^\s*tag:\s*', l)), "")
        if not set_image_tag(values_lines, args.image_tag):
            sys.exit("error: could not find image.tag in values.yaml")
        changes.append((values_yaml, "image.tag", old_tag.strip(), f"tag: {args.image_tag}"))

    # --- appVersion ---
    if args.app_version:
        if is_image_tag_chart:
            sys.exit("error: porkbun-webhook derives nothing from appVersion; use --image-tag")
        old_av = next((l for l in chart_lines if re.match(r'^appVersion:', l)), "")
        if not set_top_level(chart_lines, "appVersion", args.app_version):
            sys.exit("error: could not set appVersion")
        changes.append((chart_yaml, "appVersion", old_av.strip(), f"appVersion: {args.app_version}"))

    # --- chart version (explicit or auto-bump patch) ---
    if args.chart_version:
        target_cv = args.chart_version
    elif args.app_version or args.image_tag or deps:
        old_cv_line = next((l for l in chart_lines if re.match(r'^version:', l)), "version: 0")
        old_cv = old_cv_line.split(":", 1)[1].strip().strip('"').strip("'")
        target_cv = bump_patch(old_cv)
    else:
        target_cv = None

    if target_cv:
        old_cv_line = next((l for l in chart_lines if re.match(r'^version:', l)), "")
        if set_top_level(chart_lines, "version", target_cv):
            changes.append((chart_yaml, "version", old_cv_line.strip(), f"version: {target_cv}"))

    # --- dependencies ---
    for dep_name, dep_ver in deps:
        if not set_dep_version(chart_lines, dep_name, dep_ver):
            sys.exit(f"error: dependency '{dep_name}' not found under dependencies:")

    if not changes and not deps:
        sys.exit("error: nothing to do — pass --app-version, --image-tag, or --dep")

    # --- assemble new file contents ---
    new_chart_text = "\n".join(chart_lines) + "\n"
    old_values_text = read_text(values_yaml) if values_lines is not None else ""
    new_values_text = ("\n".join(values_lines) + "\n") if values_lines is not None else ""
    values_changed = (new_values_text != old_values_text)

    # --- preview / dry-run ---
    if args.dry_run or not args.push:
        import difflib
        def show_diff(path, old, new):
            diff = list(difflib.unified_diff(
                old.splitlines(), new.splitlines(),
                fromfile=f"a/{os.path.relpath(path, REPO_ROOT)}",
                tofile=f"b/{os.path.relpath(path, REPO_ROOT)}", lineterm=""))
            if diff:
                print("\n".join(diff))
        print("=== preview (no files written) ===")
        show_diff(chart_yaml, read_text(chart_yaml), new_chart_text)
        if values_changed:
            show_diff(values_yaml, old_values_text, new_values_text)
        print("=== end preview ===")

    # --- write files ---
    if not args.dry_run:
        write_text(chart_yaml, new_chart_text)
        written = [os.path.relpath(chart_yaml, REPO_ROOT)]
        if values_changed:
            write_text(values_yaml, new_values_text)
            written.append(os.path.relpath(values_yaml, REPO_ROOT))
        print(f"updated: {', '.join(written)}")

    # --- commit + push ---
    if args.push:
        if args.dry_run:
            sys.exit("error: --push with --dry-run is contradictory")
        branch = current_branch()
        if branch != "main":
            sys.exit(f"error: --push requires branch 'main' (currently on '{branch}'). "
                     f"Version bumps go straight to main; template changes need a PR.")
        msg_parts = [f"bump {args.chart}"]
        if args.app_version:
            msg_parts.append(f"appVersion {args.app_version}")
        if args.image_tag:
            msg_parts.append(f"image {args.image_tag}")
        for dn, dv in deps:
            msg_parts.append(f"dep {dn} {dv}")
        if target_cv:
            msg_parts.append(f"chart {target_cv}")
        msg = "; ".join(msg_parts)
        git("add", "-A")
        git("commit", "-m", msg)
        git("push", "origin", "main")
        print(f"committed + pushed to main: {msg}")


if __name__ == "__main__":
    main(sys.argv[1:])
