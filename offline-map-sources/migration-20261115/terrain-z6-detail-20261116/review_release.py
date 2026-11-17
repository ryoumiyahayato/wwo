import gzip
import json
from pathlib import Path
import struct
import subprocess
import sys
from time import monotonic
from urllib.error import HTTPError
from urllib.request import HTTPRedirectHandler, Request, build_opener, urlopen


STAGE = Path(__file__).resolve().parent
REPO = 'ryoumiyahayato/wwo'
archive = STAGE / 'archive'
restored = STAGE / 'restored-release'
restored.mkdir(exist_ok=True)
release = json.loads(subprocess.check_output(['gh', 'api', f'repos/{REPO}/releases/tags/terrain-surface-20261115']))
assets = {item['name']: item for item in release['assets']}
token = subprocess.check_output(['gh', 'auth', 'token'], text=True).strip()


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None


def remote(name):
    entry = assets[name]
    request = Request(entry['url'], headers={'Accept': 'application/octet-stream',
                                             'Authorization': f'Bearer {token}', 'User-Agent': 'WWO-Asset-Recovery'})
    try:
        return build_opener(NoRedirect()).open(request, timeout=30)
    except HTTPError as error:
        assert error.code == 302 and error.headers.get('Location'), (name, error.code)
        return error.headers['Location']


def get(name):
    url = remote(name)
    response = urlopen(url, timeout=45) if isinstance(url, str) else url
    with response:
        payload = response.read()
    assert len(payload) == assets[name]['size'], name
    (restored / name).write_bytes(payload)
    return payload


def qpk_samples(name, path, tiles):
    length = path.stat().st_size
    assert length == assets[name]['size'] and assets[name]['state'] == 'uploaded', name
    url = remote(name)
    assert isinstance(url, str), (name, 'release redirect expected')
    checked = []
    with path.open('rb') as source:
        _, z, nx, ny = struct.unpack('<8sIII', source.read(20))
        index = struct.unpack(f'<{nx*ny+1}Q', source.read(8 * (nx*ny+1)))
        ranges = [(0, index[0], 'header/index')]
        for x, y in tiles:
            row = y*nx + x
            ranges.append((index[row], index[row+1], f'{z}/{x}/{y}'))
        for start, stop, label in ranges:
            source.seek(start)
            request = Request(url, headers={'Range': f'bytes={start}-{stop-1}'})
            with urlopen(request, timeout=45) as response:
                assert response.status == 206 and response.headers['Content-Range'] == f'bytes {start}-{stop-1}/{length}', (name, label)
                assert response.read(stop-start) == source.read(stop-start), (name, label)
            checked.append(label)
    print(name, length, ', '.join(checked), flush=True)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'input':
        sampled = get('z7-detail-scar-add-7.13.json.gz')
        (restored / 'scar-add.json').write_bytes(gzip.decompress(sampled))
        print('SCAR ADD input restored', len(sampled), flush=True)
    else:
        qpk_samples('z6-detail-6.qpk', archive / 'z6-detail-6.qpk',
                    [(0, 0), (64, 32), (4, 62), (45, 61), (126, 59), (89, 56), (127, 63)])
        for name in ('z6-detail-index.json', 'z6-detail-global.json', 'z6-detail-sample-plan.json'):
            assert get(name) == (archive / name).read_bytes(), name
            print(name, assets[name]['size'], flush=True)
        name = 'z6-detail-6.qpk'
        size = 8 * 1024**2
        url = remote(name)
        started = monotonic()
        with urlopen(Request(url, headers={'Range': f'bytes=0-{size-1}'}), timeout=25) as response:
            assert response.status == 206 and response.headers['Content-Range'] == f'bytes 0-{size-1}/{assets[name]["size"]}'
            payload = response.read(size)
        with (archive / name).open('rb') as source:
            assert payload == source.read(size)
        elapsed = monotonic() - started
        (restored / (name + '.part')).write_bytes(payload)
        print(f'QPK restore sampling: {size} bytes in {elapsed:.1f} s ({size / 1024**2 / elapsed:.2f} MiB/s)', flush=True)
