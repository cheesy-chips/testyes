#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""
xnu-abi-diff.py -- what an old user space would find missing or changed in a newer XNU kernel.

The Galaxy S4 port (docs/s4-armv7-port.md) runs the user space of iOS 10.3 on a much newer kernel,
because Apple published no 32-bit ARM kernel source for iOS 10 (xnu-3789 has no ARM files at all).
The machine-independent half of the interface between the two is the table of BSD system calls and
the table of Mach traps. User space calls them by number, so a number that is gone or has changed
meaning in the newer kernel is a place where old user space breaks. This tool lists them.

It compares two trees (or any two directories that hold what it reads):

    bsd/kern/syscalls.master        the BSD system calls
    osfmk/mach/syscall_sw.h         the Mach traps
    osfmk/mach/*.defs               the MIG interfaces: the messages user space sends to the kernel's
                                    services (tasks, threads, ports, memory, hosts). A message's id is the
                                    subsystem's base number plus the routine's position, so what matters is
                                    that no routine has moved; one that Apple retired is a `skip`, which
                                    keeps the numbers. Needs clang (for -E); without it this part is skipped.

OLD is the kernel the user space was built with, NEW the kernel it will run on. Only what OLD has is
interesting: what NEW adds does not matter to code that was built without it.

A call counts as present when any #if branch of the master file has it; a call that NEW has only
behind an #if where OLD had it unconditionally is listed separately (vfork is one: xnu-8020 builds it
only with CONFIG_VFORK, which no configuration in the tree defines). Slots that answer ENOSYS (nosys,
enosys) are not calls.

The machine-dependent half (the commpage, the thread state, the timebase) is NOT covered; those files
differ per architecture and Apple did not publish 32-bit ARM ones before xnu-4570.

usage:  tools/xnu-abi-diff.py OLD NEW [--lp64] [--quiet] [--mig-define -DNAME=1 ...]
        --lp64    read the 64-bit variants of the Mach traps (the default is 32-bit, the S4's)
        --quiet   counts only, not the list of what changed
        --mig-define  a macro for clang -E on the .defs files (default -DPRIVATE=1 -DLIBSYSCALL_INTERFACE=1,
                  which is what the libsyscall build gives mig)

Exit status: 0 when the comparison ran (this is a report, not a gate).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys


def norm_name(n):
    """sys_close -> close: kernels rename things without changing the interface"""
    n = n.lstrip('_')
    if n.startswith('sys_'):
        n = n[4:]
    return n


def norm_sig(ret, args):
    """the signature without the parameter names: 'int(int,user_addr_t,int)'"""
    types = []
    for a in (x.strip() for x in args.split(',')):
        if not a or a == 'void':
            continue
        if re.search(r'[\s*]\w+(\[\d*\])?$', a):            # drop the parameter's name, keep its type
            a = re.sub(r'\s*\b[A-Za-z_]\w*(\[\d*\])?$', '', a)
        types.append(re.sub(r'\s+', ' ', a.replace(' *', '*')))
    return re.sub(r'\s+', ' ', ret.strip()) + '(' + ','.join(types) + ')'


def read_syscalls(path):
    """{number: (name, signature, condition)} for the calls in syscalls.master.

    condition is the #if expression of the branch the entry is in ('' for none, and for #else
    branches): it says "only built when ...". When both branches of an #if/#else have a line for
    one number, the one that is a real call wins over the nosys/enosys placeholder."""
    out = {}
    stack = []                                              # [expression, in_else] per open #if
    for line in open(path, encoding='utf-8', errors='replace'):
        s = line.strip()
        m = re.match(r'#\s*(ifdef|ifndef|if|elif|else|endif)\b(.*)', s)
        if m:
            kw, rest = m.group(1), re.sub(r'/\*.*?\*/', '', m.group(2)).strip()
            if kw in ('if', 'ifdef', 'ifndef'):
                stack.append([('!' if kw == 'ifndef' else '') + rest, False])
            elif kw == 'elif' and stack:
                stack[-1] = ['', True]
            elif kw == 'else' and stack:
                stack[-1][1] = True
            elif kw == 'endif' and stack:
                stack.pop()
            continue
        m = re.match(r'(\d+)\s+\S+\s+\S+\s+\{\s*(.+?)\s+(\w+)\s*\((.*?)\)', line)
        if not m:
            continue
        num, ret, name, args = int(m.group(1)), m.group(2), m.group(3), m.group(4)
        if name in ('nosys', 'enosys'):
            continue                                        # retired, or never used: the slot answers ENOSYS
        cond = ' && '.join(e for e, in_else in stack if e and not in_else)
        out[num] = (norm_name(name), norm_sig(ret, args), cond)
    return out


