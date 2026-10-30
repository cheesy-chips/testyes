#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""
xnu-port-check.py -- how much of xnu/hakios.patch carries over to another XNU tree.

The kernel patch (xnu/hakios.patch) is written against Apple's tag xnu-8796.121.2. Before a port
to a different release is started (the Galaxy S4 needs one with 32-bit ARM code, see
docs/s4-armv7-port.md) this tool measures the distance: for every file in the patch it asks
GNU patch, in dry-run mode, whether the hunks still fit, and it sorts the files that xnu/files/
adds into the part of the kernel they belong to.

It changes nothing: `patch --dry-run` writes no file, and the tree is only read.

usage:  tools/xnu-port-check.py TREE [--patch xnu/hakios.patch] [--files xnu/files] [--list]
        TREE   a checkout of the release to test (git fetch --depth 1 origin refs/tags/TAG; git checkout TAG)
        --list print every file that does not apply cleanly, not only the counts

Exit status: 0 always when the measurement ran (this is a report, not a gate).
"""
import argparse
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.dirname(HERE)


def split_patch(text):
    """[(path, chunk_text, is_new_file)] -- one entry per `diff --git` of the patch."""
    parts = re.split(r'(?m)^(?=diff --git )', text)
    out = []
    for p in parts:
        m = re.match(r'diff --git a/(\S+) b/(\S+)', p)
        if not m:
            continue
        out.append((m.group(2), p, bool(re.search(r'(?m)^new file mode', p))))
    return out


def dry_run(tree, path, chunk):
    """Ask GNU patch, dry run, whether one file's hunks fit. None: the file is not in that tree.
    Otherwise (hunks, failed, fuzzed, shifted). --batch: never ask a question, never assume a
    patch is reversed, so on a tree that already has our changes the hunks simply fail."""
    if not os.path.exists(os.path.join(tree, path)):
        return None
    r = subprocess.run(
        ['patch', '-p1', '--dry-run', '--batch', '--no-backup-if-mismatch', '-d', tree],
        input=chunk, capture_output=True, text=True)
    out = r.stdout + r.stderr
    hunks = len(re.findall(r'(?m)^@@ ', chunk))
    failed = len(re.findall(r'(?m)^Hunk #\d+ FAILED', out))
    fuzzed = len(re.findall(r'(?m)^Hunk #\d+ succeeded at \d+ with fuzz', out))
    shifted = len(re.findall(r'(?m)^Hunk #\d+ succeeded at \d+ \(offsets? ', out))
    if r.returncode != 0 and failed == 0 and hunks:
        failed = hunks          # patch refused the file for a reason it did not report per hunk
    return (hunks, failed, fuzzed, shifted)


def area(path):
    """The part of the kernel a path belongs to, for the summary."""
    for pre, name in (
        ('osfmk/arm64/', 'osfmk/arm64 (64-bit platform)'),
        ('osfmk/arm/', 'osfmk/arm (32-bit/common ARM)'),
        ('pexpert/', 'pexpert (platform expert)'),
        ('osfmk/', 'osfmk (Mach)'),
        ('bsd/dev/', 'bsd/dev (drivers)'),
        ('bsd/miscfs/', 'bsd/miscfs (file systems)'),
        ('bsd/', 'bsd (BSD layer)'),
        ('iokit/', 'iokit'),
        ('libkern/', 'libkern'),
        ('security/', 'security (MAC)'),
        ('makedefs/', 'build system'),
        ('config/', 'build system'),
        ('tools/', 'tools'),
    ):
        if path.startswith(pre):
            return name
    return 'other'


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('tree')
    ap.add_argument('--patch', default=os.path.join(TOP, 'xnu', 'hakios.patch'))
    ap.add_argument('--files', default=os.path.join(TOP, 'xnu', 'files'))
    ap.add_argument('--list', action='store_true')
    a = ap.parse_args()

    tree = os.path.abspath(a.tree)
    if not os.path.isdir(os.path.join(tree, 'osfmk')):
        sys.exit(f'xnu-port-check: {tree} does not look like an XNU tree (no osfmk/)')
    text = open(a.patch, encoding='utf-8', errors='replace').read()
    entries = split_patch(text)
    if not entries:
        sys.exit(f'xnu-port-check: no "diff --git" in {a.patch}')

    status = {}            # path -> 'clean' | 'offset' | 'fuzz' | 'partial' | 'failed' | 'missing' | 'new-conflict' | 'new'
    by_area = defaultdict(Counter)
    hunks_total = hunks_failed = 0
    for path, chunk, is_new in entries:
        if is_new:
            st = 'new-conflict' if os.path.exists(os.path.join(tree, path)) else 'new'
        else:
            res = dry_run(tree, path, chunk)
            if res is None:
                st = 'missing'
            else:
                h, f, fz, off = res
                hunks_total += h
                hunks_failed += f
                if f and f >= h:
                    st = 'failed'
                elif f:
                    st = 'partial'
                elif fz:
                    st = 'fuzz'
                elif off:
                    st = 'offset'
                else:
                    st = 'clean'
        status[path] = st
        by_area[area(path)][st] += 1

    c = Counter(status.values())
    n = len(entries)
    ok = c['clean'] + c['offset'] + c['fuzz'] + c['new']
    print(f'tree:   {tree}')
    print(f'patch:  {os.path.relpath(a.patch, TOP)}: {n} files')
    print()
    print(f'  apply cleanly (exact or shifted lines)   {c["clean"] + c["offset"]:4d}')
    print(f'  apply with fuzz (check by hand)          {c["fuzz"]:4d}')
    print(f'  new files that fit                       {c["new"]:4d}')
    print(f'  some hunks fail                          {c["partial"]:4d}')
    print(f'  every hunk fails                         {c["failed"]:4d}')
    print(f'  file is not in that release              {c["missing"]:4d}')
    print(f'  new file, but the path exists there      {c["new-conflict"]:4d}')
    print(f'  => {ok} of {n} files go in ({100 * ok // n}%); hunks that fail: {hunks_failed} of {hunks_total}')
    print()
    print('by part of the kernel (ok / needs work):')
    for ar in sorted(by_area):
        cc = by_area[ar]
        good = cc['clean'] + cc['offset'] + cc['fuzz'] + cc['new']
        print(f'  {ar:34s} {good:3d} / {sum(cc.values()) - good:3d}')
    if a.list:
        print()
        print('files that need work:')
        for p in sorted(status):
            if status[p] not in ('clean', 'offset', 'fuzz', 'new'):
                print(f'  {status[p]:12s} {p}')

    # what xnu/files/ adds, by part of the kernel. These are copied over the tree (xnu/apply.sh does
    # `cp -a files/. .`), so a path that already exists in the release is an Apple file that would be
    # overwritten; the rest cannot conflict, but may still not compile against another release.
    if os.path.isdir(a.files):
        kinds = Counter()
        overwrites = []
        for root, _, names in os.walk(a.files):
            for nm in names:
                rel = os.path.relpath(os.path.join(root, nm), a.files)
                if os.path.exists(os.path.join(tree, rel)):
                    overwrites.append(rel)
                if rel.startswith('osfmk/arm64/') or rel.startswith('pexpert/arm64'):
                    kinds['64-bit platform (osfmk/arm64, pexpert/arm64)'] += 1
                elif '/apfs/' in rel:
                    kinds['APFS reader (bsd/miscfs/apfs)'] += 1
                elif re.search(r'(^|/)hakios\.[a-z0-9_]+\.(c|h|cpp)$', rel) and rel.startswith(('bsd/dev/', 'iokit/Kernel/', 'bsd/sys/')):
                    kinds['drivers and glue named hakios.* (mostly POCO X5 Pro hardware)'] += 1
                else:
                    kinds['other (AMFI stubs, ramfs, minicrypto, IOKit replacements, ...)'] += 1
        print()
        print(f'new files in {os.path.relpath(a.files, TOP)}: {sum(kinds.values())}; '
              f'paths that already exist in this release (would be overwritten): {len(overwrites)}')
        for k, v in kinds.most_common():
            print(f'  {v:4d}  {k}')
        if a.list and overwrites:
            print()
            print('Apple files that xnu/files/ would overwrite:')
            for o in sorted(overwrites):
                print(f'  {o}')


if __name__ == '__main__':
    main()
