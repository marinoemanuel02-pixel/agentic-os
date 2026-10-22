import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, patch

TOOLS = Path(__file__).resolve().parents[1] / 'tools'


def load(name):
    spec = importlib.util.spec_from_file_location(name, TOOLS / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ConsumerMcpTests(unittest.TestCase):
    def test_consumer_key_uses_connect_header_and_never_follows_redirects(self):
        client = load('composio_connect')
        response = MagicMock()
        response.__enter__.return_value.read.return_value = (
            b': connected\n\nevent: message\ndata: {"jsonrpc":"2.0","id":1,"result":{"tools":[]}}\n\n')
        with patch.object(client.urllib.request, 'build_opener') as factory:
            factory.return_value.open.return_value = response
            self.assertEqual(client.request('tools/list', {}, 'fixture-key'), {'tools': []})
            req = factory.return_value.open.call_args.args[0]
            self.assertEqual(req.full_url, 'https://connect.composio.dev/mcp')
            self.assertEqual(req.get_header('X-consumer-api-key'), 'fixture-key')
            self.assertIsNone(req.get_header('X-api-key'))
            self.assertIsNone(client.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://other.test'))

    def test_http_errors_never_echo_credentials_or_server_body(self):
        client = load('composio_connect')
        import urllib.error
        with patch.object(client.urllib.request, 'build_opener') as factory:
            factory.return_value.open.side_effect = urllib.error.HTTPError(
                client.ENDPOINT, 401, 'fixture-key private response', {}, None)
            with self.assertRaisesRegex(ValueError, 'HTTP 401') as caught:
                client.request('tools/list', {}, 'fixture-key')
            self.assertNotIn('fixture-key', str(caught.exception))
            factory.return_value.open.assert_called_once()

    def test_rpc_error_and_oversized_responses_are_failures(self):
        client = load('composio_connect')
        for raw in [b'{"id":1,"error":{"message":"private response"}}',
                    b'x' * (client.MAX_RESPONSE + 1), b'{"id":2,"result":{}}']:
            with self.assertRaises(ValueError):
                client.parse_response(raw, 1)


class LocalCaptionTests(unittest.TestCase):
    def test_source_is_identified_when_upstream_options_precede_it(self):
        watch = load('watch_local')
        args = watch.local_options(['--detail', 'efficient', '--out-dir', 'output dir',
                                    'movie.mp4', '--start', '00:05', '--no-dedup'])
        self.assertEqual(args.source, 'movie.mp4')
        self.assertEqual(args.start, '00:05')

    def test_replaces_missing_caption_claim_but_preserves_frames_and_errors(self):
        watch = load('watch_local')
        report = ('# watch: video report\n- **Transcript:** fallback disabled; no captions available\n'
                  '## Frames\nframe.png (t=00:05)\n\n## Transcript\n'
                  '_Fallback disabled; no captions available._\n\n'
                  '## Unavailable evidence\n- original visual error\n\n---\n_Work dir: `fixture`_\n')
        merged = watch.merge_report(report, '[00:05] embedded words', 1, 'eng')
        self.assertIn('frame.png (t=00:05)', merged)
        self.assertIn('original visual error', merged)
        self.assertIn('[00:05] embedded words', merged)
        self.assertNotIn('no captions available', merged)
        self.assertIn('embedded captions', merged)

    def test_quiet_focus_is_not_missing_track_and_changed_layout_is_rejected(self):
        watch = load('watch_local')
        report = '- **Transcript:** missing\n\n## Transcript\n_missing_\n\n---\nfooter'
        self.assertIn('no caption cues in selected range', watch.merge_report(report, '', 0, 'eng'))
        with self.assertRaisesRegex(ValueError, 'layout'):
            watch.merge_report('upstream format changed', 'words', 1, 'eng')

    def test_language_choice_does_not_silently_use_another_language_or_bitmap(self):
        watch = load('watch_local')
        streams = [{'index': 2, 'codec_name': 'hdmv_pgs_subtitle', 'tags': {'language': 'eng'}},
                   {'index': 3, 'codec_name': 'mov_text', 'tags': {'language': 'ita'}},
                   {'index': 4, 'codec_name': 'subrip', 'tags': {'language': 'eng'}, 'disposition': {'default': 1}}]
        self.assertEqual(watch.select_stream(streams, None)['index'], 4)
        self.assertEqual(watch.select_stream(streams, 'ita')['index'], 3)
        self.assertIsNone(watch.select_stream(streams, 'deu'))


class NativeRenderTests(unittest.TestCase):
    def test_relative_media_root_survives_temporary_xml_relocation(self):
        render = load('kdenlive_render')
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'project.mlt'
            source.write_text('<mlt root="media"><producer id="clip"/></mlt>')
            root = render.ET.fromstring(render.checked_xml(source, set()))
            self.assertEqual(Path(root.get('root')).resolve(), (source.parent / 'media').resolve())
            self.assertIn('root="media"', source.read_text())

    def test_selects_exported_timeline_and_refuses_unknown_services(self):
        render = load('kdenlive_render')
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'project.kdenlive'
            source.write_text('<mlt producer="main_bin"><tractor id="tractor_project"/>'
                              '<filter><property name="mlt_service">unsupported.effect</property></filter></mlt>')
            before = source.read_bytes()
            with self.assertRaisesRegex(ValueError, 'unsupported.effect'):
                render.checked_xml(source, {'color', 'avformat'})
            self.assertEqual(source.read_bytes(), before)
            text = render.checked_xml(source, {'unsupported.effect'})
            self.assertIn('producer="tractor_project"', text)
            self.assertEqual(source.read_bytes(), before)

    def test_repository_argument_precedes_input_and_output_is_not_overwritten(self):
        render = load('kdenlive_render')
        command = render.command(Path('melt.exe'), Path('plugins'), Path('project.mlt'), Path('output.mp4'))
        self.assertEqual(command[1:3], ['-repository', 'plugins'])
        self.assertGreater(command.index('project.mlt'), command.index('-repository'))
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / 'output.mp4'
            target.write_bytes(b'keep')
            with self.assertRaises(FileExistsError):
                render.render(Path('missing.mlt'), target)
            self.assertEqual(target.read_bytes(), b'keep')


if __name__ == '__main__':
    unittest.main()
