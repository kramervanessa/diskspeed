# diskspeed

A short storage benchmark for Ubuntu/Debian and Fedora with colour-coded results.
Missing dependencies are installed automatically using `apt-get` or `dnf`,
as root or through `sudo`.

## Download and run

```bash
curl -fL https://raw.githubusercontent.com/kramervanessa/diskspeed/main/diskspeed.sh -o diskspeed.sh
bash diskspeed.sh
```

To test another drive, specify a directory on that drive:

```bash
bash diskspeed.sh /mnt/data
```

## Optional short test

```bash
bash diskspeed.sh --short
# Or test a specific drive:
bash diskspeed.sh --short /mnt/data
```

The short mode runs all seven workloads with a **1 GiB** test file: six
5-second measurements and a 5-second fsync measurement, each with a 1-second
warm-up. Allow roughly **42 seconds plus file preparation and fio overhead**;
dependency installation and slow storage can take longer. It requires 2 GiB
of free space. Test files are removed as in the full test.

Use this for a quick indication. The smaller file is more susceptible to caches,
and short runs provide fewer latency and stability samples. Compare results
using the same mode; use the full test to investigate inconsistent results.
Running without `--short` keeps the original full test unchanged.
Use `bash diskspeed.sh --help` to display the options.

## Measurements

- An 8 GiB test file, fully written before measurement; at least 9 GiB free space required.
- Six tests, each with 30 seconds of measurement and a 3-second warm-up.
- Sequential reads and writes (1 MiB, QD16).
- Random reads and writes (4 KiB, QD1 and QD32).
- An additional 20-second sequential 4 KiB write test with `fsync` after every write.
- Throughput, IOPS, mean latency and P99 latency.
- Stability across one-second intervals, based on variation and minimum throughput.

Allow approximately four minutes, or longer if preparing the test file takes more time.
Compare machines using the same settings and as little other activity as possible.

To override the duration of the six main tests (in either mode):

```bash
SECONDS_PER_TEST=60 bash diskspeed.sh
```

The fsync test remains at 20 seconds in full mode and 5 seconds in short mode.
Colours are enabled in terminals;
set `NO_COLOR=1` to disable them. Output uses English ASCII text and separate progress lines for compatibility with
serial consoles. Numbers use a decimal point
and commas as thousands separators (for example, `1,315 MB/s` and `0.391 ms`).

## Ratings and limitations

Colour thresholds are general guidelines, explained in the output. There is no
overall score. Provider caches and temporary performance bursts may affect results.
The fsync test measures synchronous writes, not overall database performance.
It does not verify whether hardware honours durability confirmations during an
actual power failure. The fsync latency measures the sync call only; the rate
counts completed write+fsync cycles.

Stability is rated GOOD in green as `STABLE`, yellow as `VARIABLE`, or red as
`UNCERTAIN`. These ratings describe variation during this run, not guaranteed
long-term performance. P99 is the time within which 99% of requests complete.

The script uses its own temporary test file in the selected directory. It removes
the test file and measurement files on completion, errors and normal termination
signals. Automatic cleanup is not possible after a power failure or `kill -9`;
a `.diskspeed.*` directory may remain in those cases.

## Validation

The main benchmarks have been run on Ubuntu. The fsync report was checked using
a short local fio run on macOS. Shell syntax and ShellCheck checks passed.
The apt-get and dnf installation paths were tested with simulated package commands.
A complete Fedora run has not yet been verified.
