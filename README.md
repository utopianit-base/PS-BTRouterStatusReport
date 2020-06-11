# PS-BTRouterStatusReport
Quick PowerShell script to grab the XML from the BT SmartHub (2) status page and do a SpeedTest, then output the stats to a CSV file for reporting. Designed for BT SmartHub v2 and VDSL, but this can undoubtedly be modified for others

CREDITS: Some SpeedTest Code by Kelvin Tegelaar from http://www.cyberdrain.com/

Run the script in the current folder and grab the status XML from the BT router to find the sync speeds to start with.
Next it'll download the speedtest.ZIP from https://bintray.com/ookla/download/download_file?file_path=ookla-speedtest-1.0.0-win64.zip, extract and execute it to get JSON values of the speed test.

Only tested on Windows 10 but would run on Windows Server 2016/2019 quite happily.

Can be scheduled to run every hour or every few hours so that you can report on changes to download and upload speeds and changes in sync values where the router is restarted or after a disconnection event.

CSV can then be opened in Excel and graphed if required or put into Grafana or some web dashboard.

Use and change as you wish but please give credit where appropriate.
