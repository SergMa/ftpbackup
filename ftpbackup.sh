#!/bin/sh
################################################################
# ftpbackup.sh                                                 #
#                                                              #
# This script copies recursively and incrementally all files   #
# from selected folder on local machine to defined FTP-server. #
#                                                              #
# This script:                                                 #
# - is based on ncftpput and ncftpls utilites, that can be     #
#   downloaded from  http://www.ncftp.com/download/            #
# - does not use 'Recursive' mode of ncftpls (this mode does   #
#   not work with some FTP-servers)                            #
# - was written to work even in minimalistic shell of Busybox  #
# - checks if previously started ftpbackup.sh process finished #
#                                                              #
# Usage:                                                       #
# - set actual values in PARAMETERS section of this script     #
# - run script (manually or automatically)                     #
#                                                              #
# Known bugs:                                                  #
# - it seems, that this script unexpectedly works with file    #
#   links located in folder/subfolder to be backuped.          #
#                                                              #
# (c) 2017 Mashkin S.V. / mashkh@yandex.ru                     #
################################################################

echo
echo "Making backup on ftp-server..."

################################################################
# PARAMETERS                                                   #
################################################################

# Note: local IP address may be used as name of destination folder
# for backup on remote FTP-server.
#strLocalIP=`ifconfig eth0 | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'`
strLocalIP="192.168.1.123"

localdir="/localfolder"
remotedir="/"
backupip="192.168.1.122"
backupport="21"
backupuser="user"
backuppass="1234"

################################################################
# INITIALIZATION                                               #
################################################################

#### Check if backuping is in progress

#Note: $$ returns PID of current process (shell script)

if [ `pidof -s -o $$ ftpbackup.sh` ] ; then
    echo "Error: another copy of ftpbackup.sh is working"
    exit 0
fi

#### Show ftp-backup settings
echo "----------------------------"
echo "FTP-backup settings:"
echo "localdir=\"$localdir\""
echo "remotedir=\"$remotedir/$strLocalIP\""
echo "backupip=\"$backupip\""
echo "backupport=\"$backupport\""
echo "backupuser=\"$backupuser\""
echo "backuppass=\"$backuppass\""
echo "----------------------------"

echo "FTP-backup process was started"

################################################################
# SYNCHRONIZE LOCAL FILES WITH ONES ON REMOTE FTP-SERVER       #
################################################################

error=""

numLocalFiles=0
numUploadedFiles=0

#### Get number of files to upload
echo "Counting files in local $localdir ..."

for f in $(find $localdir)
do
    if [ -d "$f" ] ; then
        :
    else
        numLocalFiles=$((numLocalFiles+1))
    fi
done

#### Create root directory on remote FTP-server if does not exist
echo "check/create folder $strLocalIP on ftp-server..."

ncftpls -l -u "$backupuser" -p "$backuppass" -P "$backupport" "ftp://$backupip$remotedir/$strLocalIP"
status=$?

if [ $status -eq 3 ] ; then
    #### root folder does not exist
    rm -fR "/tmp/$strLocalIP"
    mkdir "/tmp/$strLocalIP"
    mkdir "/tmp/$strLocalIP$localdir"
    
    ncftpput -R -v -u "$backupuser" -p "$backuppass" -P $backupport "$backupip" "$remotedir" "/tmp/$strLocalIP"
    status=$?
    if [ $? -ne 0 ] ; then
        error="Could not create folder /$strLocalIP on FTP-server"
        echo $error
    else
        rm -fR "/tmp/$strLocalIP"
        echo "Ok: folder /$strLocalIP created on ftp-server"
    fi
elif [ $status -eq 0 ] ; then
    echo "Ok: folder $strLocalIP already exists on ftp-server"
else
    error="Could not get list of files from FTP-server"
    echo $error
fi

#### Scan over all local files and check if they are on FTP-server, if not - upload them to FTP-server

echo "Scan files in local $localdir ..."

lastdir=""
currdir=""
dirlist=""

for f in $(find $localdir)
do
    #check for errors on previous stage
    if [ "$error" ] ; then
        break
    fi

    parentdir="$(dirname "$f")"

    if [ -d "$f" ] ; then
        
        currdir="$f"
        
        #check if folder has been already uploaded
        if [ "$lastdir" ] ; then
            if `echo "$f" | grep "$lastdir/" 1>/dev/null` ; then
                echo "folder $f already uploaded to ftp-server"
                uploaded="true"
            else
                uploaded="false"
            fi
        else
            uploaded="false"
        fi
                
        if [ "$uploaded" == "false" ] ; then
            dirlist=`ncftpls -u "$backupuser" -p "$backuppass" -P "$backupport" "ftp://$backupip/$remotedir$strLocalIP$f"`
            status=$? 
            if [ $status -eq 0 ] ; then
                echo "folder $f already exists on ftp-server"
            elif [ $status -eq 3 ] ; then
                ncftpput -R -v -u "$backupuser" -p "$backuppass" -P "$backupport" "$backupip" "/$remotedir/$strLocalIP/$parentdir" "$f"
                status=$? 
                if [ $status -ne 0 ] ; then
                    error="Could not upload folder to ftp-server"
                    echo $error
                    break
                fi
                lastdir="$f"
            else
                error="Could not upload folder to ftp-server"
                echo $error
                break
            fi
        
        fi
       
    else
        #numLocalFiles=$((numLocalFiles+1))
    
        #check if file is in current folder list
        inlist="false"
        for d in $dirlist
        do
            if [ "$currdir/$d" == "$f" ] ; then
                inlist="true"
                break
            fi
        done
        
        if [ "$inlist" == "true" ] ; then
            echo "file $f exists on ftp-server"
        else
            ################################
            #check if file have been uploaded with already uploaded folder
            if [ "$lastdir" ] ; then
                if `echo "$f" | grep "$lastdir/" 1>/dev/null` ; then
                    echo "file $f already uploaded to ftp-server"
                    uploaded="true"
                else
                    uploaded="false"
                fi
            else
                uploaded="false"
            fi
    
            if [ "$uploaded" == "true" ] ; then
                #count file in already uploaded folder
                numUploadedFiles=$((numUploadedFiles+1))
            else
                ncftpls -l -u "$backupuser" -p "$backuppass" -P "$backupport" "ftp://$backupip/$remotedir/$strLocalIP/$f"
                status=$?
                if [ $status -eq 0 ] ; then
                    echo "file $f already exists on ftp-server"
                elif [ $status -eq 3 ] ; then
                    #file $f does not exist on ftp-server
                    ncftpput -A -v -u "$backupuser" -p "$backuppass" -P "$backupport" "$backupip" "/$remotedir/$strLocalIP/$parentdir" "$f"
                    status=$?
                    if [ $status -eq 0 ] ; then
                        numUploadedFiles=$((numUploadedFiles+1))
                    else
                        error="Could not upload file to ftp-server"
                        echo $error
                        break
                    fi
                else
                    error="Could not upload file to ftp-server"
                    echo $error
                    break
                fi
            fi
            ################################
        fi
    fi
done

echo "Total files: $numLocalFiles"
echo "Uploaded files: $numUploadedFiles"

################################################################
# SHOW BACKUP FINISHED MESSAGE                                 #
################################################################

if [ "$error" ] ; then
    echo "ftp-backup to ftp://$backupip:$backupport has been stopped. $numUploadedFiles of $numLocalFiles files uploaded. Error: $error"
else
    echo "ftp-backup to ftp://$backupip:$backupport has been finished successfully. $numUploadedFiles of $numLocalFiles files uploaded."
fi

echo
exit 0
