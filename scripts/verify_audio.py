import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import time
import wave

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / '.build' / 'fixtures'
RESULTS = ROOT / '.build' / 'verification'
MODEL = Path(os.environ.get('FLOW_MODEL_DIR', ROOT / '.build/models/Qwen3-ASR-1.7B-8bit'))
with (ROOT / 'Resources/Info.plist').open('rb') as metadata:
    APP_NAME = plistlib.load(metadata)['CFBundleName']
ENGINE = ROOT / 'dist' / f'{APP_NAME}.app' / 'Contents/MacOS/flow-qwen'
GERMAN = 'Bitte verschiebe unseren Termin auf Donnerstag um fünfzehn Uhr. Ich schicke dir die Unterlagen morgen.'
ENGLISH = 'Please move our meeting to Thursday at three in the afternoon. I will send you the documents tomorrow.'


def concatenate(inputs, destination):
    with wave.open(str(destination), 'wb') as output:
        for index, source in enumerate(inputs):
            with wave.open(str(source), 'rb') as clip:
                if index == 0:
                    output.setparams(clip.getparams())
                if clip.getframerate() != 16000 or clip.getnchannels() != 1 or clip.getsampwidth() != 2:
                    raise ValueError('Fixture must be 16 kHz mono PCM16')
                output.writeframes(clip.readframes(clip.getnframes()))


def tokens(text):
    return re.findall(r'\w+', text.casefold().replace('15', 'fünfzehn'))


def word_error_rate(reference, actual):
    expected, received = tokens(reference), tokens(actual)
    row = list(range(len(received) + 1))
    for i, word in enumerate(expected, 1):
        next_row = [i]
        for j, output in enumerate(received, 1):
            next_row.append(min(next_row[-1] + 1, row[j] + 1, row[j - 1] + (word != output)))
        row = next_row
    return row[-1] / len(expected)


def wait_for_file(path, worker, started, timeout=180):
    while not path.exists():
        if worker.poll() is not None:
            raise RuntimeError(f'Engine exited with {worker.returncode}')
        if time.monotonic() - started >= timeout:
            raise TimeoutError(f'Engine timed out waiting for {path.name}')
        time.sleep(0.05)


def verify_worker(checks):
    measurements = []
    with tempfile.TemporaryDirectory(prefix='flow-audio-check-') as temporary:
        ready = Path(temporary) / 'ready'
        with (RESULTS / 'worker.log').open('w') as log:
            started = time.monotonic()
            worker = subprocess.Popen([str(ENGINE), '--worker', str(MODEL), str(ready)],
                                      stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=log, text=True)
            try:
                wait_for_file(ready, worker, started)
                loaded_at = time.monotonic()
                for index, (name, reference, required) in enumerate(checks):
                    output = RESULTS / f'{name}.txt'
                    completion = Path(temporary) / f'{name}.complete'
                    request = {'audio': str(FIXTURES / f'{name}.wav'), 'output': str(output),
                               'completion': str(completion), 'language': 'auto', 'vocabulary': ''}
                    job_started = time.monotonic()
                    worker.stdin.write(json.dumps(request) + '\n')
                    worker.stdin.flush()
                    wait_for_file(completion, worker, job_started)
                    reply = json.loads(completion.read_text())
                    if not reply.get('success'):
                        raise RuntimeError(f'{name}: engine failed')
                    text = output.read_text()
                    error_rate = word_error_rate(reference, text)
                    missing = set(required) - set(tokens(text))
                    if missing or error_rate > 0.15:
                        raise AssertionError(f'{name}: missing={missing}, WER={error_rate:.3f}, output={text}')
                    measurements.append({'fixture': name, 'source': 'macOS synthesized speech', 'reference': reference,
                        'transcript': text, 'word_error_rate': error_rate,
                        'seconds': round(time.monotonic() - job_started, 2),
                        'load_seconds': round(loaded_at - started, 2) if index == 0 else 0,
                        'peak_mlx_gb': reply.get('peakMLXGB')})
                    print(f'PASS {name}: WER {error_rate:.1%}, {measurements[-1]["seconds"]}s', flush=True)
            finally:
                worker.stdin.close()
                if worker.poll() is None:
                    worker.terminate()
                    try:
                        worker.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        worker.kill()
                        worker.wait()
    return measurements


def main():
    FIXTURES.mkdir(parents=True, exist_ok=True)
    RESULTS.mkdir(parents=True, exist_ok=True)
    if not (MODEL / 'model.safetensors').exists():
        raise RuntimeError('Qwen model missing. Download it in the app or set FLOW_MODEL_DIR.')
    for name, voice, text in [('german', 'Anna', GERMAN), ('english', 'Samantha', ENGLISH)]:
        subprocess.run(['say', '-v', voice, '-o', str(FIXTURES / f'{name}.wav'),
                        '--data-format=LEI16@16000', text], check=True)
    concatenate([FIXTURES / 'german.wav', FIXTURES / 'english.wav'], FIXTURES / 'mixed-de-en.wav')
    concatenate([FIXTURES / 'english.wav', FIXTURES / 'german.wav'], FIXTURES / 'mixed-en-de.wav')
    checks = [
        ('german', GERMAN, ['donnerstag', 'unterlagen']),
        ('english', ENGLISH, ['thursday', 'documents']),
        ('mixed-de-en', GERMAN + ' ' + ENGLISH, ['donnerstag', 'unterlagen', 'thursday', 'documents']),
        ('mixed-en-de', ENGLISH + ' ' + GERMAN, ['donnerstag', 'unterlagen', 'thursday', 'documents']),
    ]
    measurements = verify_worker(checks)
    run = subprocess.run([str(ROOT / '.build/release/FlowCheck'), str(FIXTURES / 'mixed-de-en.wav'),
                          str(ENGINE), str(MODEL), 'auto'], capture_output=True, text=True, timeout=180)
    if run.returncode or not all(word in tokens(run.stdout) for word in ['donnerstag', 'thursday', 'documents']):
        raise AssertionError('Integrated audio conversion/transcription failed: ' + run.stderr)
    warm = subprocess.run([str(ROOT / '.build/release/FlowCheck'), str(FIXTURES / 'german.wav'),
                           str(ENGINE), str(MODEL), 'auto', '2'], capture_output=True, text=True, timeout=240)
    (RESULTS / 'warm-german.log').write_text(warm.stderr)
    transcripts = warm.stdout.strip().splitlines()
    timings = [float(value) for value in re.findall(r'processing=([\d.]+)s', warm.stderr)]
    if warm.returncode or len(transcripts) != 2 or len(timings) != 2:
        raise AssertionError('Warm transcription pipeline failed: ' + warm.stderr)
    for transcript in transcripts:
        if word_error_rate(GERMAN, transcript) > 0.15:
            raise AssertionError('Warm model changed transcription quality: ' + transcript)
    (RESULTS / 'warm-results.json').write_text(json.dumps({
        'fixture': 'german', 'source': 'macOS synthesized speech', 'cold_seconds': timings[0],
        'warm_seconds': timings[1], 'transcripts': transcripts}, indent=2, ensure_ascii=False))
    print(f'WARM PASS: first {timings[0]}s, next {timings[1]}s, quality preserved', flush=True)
    (RESULTS / 'results.json').write_text(json.dumps(measurements, indent=2, ensure_ascii=False))
    print('AUDIO PASS: German, English, both switch directions, integrated pipeline', flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'AUDIO FAIL: {error}', file=sys.stderr)
        sys.exit(1)
