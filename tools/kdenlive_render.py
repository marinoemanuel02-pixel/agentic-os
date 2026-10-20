"""Render an exported local MLT timeline with a checked subset of Windows plugins."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

PLUGINS = ('core', 'avformat', 'xml', 'resample', 'qt6', 'kdenlive')


def checked_xml(source, services):
    root = ET.parse(source).getroot()
    if root.tag != 'mlt':
        raise ValueError('Expected an MLT XML project')
    required = set()
    for element in root.iter():
        props = {p.get('name'): p.text for p in element.findall('property')}
        if props.get('disable') != '1' and props.get('mlt_service'):
            required.add(props['mlt_service'])
    missing = required - services
    if missing:
        raise ValueError('Selected renderer lacks required services: ' + ', '.join(sorted(missing)))
    if root.get('producer') == 'main_bin':
        if root.find("tractor[@id='tractor_project']") is None:
            raise ValueError('Project selects the bin; an explicit supported timeline is required')
        root.set('producer', 'tractor_project')
    # Temporary XML lives beside the output, so retain the original media-resolution root.
    media_root = Path(root.get('root') or '.')
    if not media_root.is_absolute():
        media_root = source.resolve().parent / media_root
    root.set('root', str(media_root.resolve()))
    return ET.tostring(root, encoding='unicode')


def command(melt, repository, source, output):
    return [str(melt), '-repository', str(repository), str(source), '-consumer',
            'avformat:' + str(output), 'vcodec=libx264', 'acodec=aac', 'f=mp4', 'real_time=-1']


def environment(app):
    return dict(os.environ, MLT_DATA=str(app / 'share/mlt'), QT_QPA_PLATFORM='offscreen',
                PATH=str(app / 'bin') + os.pathsep + os.environ.get('PATH', ''))


def plugin_repository(app):
    files = [app / 'lib/mlt' / ('libmlt' + name + '.dll') for name in PLUGINS]
    digest = hashlib.sha256(b''.join(hashlib.sha256(p.read_bytes()).digest() for p in files)).hexdigest()[:16]
    target = Path.home() / '.aos/tools/stack/kdenlive-render' / digest
    target.mkdir(parents=True, exist_ok=True)
    for source in files:
        dest = target / source.name
        if not dest.exists() or dest.read_bytes() != source.read_bytes():
            shutil.copyfile(source, dest)
    return target


def render(source, output, timeout=300):
    source, output = Path(source).resolve(), Path(output).resolve()
    if output.exists():
        raise FileExistsError('Output already exists; choose a new file')
    if not source.is_file():
        raise ValueError('MLT source not found')
    if output.suffix.lower() != '.mp4':
        raise ValueError('This checked renderer exports H.264/AAC MP4 only')
    app = Path.home() / 'AppData/Local/Programs/Kdenlive'
    melt = app / 'bin/melt.exe'
    repository, env = plugin_repository(app), environment(app)
    services = {'playlist', 'tractor'}
    for kind in ('producers', 'filters', 'transitions'):
        result = subprocess.run([str(melt), '-repository', str(repository), '-query', kind],
                                capture_output=True, text=True, encoding='utf-8', errors='replace',
                                env=env, timeout=15, check=True, shell=False)
        services.update(re.findall(r'^\s+- (\S+)\s*$', result.stdout + '\n' + result.stderr, re.M))
    text = checked_xml(source, services)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='aos-render-', dir=output.parent) as work:
        xml, media = Path(work) / 'timeline.mlt', Path(work) / 'render.mp4'
        xml.write_text(text, encoding='utf-8')
        subprocess.run(command(melt, repository, xml, media), env=env, capture_output=True,
                       text=True, encoding='utf-8', errors='replace', timeout=timeout, check=True, shell=False)
        probe = subprocess.run([str(app / 'bin/ffprobe.exe'), '-v', 'error', '-show_format', '-show_streams',
                               '-of', 'json', str(media)], capture_output=True, timeout=20, check=True, shell=False)
        info = json.loads(probe.stdout)
        if float(info.get('format', {}).get('duration', 0)) <= 0 or not info.get('streams'):
            raise ValueError('Renderer produced no usable media')
        # Publish only after verification, with an atomic refusal to replace an existing output.
        os.link(media, output)
    return {'output': str(output), 'bytes': output.stat().st_size, 'duration': float(info['format']['duration']),
            'streams': [s['codec_type'] for s in info['streams']], 'plugin_repository': str(repository)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--timeout', type=int, default=300)
    args = parser.parse_args()
    try:
        if not 1 <= args.timeout <= 3600:
            raise ValueError('Timeout must be between 1 and 3600 seconds')
        print(json.dumps(render(args.source, args.output, args.timeout), indent=2))
        return 0
    except (OSError, ValueError, ET.ParseError, subprocess.SubprocessError) as exc:
        print('Native render failed: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
