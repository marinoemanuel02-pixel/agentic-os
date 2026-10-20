"""One explicit text-only OmniRoute request, saved as an unaccepted candidate."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

MAX_PROMPT = 32 * 1024
MAX_RESPONSE = 1024 * 1024


def validate_endpoint(endpoint):
    url = urllib.parse.urlsplit(endpoint)
    if (url.scheme != 'http' or url.hostname not in ('127.0.0.1', '::1')
            or url.username is not None or url.password is not None or url.query or url.fragment
            or url.path.rstrip('/') != '/v1'):
        raise ValueError('Use an explicit loopback http://127.0.0.1:PORT/v1 endpoint without credentials')
    _ = url.port  # Reject malformed ports before constructing a request.
    return endpoint.rstrip('/')


def activation_key(environment):
    key = environment.get('OMNIROUTE_WORKER_KEY', '').strip()
    if not key:
        raise ValueError('A scoped router key must be supplied to this process from aos secret')
    if any(ord(char) < 33 or ord(char) > 126 for char in key):
        raise ValueError('Router credential must be one printable ASCII token')
    return key


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def parse_response(payload):
    if not isinstance(payload, dict):
        raise ValueError('Expected a completion object')
    choices = payload.get('choices', [])
    if not isinstance(choices, list) or len(choices) != 1 or not isinstance(choices[0], dict):
        raise ValueError('Expected one completion; no automatic retry or fallback was attempted')
    message = choices[0].get('message', {})
    if not isinstance(message, dict):
        raise ValueError('Expected a text message object')
    text = message.get('content')
    if message.get('tool_calls') or message.get('function_call') or not isinstance(text, str) or not text.strip():
        raise ValueError('Expected text without tool calls; candidate rejected')
    usage = payload.get('usage') or {}
    measured = {name: value for name, value in usage.items()
                if name in ('prompt_tokens', 'completion_tokens', 'total_tokens')
                and type(value) is int and value >= 0} if isinstance(usage, dict) else {}
    return {'text': text, 'reported_model': payload.get('model'),
            'complete': choices[0].get('finish_reason') == 'stop', 'provider_reported_usage': measured}


def request(endpoint, model, prompt, key, timeout=45):
    endpoint = validate_endpoint(endpoint)
    if not model.strip() or len(model) > 200 or len(prompt.encode('utf-8')) > MAX_PROMPT or not prompt.strip():
        raise ValueError('Supply one explicit route and a nonempty task packet of at most 32 KiB')
    body = json.dumps({'model': model, 'messages': [{'role': 'user', 'content': prompt}],
                       'stream': False, 'max_tokens': 2048,
                       'provider': {'allow_fallbacks': False,
                                    'max_price': {'prompt': 0, 'completion': 0, 'request': 0}}}).encode('utf-8')
    req = urllib.request.Request(endpoint + '/chat/completions', data=body,
                                 headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    started = time.monotonic()
    try:
        with opener.open(req, timeout=timeout) as response:
            data = response.read(MAX_RESPONSE + 1)
    except urllib.error.HTTPError as error:
        raise ValueError('Router returned HTTP ' + str(error.code) + '; no retry or fallback attempted') from None
    except urllib.error.URLError:
        raise ValueError('Router connection failed; no retry or fallback attempted') from None
    if len(data) > MAX_RESPONSE:
        raise ValueError('Router response exceeds the 1 MiB limit')
    result = parse_response(json.loads(data))
    result.update(requested_model=model, endpoint=endpoint, seconds=round(time.monotonic() - started, 3),
                  prompt_sha256=hashlib.sha256(prompt.encode('utf-8')).hexdigest(),
                  response_sha256=hashlib.sha256(result['text'].encode('utf-8')).hexdigest(),
                  accepted=False, filesystem_tools=False, requests=1)
    return result


def save_candidate(path, result):
    with Path(path).open('x', encoding='utf-8') as target:
        json.dump(result, target, indent=2, ensure_ascii=False)
        target.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--endpoint', required=True)
    parser.add_argument('--model', required=True)
    parser.add_argument('--packet', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        key = activation_key(os.environ)
        if args.output.exists():
            raise ValueError('Candidate output already exists; choose a new path')
        if args.packet.stat().st_size > MAX_PROMPT:
            raise ValueError('Task packet exceeds 32 KiB')
        result = request(args.endpoint, args.model, args.packet.read_text(encoding='utf-8'), key)
        save_candidate(args.output, result)
        print('Candidate saved; the lead must verify it before use.')
        return 0 if result['complete'] else 1
    except (ValueError, OSError, TypeError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
