Standalone ZFTS.

Install the zsiglib, zcomp, and zfts rpms on the target sensor and ground
 server using rpm, yum, or dnf. 

To execute ZFTS through zcomp use the config files provided.
There are 2 files 'zfts_zcomp_gnd.ini' and 'zfts_zcomp_air.ini'
The air cfg is for use on the sensor.

Important zfts_zcomp_air.ini cfg settings.

`ZC_OUTPUT_RATE=3000000`  This setting set the bits per second for the uplink
                          is allowed to use.

`FTS_MAX_XFERS=2`   This setting sets the max number of parallel transfers.

`FTS_IN_DIR=/tmp/send1`  This setting set the dir ZFTS monitors for files to be
                         transferred.  It creates 5 directories labeled 1-5 for 
                         transferring files at different priorities.
                         priority 1 is the highest, 5 is the lowest.  If files
                         are placed directly in the input dir, they will get 
                         the default priority of 3.

`ZC_IN_ADDRESS=0.0.0.0:50001` Set the UDP  address and port to listen for 
                              messages from the ground.

Important zfts_zcomp_gnd.ini cfg settings.

`ZC_OUT_ADDRESS=pr13:50001`  This setting tells the ground where to reach
                             the sensor.  The air is set up to listen to 
                             udp port 50001 as seen above.

`FTR_OUT_DIR=/tmp/out2`      This set the output directory for completed 
                             file transfers.

`FTR_CC_ADDR=0.0.0.0:19012`  This setting sets what address and port to host
                             the zfts web interface.  The web page provides
                             status of file transfers and the ability to change
                             priority, pause and cancel transfers.

To run the applications on the sensor execute the programs below
in two different shells

[user@sensor zfts]$ /opt/prgsnap/bin/zcompd -c zfts_zcomp_air.ini 
[user@sensor zfts]$ /opt/prgsnap/bin/zfts -c zfts_zcomp_air.ini 

To run the applications on the ground execute the programs below
in two different shells

[user@ground zfts]$ /opt/prgsnap/bin/zcompd -c zfts_zcomp_gnd.ini 
[user@ground zfts]$ /opt/prgsnap/bin/zfts -c zfts_zcomp_gnd.ini 


