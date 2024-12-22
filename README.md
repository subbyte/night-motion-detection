# Night Motion Detection

Use case: detecting mouse at night.

Although many NVR systems like [zoneminder](https://zoneminder.com/) and [Frigate](https://frigate.video/) has motion detection functions, the functions have little space to tune/customize and do not detect small objects effectively.

[dvr-scan](https://dvr-scan.readthedocs.io) is a simple OpenCV-based detector that can be easily customized with parameters or code modification to detect small object motion. It also uses background substraction for more reliable motion detection than [Friagte](https://frigate.video/).

This script uses `dvr-scan` with GPU acceleration to detect small object motion at night. It recognizes night vision videos (grayscale) from all NVR video clips and performs detection and false positive elimination. It reduces false positive by 1000x---about 30 seconds to inspect compared to 8 hours security camera recording per night.
