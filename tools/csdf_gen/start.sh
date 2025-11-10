#!/bin/bash

#######
#
#  this script is a placeholder for a much more complicated
#  script that lives in the target deployment environment.
#
#######

HOME=/mission-share/tools/csdf_gen/

LOG=${HOME}/csdf_gen.log

cd ${HOME}

echo pwd >>"$LOG" 2>&1

inpath=${1}
basename=${2}

echo $inpath >> "$LOG" 2>&1
echo $basename >> "$LOG" 2>&1

srifile=${inpath}${basename}.sri
pcmfile=${inpath}${basename}.pcm

echo $srifile >> "$LOG" 2>&1
echo $pcmfile >> "$LOG" 2>&1

if [ -f "$srifile" ] && [ -f "$pcmfile" ]; then

	echo "both the sri and pcm files have been found"  >> "$LOG" 2>&1

	cat $srifile $pcmfile > ${HOME}/${basename}.csdf

#	rm $srifile
#	rm $pcmfile

fi

