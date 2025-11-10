#!/usr/bin/env bash

# Input:
# - IBS report file in json format. This report should contain data for only 1 intercept.
# Output:
# - SG5302 intercept report. The report will be written to the current working directory or the
#   the directory specified with the '-o' option (see below). The report name will use the following convention:
#   'sg5302_report_' + str_time.strftime("%Y%m%d_%H%M%S") + '.txt'
# Usage (linux):
# - usage: IBSToSG5302.sh [-h] [-i IBS_FILE] [-o OUTPUT_DIRECTORY]
# Program arguments:
# - Required: ibs_file           - IBS report file that will be converted
# - Optional: output_directory   - Directory where SG5302 report will be written to    - Default: current working directory

# get full absolute path to the python virtual environment
full_path=$(readlink -f -- $0)
script_dir=$(dirname $full_path)
# source the activatation script for the virtual environment
source $script_dir/.venv/bin/activate
# run the converter python script with the supplied arguments
python $script_dir/IBSToSG5302.py "$@"