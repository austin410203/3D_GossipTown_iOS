"""Tiny GitHub API helper using the git credential token (no gh on this machine). Prints no secrets.
usage: python -I tools/gh.py visibility public|private
       python -I tools/gh.py runs                  (latest workflow runs)
       python -I tools/gh.py dispatch testflight   (workflow_dispatch with testflight=true)
"""
import json, subprocess, sys, urllib.request

REPO = 'austin410203/3D_GossipTown_iOS'


def token():
    out = subprocess.run(['git', 'credential', 'fill'], input='protocol=https\nhost=github.com\n\n', capture_output=True, text=True).stdout
    return dict(l.split('=', 1) for l in out.splitlines() if '=' in l)['password']


def api(method, path, body=None):
    req = urllib.request.Request(f'https://api.github.com{path}', method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={'Authorization': f'token {token()}', 'Accept': 'application/vnd.github+json', 'User-Agent': 'gossiptown-ci'})
    with urllib.request.urlopen(req) as r:
        t = r.read()
        return json.loads(t) if t else {}


cmd = sys.argv[1]
if cmd == 'visibility':
    r = api('PATCH', f'/repos/{REPO}', {'private': sys.argv[2] == 'private'})
    print('private' if r['private'] else 'public')
elif cmd == 'runs':
    for w in api('GET', f'/repos/{REPO}/actions/runs?per_page=5')['workflow_runs']:
        print(w['run_number'], w['status'], w['conclusion'], w['head_sha'][:7], w['display_title'][:60])
elif cmd == 'jobs':
    run = api('GET', f'/repos/{REPO}/actions/runs?per_page=1')['workflow_runs'][0]
    for j in api('GET', f"/repos/{REPO}/actions/runs/{run['id']}/jobs")['jobs']:
        print(j['name'], j['status'], j['conclusion'], [(s['name'], s['conclusion']) for s in j['steps'] if s['conclusion'] not in ('success', 'skipped', None)])
elif cmd == 'dispatch':
    api('POST', f'/repos/{REPO}/actions/workflows/ios.yml/dispatches', {'ref': 'main', 'inputs': {'testflight': 'testflight' in sys.argv[2:], 'storeshots': 'storeshots' in sys.argv[2:]}})
    print('dispatched')
elif cmd == 'secret':
    # secret NAME VALUE — encrypted with the repo public key (libsodium sealed box)
    from base64 import b64encode, b64decode
    from nacl import encoding, public
    k = api('GET', f'/repos/{REPO}/actions/secrets/public-key')
    box = public.SealedBox(public.PublicKey(k['key'].encode(), encoding.Base64Encoder()))
    enc = b64encode(box.encrypt(sys.argv[3].encode())).decode()
    api('PUT', f'/repos/{REPO}/actions/secrets/{sys.argv[2]}', {'encrypted_value': enc, 'key_id': k['key_id']})
    print('set', sys.argv[2])
elif cmd == 'secrets':
    print(' '.join(s['name'] for s in api('GET', f'/repos/{REPO}/actions/secrets')['secrets']))
