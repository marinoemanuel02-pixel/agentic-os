"""Preserve upstream Watch frames and add embedded text captions for local media."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

TEXT_CODECS = {'mov_text', 'subrip', 'srt', 'webvtt', 'ass', 'ssa', 'text'}


def select_stream(streams, language):
    candidates = [s for s in streams if s.get('codec_name') in TEXT_CODECS
                  and (not language or s.get('tags', {}).get('language') == language)]
    return next((s for s in candidates if s.get('disposition', {}).get('default')), candidates[0] if candidates else None)


def merge_report(report, transcript, count, language):
    metadata = ('- **Transcript:** ' + str(count) + ' segments (embedded captions, ' + language + ')'
                if count else '- **Transcript:** no caption cues in selected range (embedded captions)')
    report, replaced = re.subn(r'^- \*\*Transcript:\*\*[^\n]*', lambda _: metadata, report, count=1, flags=re.M)
    start = report.find('\n## Transcript\n')
    end_match = re.search(r'\n(?:## Unavailable evidence\n|---\n)', report[start + 1:]) if start >= 0 else None
    if replaced != 1 or start < 0 or end_match is None:
        raise ValueError('Upstream Watch report layout changed; embedded captions were not merged')
    end = start + 1 + end_match.start()
    # The fence grows if subtitle text itself contains backticks.
    fence = '`' * max(3, max((len(m.group()) + 1 for m in re.finditer(r'`+', transcript)), default=3))
    section = ('\n## Transcript\n\n_Source: embedded captions (' + language + '); source-relative timestamps._\n\n'
               + fence + '\n' + transcript + '\n' + fence + '\n' if transcript
               else '\n## Transcript\n\n_No caption cues in selected range; embedded track exists._\n')
    return report[:start] + section + '\n' + report[end:]


def seconds(value):
    return None if value is None else sum(float(part) * 60 ** i for i, part in enumerate(reversed(value.split(':'))))


def local_options(arguments):
    options = argparse.ArgumentParser(add_help=False)
    options.add_argument('source')
    for flag in ('--start', '--end', '--sub-lang'):
        options.add_argument(flag)
    # Consume the other pinned upstream options so their values cannot become the source.
    options.add_argument('--max-frames', '--resolution', '--fps', '--detail', '--timestamps',
                         '--out-dir', '--whisper', '--cookies', '--cookies-from-browser',
                         '--engine', '--question', dest='ignored_value')
    options.add_argument('--no-whisper', '--no-dedup', action='store_true', dest='ignored_switch')
    return options.parse_args(arguments)


def embedded_transcript(source, language, start, end, upstream):
    probe = subprocess.run([shutil.which('ffprobe') or 'ffprobe', '-v', 'error', '-select_streams', 's',
                            '-show_streams', '-of', 'json', str(source)], capture_output=True,
                           timeout=30, check=True, shell=False)
    stream = select_stream(json.loads(probe.stdout).get('streams', []), language)
    if stream is None:
        return None
    with tempfile.TemporaryDirectory(prefix='watch-captions-', dir=os.environ.get('TEMP')) as work:
        captions = Path(work) / 'captions.vtt'
        subprocess.run([shutil.which('ffmpeg') or 'ffmpeg', '-nostdin', '-v', 'error', '-i', str(source),
                        '-map', '0:' + str(stream['index']), '-c:s', 'webvtt', str(captions)],
                       capture_output=True, timeout=60, check=True, shell=False)
        # Reuse the pinned upstream parser, overlap rules and timestamp formatter.
        sys.path.insert(0, str(upstream.parent))
        try:
            spec = importlib.util.spec_from_file_location('watch_transcribe', upstream.with_name('transcribe.py'))
            parser = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(parser)
            segments = parser.filter_range(parser.parse_vtt(captions), seconds(start), seconds(end))
            return parser.format_transcript(segments), len(segments), stream.get('tags', {}).get('language', 'unknown')
        finally:
            sys.path.pop(0)


def main():
    upstream = Path.home() / '.aos/tools/stack/watch/source/skills/watch/scripts/watch.py'
    arguments = sys.argv[1:]
    # Also enforce the local policy for direct invocation outside tools/stack.py.
    for index, arg in enumerate(arguments):
        if arg.split('=', 1)[0] == '--whisper':
            raise ValueError('Use the existing offline footage workflow for speech transcription')
        if arg.startswith('--engine=') and arg != '--engine=local':
            raise ValueError('This Watch adapter requires the local engine')
        if arg == '--engine' and (index + 1 == len(arguments) or arguments[index + 1] != 'local'):
            raise ValueError('This Watch adapter requires the local engine')
    result = subprocess.run([sys.executable, str(upstream), *arguments, '--engine', 'local', '--no-whisper',
                             '--max-frames', '30'], capture_output=True, text=True, encoding='utf-8',
                            errors='replace', timeout=300, shell=False)
    sys.stderr.write(result.stderr)
    report = result.stdout
    if result.returncode == 0 and not any(a in ('--help', '-h') for a in arguments):
        args = local_options(arguments)
        source = Path(args.source).expanduser()
        if source.is_file():
            try:
                evidence = embedded_transcript(source.resolve(), args.sub_lang, args.start, args.end, upstream)
                if evidence is not None:
                    report = merge_report(report, *evidence)
            except (OSError, ValueError, subprocess.SubprocessError):
                sys.stdout.write(report)
                print('\nEmbedded caption extraction failed; original Watch evidence is preserved.', file=sys.stderr)
                return 1
    sys.stdout.write(report)
    return result.returncode


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(2)
