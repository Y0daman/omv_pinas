# HW-notes: Freenove FNK0107 + Raspberry Pi 5 + 4x NVMe

This document captures practical hardware facts for this NAS build.

## Sources

- FNK0107 docs index: https://docs.freenove.com/projects/fnk0107/en/latest/index.html
- FNK0107 Chapter 1 (components): https://docs.freenove.com/projects/fnk0107/en/latest/fnk0107/codes/tutorial/1_Introduction_to_Main_Components_.html

## Relevant points for this build

- The product is built for Raspberry Pi 5.
- Freenove documents support for 1/2/4-slot NVMe adapters.
- The quad adapter supports up to 4 NVMe SSDs simultaneously.
- NVMe slots are M.2 M-Key and support 2230/2242/2260/2280 sizes.
- Documentation recommends a strong PSU (5.1V/5A) for stability.
- Additional NVMe-side power input is noted to avoid instability.

## Practical design implications

- Expect shared PCIe bandwidth across multiple drives (RPi5 has a PCIe x1 upstream path).
- Thermal management is critical: active cooling, airflow, and monitoring are required.
- Prioritize data protection (backup) over raw peak performance.

## Post-assembly verification

Run on the Pi:

```bash
lsblk -o NAME,SIZE,MODEL,TYPE,MOUNTPOINT
dmesg | grep -Ei "nvme|pcie|aer|error"
sudo smartctl --scan
```

If drives are missing or links reset, check cabling, power, and cooling first.
