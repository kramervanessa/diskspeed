#!/usr/bin/env bash
# Missing dependencies are installed automatically on Ubuntu/Debian and Fedora.
# Usage: ./diskspeed.sh [target-directory]
# Optional: SECONDS_PER_TEST=60 ./diskspeed.sh /mnt/data
set -Eeuo pipefail

target=${1:-.}
duration=${SECONDS_PER_TEST:-30}
if [[ ! $duration =~ ^[0-9]+$ ]] || (( duration < 5 || duration > 600 )); then
  echo 'SECONDS_PER_TEST must be between 5 and 600.' >&2
  exit 1
fi
# Package names are the same on Fedora and Ubuntu/Debian.
packages=()
command -v fio >/dev/null 2>&1 || packages+=(fio)
command -v python3 >/dev/null 2>&1 || packages+=(python3)
command -v awk >/dev/null 2>&1 || packages+=(gawk)
command -v hostname >/dev/null 2>&1 || packages+=(hostname)
for tool in mktemp df tail rm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    packages+=(coreutils)
    break
  fi
done
if (( ${#packages[@]} > 0 )); then
  if command -v dnf >/dev/null 2>&1; then
    manager=dnf
  elif command -v apt-get >/dev/null 2>&1; then
    manager=apt-get
  else
    printf 'Automatic installation requires dnf (Fedora) or apt-get (Ubuntu/Debian).\nMissing packages: %s\n' "${packages[*]}" >&2
    exit 1
  fi
  privilege=()
  if (( EUID != 0 )); then
    if ! command -v sudo >/dev/null 2>&1; then
      echo 'To install dependencies, run this script as root or install sudo.' >&2
      exit 1
    fi
    privilege=(sudo)
  fi
  printf 'Installing missing packages using %s: %s\n' "$manager" "${packages[*]}"
  if [[ $manager == apt-get ]]; then
    "${privilege[@]}" apt-get update
    "${privilege[@]}" apt-get install -y "${packages[@]}"
  else
    "${privilege[@]}" dnf install -y "${packages[@]}"
  fi
  hash -r
fi
for tool in fio python3 mktemp df awk hostname tail rm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Required program still missing after installation: %s\n' "$tool" >&2
    exit 1
  fi
done
if [[ $(fio --version) != fio-* ]]; then
  echo 'The installed fio is not the Flexible I/O Tester.' >&2
  exit 1
fi
if [[ ! -d $target || ! -w $target ]]; then
  echo "Target directory does not exist or is not writable: $target" >&2
  exit 1
fi
target=$(cd -- "$target" && pwd -P)
available=$(df -Pk -- "$target" | awk 'END {print $4}')
if [[ ! $available =~ ^[0-9]+$ ]] || (( available < 9437184 )); then
  echo 'At least 9 GiB of free space is required.' >&2
  exit 1
fi

testdir=$(mktemp -d -- "$target/.diskspeed.XXXXXXXX")
cleanup() {
  local result=$?
  trap - EXIT
  if rm -rf -- "$testdir"; then
    printf '\nTest files removed.\n'
  else
    printf '\nCleanup failed: %s\n' "$testdir" >&2
    result=1
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
export DISKSPEED_COLOR=0
if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
  export DISKSPEED_COLOR=1
fi

printf 'Quick disk benchmark · %s\nTarget: %s\n' "$(hostname)" "$target"
printf '8 GiB test file · 6 tests of %s s (+ 3 s warm-up each) · additional 20 s fsync test\n' "$duration"

run_fio() {
  local name=$1 mode=$2 block=$3 depth=$4
  shift 4
  local engine=libaio direct=1
  if [[ $name == fsync ]]; then
    engine=psync
    direct=0
  fi
  if ! fio --name="$name" --filename="$testdir/data" --size=8G \
      --rw="$mode" --bs="$block" --ioengine="$engine" --direct="$direct" \
      --iodepth="$depth" --numjobs=1 --refill_buffers=1 \
      --group_reporting --lat_percentiles=1 --percentile_list=99 \
      --output-format=json --output="$testdir/$name.json" "$@" \
      >"$testdir/error.log" 2>&1; then
    printf '\nTest failed (%s):\n' "$name" >&2
    tail -n 12 "$testdir/error.log" >&2
    [[ ! -s $testdir/$name.json ]] || tail -n 12 "$testdir/$name.json" >&2
    exit 1
  fi
}

printf 'Preparing …\n'
run_fio prepare write 1M 16 --end_fsync=1
for spec in 'seqread read 1M 16' 'seqwrite write 1M 16' \
            'read1 randread 4k 1' 'write1 randwrite 4k 1' \
            'read32 randread 4k 32' 'write32 randwrite 4k 32'; do
  read -r name mode block depth <<< "$spec"
  printf '  %-9s …\r' "$name"
  run_fio "$name" "$mode" "$block" "$depth" \
    --runtime="$duration" --time_based --ramp_time=3 --bwavgtime=1000
done
printf '  fsync     …\r'
run_fio fsync write 4k 1 --fsync=1 --end_fsync=1 \
  --runtime=20 --time_based --ramp_time=3 --bwavgtime=1000
printf '                     \r'

python3 - "$testdir" <<'PY'
import json
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
color = os.environ.get('DISKSPEED_COLOR') == '1'

def load(name, direction):
    obj = json.loads((root / (name + '.json')).read_text())
    jobs = obj['jobs']
    if any(job.get('error', 0) for job in jobs):
        raise SystemExit('fio reported an error: ' + name)
    return jobs[0][direction]

def latency(stats, percentile=False):
    for unit, divisor in [('ns', 1e6), ('us', 1e3), ('ms', 1)]:
        record = stats.get('lat_' + unit)
        if record is not None:
            value = (min(record['percentile'].items(),
                         key=lambda item: abs(float(item[0]) - 99))[1]
                     if percentile else record['mean'])
            return value / divisor
    raise SystemExit('Unknown fio latency format.')

def number(value, decimals=0):
    return f'{value:,.{decimals}f}'

def row(label, value, display, bad, good, lower=False):
    if lower:
        level = 2 if value <= good else 0 if value > bad else 1
    else:
        level = 2 if value >= good else 0 if value < bad else 1
    rating = ['POOR', 'FAIR', 'GOOD'][level]
    text = f'{label:<29} {display:>15}  {rating}'
    print((f'\033[{[31, 33, 32][level]}m{text}\033[0m') if color else text)

print('\nResults – general guidelines for SSD and cloud VM storage\n')
for name, direction, label in [('seqread', 'read', 'Sequential read (QD16)'),
                                ('seqwrite', 'write', 'Sequential write (QD16)')]:
    stats = load(name, direction)
    speed = stats['bw_bytes'] / 1e6
    row(label, speed, f'{number(speed)} MB/s', 200, 1000)
for direction, label in [('read', 'Read'), ('write', 'Write')]:
    stats = load(direction + '32', direction)
    iops = stats['iops']
    row(label + ' 4K IOPS (QD32)', iops, number(iops), 10000, 50000)
    stats = load(direction + '1', direction)
    mean, p99 = latency(stats), latency(stats, True)
    row(label + ' mean latency (QD1)', mean, f'{number(mean, 3)} ms', 2, 0.5, True)
    row(label + ' P99 latency (QD1)', p99, f'{number(p99, 3)} ms', 10, 2, True)
print('\nGreen/GOOD: ≥1,000 MB/s, ≥50,000 IOPS, mean ≤0.5 ms, P99 ≤2 ms.')
print('Red/POOR: <200 MB/s, <10,000 IOPS, mean >2 ms, P99 >10 ms.')
print('Yellow/FAIR in between. No overall score; requirements vary.')
print('\nDurable writes – 4K sequential, QD1, fsync after every write:')
write = load('fsync', 'write')
sync = load('fsync', 'sync')
if sync.get('total_ios', 0) <= 0 or write.get('runtime', 0) <= 0:
    raise SystemExit('No fsync operations were measured; no valid rating is available.')
cycles = sync['total_ios'] * 1000 / write['runtime']
mean, p99 = latency(sync), latency(sync, True)
row('Write + fsync per second', cycles, number(cycles), 100, 1000)
row('fsync mean latency', mean, f'{number(mean, 3)} ms', 10, 1, True)
row('fsync P99 latency', p99, f'{number(p99, 3)} ms', 50, 5, True)
print('fsync guidelines, green: ≥1,000/s, mean ≤1 ms, P99 ≤5 ms;')
print('red: <100/s, mean >10 ms, P99 >50 ms; yellow in between.')
print('Rate counts completed write+fsync cycles; latencies cover fsync only.')
print('Measures synchronous writes, not overall database performance.')
print('\nPerformance stability across one-second intervals:')
for name, direction, label in [
    ('seqread', 'read', 'Sequential read'),
    ('seqwrite', 'write', 'Sequential write'),
    ('read1', 'read', 'Read 4K QD1'),
    ('write1', 'write', 'Write 4K QD1'),
    ('read32', 'read', 'Read 4K QD32'),
    ('write32', 'write', 'Write 4K QD32'),
    ('fsync', 'write', 'Write + fsync QD1'),
]:
    stats = load(name, direction)
    average = stats.get('bw_mean', 0)
    samples = stats.get('bw_samples', 0)
    if average <= 0 or samples < 5:
        print(f'{label:<29} UNAVAILABLE – insufficient samples')
        continue
    variation = 100 * stats['bw_dev'] / average
    minimum = 100 * stats['bw_min'] / average
    level = 0 if variation > 25 or minimum < 50 else (2 if variation <= 10 and minimum >= 80 else 1)
    rating = ['UNCERTAIN', 'VARIABLE', 'STABLE'][level]
    text = (f'{label:<29} {rating:<11} '
            f'Variation {number(variation, 1)}% · Minimum {number(minimum, 0)}% of mean')
    print(f'\033[{[31, 33, 32][level]}m{text}\033[0m' if color else text)
print('Green: variation ≤10% and minimum ≥80% of mean.')
print('Red/uncertain: variation >25% or minimum <50%; otherwise yellow.')
print('Variation = standard deviation / mean. Guidelines, not guarantees.')
print('Repeat UNCERTAIN tests. P99 describes the slower end of individual requests.')
print('P99: 99% of requests complete within this time. QD: outstanding requests.')
print('Only the fsync test requests durable confirmation of every write from the storage system.')
print('Not a power-loss test. Provider caches and bursts may affect short benchmarks.')
PY