def read_traps(path, lp64):
    """{number: (name, argument count, '')} from kernel_trap(name, number, args), #if defined(__LP64__) resolved"""
    out = {}
    stack = []                                              # one flag per open #if: is its active branch the one we read?
    for line in open(path, encoding='utf-8', errors='replace'):
        s = line.strip()
        m = re.match(r'#\s*(if|ifdef|ifndef|else|endif)\b(.*)', s)
        if m:
            kw, rest = m.group(1), m.group(2)
            if kw in ('if', 'ifdef', 'ifndef'):
                if '__LP64__' in rest:
                    stack.append(lp64 != (kw == 'ifndef' or rest.lstrip().startswith('!')))
                else:
                    stack.append(True)                      # PRIVATE, the include guard: always on
            elif kw == 'else' and stack:
                stack[-1] = not stack[-1]
            elif kw == 'endif' and stack:
                stack.pop()
            continue
        if not all(stack):
            continue
        m = re.match(r'kernel_trap\(\s*(\w+)\s*,\s*(-?\d+)\s*,\s*(\d+)\s*\)', s)
        if m:
            out[int(m.group(2))] = (norm_name(m.group(1)), int(m.group(3)), '')
    return out


def compare(old, new, label, show):
    """print one table's verdicts"""
    new_by_name = {}
    for n, (name, _, _) in new.items():
        new_by_name.setdefault(name, []).append(n)
    same, changed_args, renamed, moved, gone = [], [], [], [], []
    for n in sorted(old):
        name, sig, _ = old[n]
        if n in new and new[n][0] == name:
            (same if new[n][1] == sig else changed_args).append(n)
        elif name in new_by_name:
            moved.append(n)                                 # the call exists, under another number
        elif n in new:
            renamed.append(n)                               # the number now means something else
        else:
            gone.append(n)
    behind_if = [n for n in same + changed_args if new[n][2] and new[n][2] != old[n][2]]
    print(f'{label}: {len(old)} in OLD, {len(new)} in NEW; of OLD\'s:')
    print(f'  {len(same):4d}  same number, same name, same arguments')
    for what, lst in (('same number and name, arguments differ', changed_args),
                      ('same name at another number', moved),
                      ('number now means a different call', renamed),
                      ('gone from NEW', gone)):
        print(f'  {len(lst):4d}  {what}')
    print(f'  {len(behind_if):4d}  (of the first two groups: built in NEW only behind an #if that OLD did not have)')
    if not show:
        return
    for title, lst in (('arguments differ', changed_args), ('another number', moved),
                       ('different call', renamed), ('gone', gone)):
        for n in lst:
            nm = old[n][0]
            if title == 'arguments differ':
                detail = f'{old[n][1]}  ->  {new[n][1]}' if isinstance(old[n][1], str) else f'{old[n][1]} -> {new[n][1]}'
            elif title == 'another number':
                detail = 'now at ' + ', '.join(str(k) for k in new_by_name[nm])
            elif title == 'different call':
                detail = 'now ' + new[n][0]
            else:
                detail = ''
            print(f'        {n:5d} {nm:40s} {title}{(": " + detail) if detail else ""}')
    for n in behind_if:
        print(f'        {n:5d} {old[n][0]:40s} only under #if {new[n][2]}')


def mig_routines(tree, rel, defines):
    """(subsystem, {id: name}) of one .defs file after clang -E; a `skip` statement is named '<skip>'"""
    cmd = [shutil.which('clang'), '-E', '-P', '-x', 'c', '-nostdinc', '-I', os.path.join(tree, 'osfmk'),
           '-I', os.path.join(tree, 'osfmk', 'mach'), '-I', tree] + defines + [os.path.join(tree, rel)]
    text = subprocess.run(cmd, capture_output=True, text=True).stdout
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    stmts, cur, depth = [], [], 0
    for ch in text:                         # statements end at a ';' outside parentheses (inside, ';' separates arguments)
        depth += (ch == '(') - (ch == ')')
        if ch == ';' and depth == 0:
            stmts.append(''.join(cur))
            cur = []
        else:
            cur.append(ch)
    sub, base, idx, out = None, 0, 0, {}
    for st in stmts:
        st = ' '.join(st.split())
        m = re.match(r'subsystem\s+(?:\w+\s+)*?(\w+)\s+(\d+)$', st)
        if m and sub is None:
            sub, base = m.group(1), int(m.group(2))
        elif sub and re.match(r'(routine|simpleroutine)\s+\w+', st):
            out[base + idx] = re.match(r'\w+\s+(\w+)', st).group(1)
            idx += 1
        elif sub and st == 'skip':
            out[base + idx] = '<skip>'
            idx += 1
    return sub, out


