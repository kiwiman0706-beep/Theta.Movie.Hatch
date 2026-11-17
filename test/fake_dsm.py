"""DSM の File Station を真似る小さなサーバー（結合テスト用）。

    python3 test/fake_dsm.py <動画のフォルダ> [port] [--otp]

<動画のフォルダ> を共有フォルダ /video として見せる。SYNO.API.Info・SYNO.API.Auth（2 段階認証つき）・
SYNO.FileStation.List・SYNO.FileStation.Download（Range 対応）だけ。形は DSM 7 の Web API に合わせたが、
細部は実機と違う場合がある（TESTING.md）。
"""
import json
import os
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.abspath(sys.argv[1])
PORT = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 5999
NEED_OTP = '--otp' in sys.argv
USER, PASS, OTP, SID, DID = 'u', 'p', '123456', 'sid-xyz', 'did-abc'

APIS = {
    'SYNO.API.Auth': {'path': 'entry.cgi', 'minVersion': 1, 'maxVersion': 7},
    'SYNO.FileStation.List': {'path': 'entry.cgi', 'minVersion': 1, 'maxVersion': 2},
    'SYNO.FileStation.Download': {'path': 'entry.cgi', 'minVersion': 1, 'maxVersion': 2},
}


def local(p):
    if not p.startswith('/video'):
        return None
    rel = p[len('/video'):].lstrip('/')
    full = os.path.abspath(os.path.join(ROOT, rel))
    return full if full.startswith(ROOT) else None


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send_json(self, obj):
        b = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def ok(self, data=None):
        self.send_json({'success': True, 'data': data or {}})

    def err(self, code):
        self.send_json({'success': False, 'error': {'code': code}})

    def params(self):
        u = urllib.parse.urlparse(self.path)
        q = dict(urllib.parse.parse_qsl(u.query))
        if self.command == 'POST':
            n = int(self.headers.get('Content-Length') or 0)
            q.update(dict(urllib.parse.parse_qsl(self.rfile.read(n).decode())))
        return q

    def do_GET(self):
        self.handle_req()

    def do_POST(self):
        self.handle_req()

    def handle_req(self):
        q = self.params()
        api = q.get('api', '')
        if api == 'SYNO.API.Info':
            return self.ok(APIS)
        if api == 'SYNO.API.Auth':
            if q.get('account') != USER or q.get('passwd') != PASS:
                return self.err(400)
            if NEED_OTP and q.get('device_id') != DID:
                if 'otp_code' not in q:
                    return self.err(403)
                if q['otp_code'] != OTP:
                    return self.err(404)
                return self.ok({'sid': SID, 'did': DID})
            return self.ok({'sid': SID})
        if q.get('_sid') != SID:
            return self.err(119)
        if api == 'SYNO.FileStation.List':
            d = local(q.get('folder_path', ''))
            if d is None or not os.path.isdir(d):
                return self.err(408)
            names = sorted(os.listdir(d))
            off, lim = int(q.get('offset', 0)), int(q.get('limit', 1000))
            files = []
            for n in names[off:off + lim]:
                full = os.path.join(d, n)
                st = os.stat(full)
                files.append({
                    'path': q['folder_path'].rstrip('/') + '/' + n,
                    'name': n,
                    'isdir': os.path.isdir(full),
                    'additional': {'size': st.st_size, 'time': {'mtime': int(st.st_mtime)}},
                })
            return self.ok({'files': files, 'total': len(names), 'offset': off})
        if api == 'SYNO.FileStation.Download':
            f = local(q.get('path', ''))
            if f is None or not os.path.isfile(f):
                return self.err(408)
            size = os.path.getsize(f)
            start, end = 0, size - 1
            rng = self.headers.get('Range')
            if rng and rng.startswith('bytes='):
                a, _, b = rng[6:].partition('-')
                start = int(a or 0)
                end = int(b) if b else size - 1
                self.send_response(206)
                self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
            else:
                self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Accept-Ranges', 'bytes')
            self.send_header('Content-Length', str(end - start + 1))
            self.end_headers()
            with open(f, 'rb') as fh:
                fh.seek(start)
                self.wfile.write(fh.read(end - start + 1))
            return
        return self.err(102)


print('fake DSM on', PORT, 'otp' if NEED_OTP else '', flush=True)
ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()
