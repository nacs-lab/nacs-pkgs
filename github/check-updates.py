#!/usr/bin/env python3

# Decide which packages need to be rebuilt.
#
# A package is rebuilt when
# 1. its upstream commit (from nvchecker) doesn't match its pkgver, or
# 2. the package for the current PKGBUILD version is not published yet, or
# 3. one of the packages it links to is rebuilt.
#    The pkgrel is bumped in this case so that the new package gets a new version.
#
# The list of packages to build for each platform is written to `$GITHUB_OUTPUT`.

import argparse
import json
import os
import re
import subprocess
import sys
import tomllib

PLATFORMS = {
    'archlinux': {
        'srcdir': 'arch',
        'repodir': 'archlinux/x86_64',
        'env': {'CARCH': 'x86_64', 'CHOST': 'x86_64-pc-linux-gnu'},
        # Package -> packages that it needs to be rebuilt against
        'packages': {
            'libnacs-git': [],
            'python-libnacs-git': [],
            'molecube2-git': ['libnacs-git'],
            'labctrl-node-git': ['libnacs-git'],
            'libspcm': [],
        },
    },
    'archlinux-arm': {
        'srcdir': 'arch-arm',
        'repodir': 'archlinux/armv7h',
        'env': {'CARCH': 'armv7h', 'CHOST': 'armv7l-unknown-linux-gnueabihf'},
        'packages': {
            'linux-nacs': [],
            'knacs-git': ['linux-nacs'],
            'nacs-boot': [],
            'libnacs-git': ['knacs-git'],
            'molecube2-git': ['libnacs-git'],
        },
    },
    'msys2': {
        'srcdir': 'windows',
        'repodir': 'msys2/mingw64',
        'env': {'CARCH': 'x86_64', 'CHOST': 'x86_64-w64-mingw32',
                'MINGW_PACKAGE_PREFIX': 'mingw-w64-x86_64'},
        'packages': {
            'mingw-w64-sleef-git': [],
            'mingw-w64-libnacs-git': ['mingw-w64-sleef-git'],
        },
    },
}

PKGINFO_SCRIPT = '''
source PKGBUILD || exit 1
echo "$epoch"
echo "$pkgver"
echo "$pkgrel"
echo "${arch[*]}"
printf '%s\\n' "${pkgname[@]}"
'''

def read_pkginfo(path, env):
    out = subprocess.run(['bash', '-c', PKGINFO_SCRIPT], cwd=path, check=True,
                         env={**os.environ, **env}, stdout=subprocess.PIPE,
                         text=True).stdout.splitlines()
    epoch, pkgver, pkgrel, arch = out[:4]
    return {'epoch': epoch, 'pkgver': pkgver, 'pkgrel': pkgrel,
            'arch': arch.split(), 'names': out[4:]}

def package_prefixes(info, carch):
    ver = f"{info['epoch']}:" if info['epoch'] else ''
    ver += f"{info['pkgver']}-{info['pkgrel']}"
    arch = 'any' if 'any' in info['arch'] else carch
    return [f'{name}-{ver}-{arch}.pkg.tar.' for name in info['names']]

def pkgver_hash(pkgver):
    m = re.search(r'(?:^|\.)g?([0-9a-f]{7,40})$', pkgver)
    return m[1] if m else None

def run_nvchecker(config):
    with open(config, 'rb') as fh:
        entries = [name for name in tomllib.load(fh) if name != '__config__']
    # No old version file is used. The current version is read from the PKGBUILD.
    out = subprocess.run(['nvchecker', '-c', config, '--logger', 'json'],
                         stdout=subprocess.PIPE, text=True).stdout
    versions = {}
    for line in out.splitlines():
        try:
            log = json.loads(line)
        except json.JSONDecodeError:
            continue
        if 'version' in log and 'name' in log:
            versions[log['name']] = log['version']
        elif log.get('level') in ('error', 'warning'):
            print(f"nvchecker {log.get('name', '')}: {log.get('event', '')} "
                  f"{log.get('error', '')}", file=sys.stderr)
    failed = [name for name in entries if name not in versions]
    if failed:
        print(f'::warning::Failed to check upstream version of {", ".join(failed)}')
    if entries and not versions:
        sys.exit('Failed to check all upstream versions')
    return versions

def bump_pkgrel(path):
    with open(path) as fh:
        content = fh.read()
    content, n = re.subn(r'^pkgrel=(\d+)$',
                         lambda m: f'pkgrel={int(m[1]) + 1}',
                         content, count=1, flags=re.M)
    if n != 1:
        raise ValueError(f'Cannot find pkgrel in {path}')
    with open(path, 'w') as fh:
        fh.write(content)

def write_output(fh, key, value):
    if fh is not None:
        print(f'{key}={value}', file=fh)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--nvchecker', default='nvchecker.toml',
                        help='nvchecker configuration file')
    parser.add_argument('--published', required=True,
                        help='File with the list of files in the package repository')
    args = parser.parse_args()

    with open(args.published) as fh:
        published = fh.read().splitlines()
    upstream = run_nvchecker(args.nvchecker)

    output = os.environ.get('GITHUB_OUTPUT')
    output = open(output, 'a') if output else None
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    summary = open(summary, 'a') if summary else sys.stdout
    print('| Package | Version | Upstream | Action |', file=summary)
    print('|---|---|---|---|', file=summary)

    for platform, conf in PLATFORMS.items():
        carch = conf['env']['CARCH']
        prefix = conf['repodir'] + '/'
        files = [f[len(prefix):] for f in published if f.startswith(prefix)]

        rebuild = {}
        infos = {}
        # The packages are listed in dependency order.
        for pkg, deps in conf['packages'].items():
            path = os.path.join(conf['srcdir'], pkg)
            info = read_pkginfo(path, conf['env'])
            infos[pkg] = info

            upstream_ver = upstream.get(path)
            cur_hash = pkgver_hash(info['pkgver'])
            if upstream_ver is not None and cur_hash is None:
                print(f'Cannot find commit hash in {path} version {info["pkgver"]}',
                      file=sys.stderr)
            if (upstream_ver is not None and cur_hash is not None and
                not upstream_ver.startswith(cur_hash)):
                rebuild[pkg] = 'upstream updated'
            elif not all(any(f.startswith(p) for f in files)
                         for p in package_prefixes(info, carch)):
                rebuild[pkg] = 'not published'
            else:
                rebuilt_deps = [dep for dep in deps if dep in rebuild]
                if rebuilt_deps:
                    bump_pkgrel(os.path.join(path, 'PKGBUILD'))
                    info['pkgrel'] = str(int(info['pkgrel']) + 1)
                    rebuild[pkg] = f'rebuild for {", ".join(rebuilt_deps)}'

        for pkg, info in infos.items():
            ver = f"{info['pkgver']}-{info['pkgrel']}"
            upstream_ver = upstream.get(os.path.join(conf['srcdir'], pkg), '')
            print(f'| {platform}/{pkg} | {ver} | {upstream_ver[:12]} | '
                  f'{rebuild.get(pkg, "")} |', file=summary)
        write_output(output, platform, ' '.join(rebuild))

    if output is not None:
        output.close()

if __name__ == '__main__':
    main()