def mig_files(tree):
    """the .defs files that the tree's own osfmk/mach/Makefile builds (MIG_DEFS and the two private
    lists); every .defs in the directory when there is no such Makefile. Some releases keep a stale
    .defs next to the live ones (xnu-3789 has a sync.defs that nothing builds)."""
    d = os.path.join(tree, 'osfmk', 'mach')
    if not os.path.isdir(d):
        return []
    listed = []
    mk = os.path.join(d, 'Makefile')
    if os.path.isfile(mk):
        text = open(mk, encoding='utf-8', errors='replace').read().replace('\\\n', ' ')
        for m in re.finditer(r'(?m)^(MIG_DEFS|MIG_PRIVATE_DEFS|MACH_PRIVATE_DEFS)\s*[:+]?=(.*)$', text):
            listed += [t for t in m.group(2).split() if t.endswith('.defs')]
    if not listed:
        listed = [f for f in os.listdir(d) if f.endswith('.defs')]
    return sorted({f for f in listed if os.path.isfile(os.path.join(d, f))})


def read_mig(tree, defines):
    """{(subsystem, id): name} for the .defs files of osfmk/mach that the tree builds"""
    out = {}
    for f in mig_files(tree):
        sub, routines = mig_routines(tree, 'osfmk/mach/' + f, defines)
        for i, n in routines.items():
            out[(sub, i)] = n
    return out


def compare_mig(old_tree, new_tree, defines, show):
    if not shutil.which('clang'):
        print('MIG interfaces: skipped (needs clang to preprocess the .defs files)')
        return
    old, new = read_mig(old_tree, defines), read_mig(new_tree, defines)
    if not old:
        print('MIG interfaces: skipped (no osfmk/mach/*.defs in OLD)')
        return
    new_names = {}
    for (sub, i), n in new.items():
        new_names.setdefault((sub, n), []).append(i)
    named = {k: n for k, n in old.items() if n != '<skip>'}
    same, retired, moved, other, gone = [], [], [], [], []
    for (sub, i), n in sorted(named.items()):
        there = new.get((sub, i))
        if there == n:
            same.append((sub, i))
        elif there == '<skip>':
            retired.append((sub, i))
        elif (sub, n) in new_names:
            moved.append((sub, i))
        elif there is not None:
            other.append((sub, i))
        else:
            gone.append((sub, i))
    print(f'MIG interfaces: {len({k[0] for k in old})} subsystems, {len(named)} routines in OLD; of those:')
    print(f'  {len(same):4d}  same id, same name')
    for what, lst in (('retired: the id is kept, as a skip', retired), ('same name at another id', moved),
                      ('id now means a different routine', other), ('gone from NEW', gone)):
        print(f'  {len(lst):4d}  {what}')
    if show:
        for what, lst in (('retired', retired), ('another id', moved), ('different routine', other), ('gone', gone)):
            for sub, i in lst:
                extra = ''
                if what == 'another id':
                    extra = ': now at ' + ', '.join(str(k) for k in new_names[(sub, named[(sub, i)])])
                elif what == 'different routine':
                    extra = ': now ' + new[(sub, i)]
                print(f'        {i:7d} {sub + "." + named[(sub, i)]:44s} {what}{extra}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('old')
    ap.add_argument('new')
    ap.add_argument('--lp64', action='store_true')
    ap.add_argument('--quiet', action='store_true')
    ap.add_argument('--mig-define', action='append', default=None, metavar='-DNAME=1')
    a = ap.parse_args()
    defines = a.mig_define if a.mig_define else ['-DPRIVATE=1', '-DLIBSYSCALL_INTERFACE=1']

    files = {}
    for side, d in (('old', a.old), ('new', a.new)):
        for key, rel in (('sys', 'bsd/kern/syscalls.master'), ('trap', 'osfmk/mach/syscall_sw.h')):
            p = os.path.join(d, rel)
            if not os.path.isfile(p):
                sys.exit(f'xnu-abi-diff: {p} not found (is {d} an XNU tree?)')
            files[side, key] = p
    print(f'OLD: {a.old}\nNEW: {a.new}\n')
    compare(read_syscalls(files['old', 'sys']), read_syscalls(files['new', 'sys']), 'BSD system calls', not a.quiet)
    print()
    compare(read_traps(files['old', 'trap'], a.lp64), read_traps(files['new', 'trap'], a.lp64),
            'Mach traps (' + ('64' if a.lp64 else '32') + '-bit)', not a.quiet)
    print()
    compare_mig(a.old, a.new, defines, not a.quiet)


if __name__ == '__main__':
    main()
