#!/usr/bin/env python3
"""Fail closed on private files and commit metadata, without printing their values."""
import argparse
import pathlib
import re
import subprocess
import sys

EMAIL = re.compile(rb'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
NOREPLY = re.compile(rb'(?:(?:[0-9]+\+)?[A-Za-z0-9-]+@users\.noreply\.github\.com|noreply@github\.com)')
PATTERNS = {
    'private key': rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'credential': rb'(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-(?:proj-)?[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16})',
    'home directory': rb'/' + rb'Users/[^/\s]+/',
    'device identifier': rb'\b[0-9A-F]{8}-[0-9A-F]{16}\b',
    'assigned team': rb'DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}\b',
}
PRIVATE_SUFFIXES = {'.p12', '.p8', '.pem', '.mobileprovision', '.key', '.pfx', '.ipa', '.xcarchive', '.xcappdata'}
issues = set()


def git(*args):
    return subprocess.check_output(['git', *args], stderr=subprocess.PIPE)


def report(location, reason):
    issues.add((location, reason))


def check_identity(data, location):
    match = re.search(rb'<([^<>]+)>', data)
    if not match or not NOREPLY.fullmatch(match[1]):
        report(location, 'author/committer/tagger must use a GitHub no-reply address')


def check_text(data, location, metadata=False):
    for label, pattern in PATTERNS.items():
        if re.search(pattern, data):
            report(location, label)
    for address in EMAIL.findall(data):
        domain = address.rsplit(b'@', 1)[1].lower()
        example = domain in {b'example.com', b'example.org', b'example.net', b'example.invalid'}
        if not NOREPLY.fullmatch(address) and (metadata or not example):
            report(location, 'personal email')


def check_path(name):
    path = pathlib.PurePosixPath(name)
    if (any(pathlib.PurePosixPath(part).suffix.lower() in PRIVATE_SUFFIXES for part in path.parts)
            or path.name == 'Local.xcconfig' or path.name.startswith('.env')
            or '.private-backups' in path.parts):
        report(name, 'private artifact')


def check_image(data, location):
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        pos = 8
        while pos + 12 <= len(data):
            size = int.from_bytes(data[pos:pos + 4], 'big')
            kind = data[pos + 4:pos + 8]
            if kind in {b'tEXt', b'zTXt', b'iTXt', b'eXIf'}:
                report(location, 'image text or EXIF metadata')
            pos += size + 12
        return True
    if data.startswith(b'\xff\xd8'):
        pos = 2
        while pos + 4 <= len(data) and data[pos] == 255:
            marker = data[pos + 1]
            if marker in (0xDA, 0xD9):
                break
            size = int.from_bytes(data[pos + 2:pos + 4], 'big')
            if size < 2:
                report(location, 'malformed image metadata')
                break
            if marker in (0xE1, 0xED, 0xFE):
                report(location, 'image EXIF, IPTC or comment metadata')
            pos += 2 + size
        return True
    return False


def check_blob(data, location):
    if not check_image(data, location):
        check_text(data, location)


def audit_index():
    files = git('ls-files', '--stage', '-z').split(b'\0')
    count = 0
    for entry in filter(None, files):
        info, name = entry.split(b'\t', 1)
        mode, oid, stage = info.split()
        path = name.decode('utf-8', 'replace')
        check_path(path)
        if stage != b'0' or mode == b'160000':
            report(path, 'unmerged index or unaudited submodule')
            continue
        check_blob(git('cat-file', 'blob', oid.decode()), path)
        count += 1
    return count


def audit_history(revisions):
    for revision in revisions:
        # Fail rather than silently skip a pushed ref that does not resolve to a commit.
        git('rev-parse', '--verify', revision + '^{commit}')
        kind = git('cat-file', '-t', revision).strip()
        while kind == b'tag':
            raw = git('cat-file', 'tag', revision)
            for line in raw.splitlines():
                if line.startswith(b'tagger '):
                    check_identity(line, 'tag ' + revision[:12])
            check_text(raw, 'tag ' + revision[:12], metadata=True)
            revision = raw.splitlines()[0].removeprefix(b'object ').decode()
            kind = git('cat-file', '-t', revision).strip()
    commits = git('rev-list', *revisions, '--').splitlines()
    blobs = {}
    for oid in commits:
        sha = oid.decode()
        location = 'commit ' + sha[:12]
        raw = git('cat-file', 'commit', sha)
        headers, _, message = raw.partition(b'\n\n')
        for field in (b'author ', b'committer '):
            lines = [line for line in headers.splitlines() if line.startswith(field)]
            if len(lines) != 1:
                report(location, 'missing commit identity')
            else:
                check_identity(lines[0], location)
        check_text(raw, location, metadata=True)
        for entry in filter(None, git('ls-tree', '-rz', sha).split(b'\0')):
            info, name = entry.split(b'\t', 1)
            mode, kind, blob = info.split()
            path = name.decode('utf-8', 'replace')
            check_path(path)
            if kind != b'blob':
                report(path, 'unaudited submodule')
            else:
                blobs.setdefault(blob.decode(), path)
    for blob, path in blobs.items():
        check_blob(git('cat-file', 'blob', blob), path)
    return len(commits), len(blobs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identity', action='store_true', help='Check the effective identity, including environment overrides.')
    parser.add_argument('--staged', action='store_true', help='Check the actual Git index, not unstaged working files.')
    parser.add_argument('--history', nargs='+', metavar='REF', help='Check every reachable commit and blob from these refs.')
    parser.add_argument('--message', type=pathlib.Path, help='Check a proposed commit message and co-author trailers.')
    args = parser.parse_args()
    try:
        if args.identity:
            for name in ('GIT_AUTHOR_IDENT', 'GIT_COMMITTER_IDENT'):
                check_identity(git('var', name), 'effective ' + name.lower())
        if args.message:
            check_text(args.message.read_bytes(), 'commit message', metadata=True)
        if args.history:
            commits, blobs = audit_history(args.history)
            print(f'Audited {commits} commits and {blobs} file versions.')
        if args.staged or not (args.identity or args.message or args.history):
            print(f'Audited {audit_index()} staged files.')
    except (OSError, ValueError, subprocess.CalledProcessError):
        print('Privacy audit could not finish; refusing to continue.', file=sys.stderr)
        return 1
    for location, reason in sorted(issues):
        print(f'{location}: {reason}', file=sys.stderr)
    print(f'Privacy audit: {len(issues)} findings.')
    return int(bool(issues))


if __name__ == '__main__':
    sys.exit(main())
