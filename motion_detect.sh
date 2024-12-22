#!/usr/bin/env sh
#
# Night Motion Detection
# - scan NVR videos on specific date
# - process ones with night vision (grayscale)
# - motion detection using dvr-scan
# - eliminate false positives
#   - too short event (dvr-scan min-event-length does not work well)
#   - motion with light on
#
# Requirements:
# - pacman: imagemagick
# - pacman: ffmpeg
# - dvr-scan with OpenCV CUDA
#   - pacman: python-opencv-cuda
#   - pip: dvr-scan[opencv]

PYTHON_VENV_PATH=~/venv/dvr-scan
INPUT_DIRECTORY=/mnt/watcher/monitors/tapo
OUTPUT_BASE_DIRECTORY=/mnt/watcher/monitors/tapo-detect

START_CLOCK=22  # start on a given day's 10PM
END_CLOCK=08    # end on the next day's 8AM

# 4 seconds: dvr_scan has 1.5s (pre-rec) and 2s (post-rec) for each event
EVENT_DURATION_THRESHOLD=4

# dvr-scan use OpenCV to generate .avi files
# Which can have saturation>0 even for grayscale videos
# Use a threshold to filter colorful clips out
COLOR_SATURATION_THRESHOLD=0.07

usage() {
    echo "Usage: $0 <date>"
    echo "  <date> is %Y-%m-%d format, from the night of the day to dawn of the next day"
}

_FRAME_FIRST=$(mktemp --suffix=.png)
_FRAME_LAST=$(mktemp --suffix=.png)

extract_saturation() {
    # Extract saturation of input image $1
    magick "$1" -colorspace HSL -format "%[fx:mean.g]" info:
}

is_video_colorful() {
    # Check if video $1 is colorful
    # Use return code 0 (colorful) and 1 (grayscale)
    _t=$COLOR_SATURATION_THRESHOLD

    # Extract first frame
    # Store saturatoin into $sf
    ffmpeg -i "$1" -vf "select=eq(n\,0)" -vsync vfr -vframes 1 "$_FRAME_FIRST" -y > /dev/null 2>&1
    _sf=$(extract_saturation $_FRAME_FIRST)

    # Extract first frame of last second
    # Store saturatoin into $sl
    ffmpeg -sseof -1 -i "$1" -vf "select=eq(n\,0)" -vsync vfr -vframes 1 "$_FRAME_LAST" -y > /dev/null 2>&1
    _sl=$(extract_saturation $_FRAME_LAST)

    echo "Saturations: $_sf, $_sl"

    # Compute return code
    perl -e "exit(($_sf > $_t && $_sl > $_t) ? 0 : 1)"
}

# init
. $PYTHON_VENV_PATH/bin/activate

day=$1
if ! date -d $day > /dev/null 2>&1; then usage; exit 1; fi

idir=$INPUT_DIRECTORY
if [ -z "$idir" ] || [ ! -d "$idir" ]; then "Error: input directory"; exit 1; fi

odir=$OUTPUT_BASE_DIRECTORY/$day
if [ -d "$odir" ]; then echo "Error: output directory exists"; exit 1; fi
if ! mkdir -p "$odir"; then echo "Error: cannot create output directory"; exit 1; fi

day2=$(date -I -d "$day + 1 day")

for video_file in "$idir"/*; do
    input_filename=$(basename "$video_file")
    if [ "$input_filename" \< "$day---$START_CLOCK" ] || [ "$input_filename" \> "$day2---$END_CLOCK" ]; then continue; fi

    echo "Check $input_filename ..."
    if is_video_colorful "$video_file"; then continue; fi

    echo "Process video $input_filename ..."
    dvr-scan -b MOG2_CUDA -t 0.5 -i $video_file -d $odir

    video_time="${input_filename%.*}"
    for output_file in "$odir"/"$video_time"*; do
        if ! [ -f "$output_file" ]; then continue; fi
        echo "Check video clip $output_file ..."

        duration=$(ffprobe -v error -select_streams v:0 -show_entries format=duration -of csv=p=0 $output_file | awk '{print int($1)}')
        if [ "$duration" -lt "$EVENT_DURATION_THRESHOLD" ]; then
            echo "Delete short clip $output_file : $duration sec"
            rm $output_file
            continue
        fi

        if is_video_colorful "$output_file"; then
            echo "Delete colorful clip $output_file"
            rm $output_file
        fi
    done
done
