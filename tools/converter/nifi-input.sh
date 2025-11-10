#!/usr/bin/env bash

# Input:
#    read from stdin (from nifi)
# Output:
# - SG5302 intercept report. The report will be written to the current working directory or the
#   the directory specified with the '-o' option (see below). The report name will use the following convention:
#   'sg5302_report_' + str_time.strftime("%Y%m%d_%H%M%S") + '.txt'

# get full absolute path to the python virtual environment
full_path=$(readlink -f -- $0)
script_dir=$(dirname $full_path)
# source the activatation script for the virtual environment
source $script_dir/.venv/bin/activate
# run the converter python script with the supplied arguments

TMPFILE=$(mktemp)

STDIN=$(cat -)
echo $STDIN > ${TMPFILE}

python $script_dir/IBSToSG5302.py -i ${TMPFILE} -o /mission-share/tools/converter/tmp
rm ${TMPFILE}
