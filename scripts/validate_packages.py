#!/usr/bin/env python3
"""Read-only source checks and disposable rebuilds. Never invokes installer -pkg to install."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import subprocess


def run(*args):
    return subprocess.run([str(arg) for arg in args], check=True, capture_output=True, text=True).stdout


def digest_tree(root):
    root = pathlib.Path(root)
    if root.is_file():
        return hashlib.sha256(root.read_bytes()).hexdigest()
    return {str(file.relative_to(root)): hashlib.sha256(file.read_bytes()).hexdigest()
            for file in root.rglob('*') if file.is_file() and not file.is_symlink()}


def rpc(backend, request):
    process = subprocess.run([str(backend), '--rpc'], input=json.dumps(request) + '\n', capture_output=True, text=True)
    events = [json.loads(line) for line in process.stdout.splitlines()]
    assert process.returncode == 0, (events, process.stderr)
    assert events[-1]['type'] == 'result', events[-1]
    return events[-1]['value']


def main():
    parser = argparse.ArgumentParser()
    for name in ['original', 'fixed', 'legacy', 'backend', 'output']:
        parser.add_argument('--' + name, type=pathlib.Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    report = {}
    for label, source in [('original', args.original), ('fixed', args.fixed), ('legacy', args.legacy)]:
        before = digest_tree(source)
        workspace = args.output / (label + '-workspace')
        request = {'operation': 'inspect', 'source': str(source.resolve()), 'workspace': str(workspace.resolve()), 'language': 'en'}
        inspection = rpc(args.backend, request)
        if label == 'original':
            assert inspection['stats']['installSizes'] == 1
            assert inspection['stats']['binaries'] == 3, inspection['stats']
        if label == 'fixed':
            assert inspection['stats']['installSizes'] == 0
        if label == 'legacy':
            assert inspection['stats']['components'] == 2
            assert inspection['stats']['legacy'] == 2
            assert inspection['stats']['binaries'] == 2
        baseline = digest_tree(workspace / 'repack')
        request.update(operation='rebuild', options={'scripts': False, 'outputDirectory': str(args.output.resolve()), 'outputName': f'{label}-modernized.pkg'})
        result = rpc(args.backend, request)
        product = pathlib.Path(result['output'])
        assert result['verified'] is True
        expanded = args.output / (label + '-verified')
        if expanded.exists():
            import shutil
            shutil.rmtree(expanded)
        run('/usr/sbin/pkgutil', '--expand', product, expanded)
        after = digest_tree(expanded)
        if label in ['original', 'fixed']:
            # All scripts, embedded payload bytes and component metadata are unchanged.
            assert {k: v for k, v in before_metadata(baseline).items()} == before_metadata(after)
            assert not any(issue['id'] == 'install-sizes' for issue in rpc(args.backend, {**request, 'operation': 'inspect', 'source': str(product)})['issues'])
        else:
            full = args.output / 'legacy-full'
            if full.exists():
                import shutil
                shutil.rmtree(full)
            run('/usr/sbin/pkgutil', '--expand-full', product, full)
            for archive in source.glob('Contents/Packages/*.pkg/Contents/Archive.pax.gz'):
                component = archive.parent.parent.name
                unpacked = args.output / ('legacy-source-' + component)
                if unpacked.exists():
                    import shutil
                    shutil.rmtree(unpacked)
                unpacked.mkdir()
                run('/usr/bin/tar', '-xzf', archive, '-C', unpacked, '--no-same-owner')
                assert digest_tree(unpacked) == digest_tree(full / component / 'Payload'), component

        # This queries choices; it does not install anything or run install scripts.
        choices = run('/usr/sbin/installer', '-showChoicesXML', '-pkg', product, '-target', '/')
        parsed_choices = plistlib.loads(choices.encode())
        assert parsed_choices, product
        assert before == digest_tree(source), 'Source package was modified'
        report[label] = {'stats': inspection['stats'], 'compatibility': inspection['compatibility'], 'output': str(product), 'archive_verified': True,
                         'installer_choices_readable': True, 'source_unchanged': True,
                         'content_preserved': True, 'fixes': result['fixes']}
    assert report['original']['fixes'] == 5
    assert report['fixed']['fixes'] == 0
    (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


def before_metadata(files):
    return {name: digest for name, digest in files.items() if name != 'Distribution'}


if __name__ == '__main__':
    main()
