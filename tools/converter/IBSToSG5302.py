#!/usr/bin/env python

# Requirements:
# - The included python virtual environment must be used. You can activate it with the following command:
#   source .venv/bin/activate
# Input:
# - IBS report file in json format. This report should contain data for only 1 intercept.
# Output:
# - SG5302 intercept report. The report will be written to the current working directory or the
#   the directory specified with the '-o' option (see below). The report name will use the following convention:
#   'sg5302_report_' + str_time.strftime("%Y%m%d_%H%M%S") + '.txt'
# Usage (linux):
# - python IBSToSG5302.py [-h] [-o OUTPUT_DIRECTORY] ibs_file
# Program arguments:
# - Required: ibs_file           - IBS report file that will be converted
# - Optional: output_directory   - Directory where SG5302 report will be written to    - Default: current working directory

try:
    import os
    import argparse
    import errno
    import traceback
    import SG5302
    from IBSReader import IBSReader
except ImportError as e:
    traceback.print_exception(e)
    print()
    print("Please ensure the python virtual environment is activated with the following command:")
    script_dir = os.path.dirname(os.path.realpath(__file__))
    print("source " + script_dir + "/.venv/bin/activate")
    exit(1)

# configurable report parameters that will get written to the SG5302 report
def getReportParams(report_type):
    params = dict()
    params["enable_ftp_transfer"] = True
    params["source_id"] = "AAAA"
    params["collector_diagraph"] = "ZZ"
    params["routing"] = "ZZ"
    params["platform_symbol"] = "J"
    params["mission_num"] = "N488CR"
    params["file_distribution_indicator"] = "ZZZ"
    params["daily_report_counter"] = "01"
    return params

parser = argparse.ArgumentParser("IBSToSG5302.py", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-i", "--ibs-file", help="Path to IBS file", type=str)
parser.add_argument("-o", "--output-directory", help="Path to write SG5302 report (default: Current working directory)", type=str, default=argparse.SUPPRESS)
args = parser.parse_args()
if not hasattr(args, "output_directory"):
    args.output_directory = os.getcwd()

if not os.path.isfile(args.ibs_file):
    raise FileNotFoundError(errno.ENOENT, os.strerror(errno.ENOENT), args.ibs_file)

sg5302_data = IBSReader(args.ibs_file)
if len(sg5302_data) == 0:
    print("ERROR: No data found in IBS report. Could not create SG5302 report")
    exit(2)

files = SG5302.process([sg5302_data], "", args.output_directory, getReportParams(""))
for file in files:
    print("SG5302 file wrote to:", file)
