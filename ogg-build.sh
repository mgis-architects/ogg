#!/bin/bash
#########################################################################################
## OGG for Oracle Databases
#########################################################################################
# Installs Oracle Goldengate 12.2.1 on an existing Oracle database 
# built via https://github.com/mgis-architects/terraform/tree/master/azure/oracledb
# This script only supports Azure currently, mainly due to the disk persistence method
#
# USAGE:
#
#    sudo ogg-build.sh ~/ogg-build.ini
#
# USEFUL LINKS: 
# 
# docs:    https://docs.oracle.com/goldengate/c1221/gg-winux/docs.htm
# install: https://docs.oracle.com/goldengate/c1221/gg-winux/GIORA/GUID-FBE6775F-A3F8-4765-BEAE-A302C7D8B6F9.htm#GIORA977
#
#########################################################################################

g_prog=ogg-build
RETVAL=0

######################################################
## defined script variables
######################################################
STAGE_DIR=/tmp/$g_prog/stage
LOG_DIR=/var/log/$g_prog
LOG_FILE=$LOG_DIR/${prog}.log.$(date +%Y%m%d_%H%M%S_%N)
INI_FILE=$LOG_DIR/${g_prog}.ini

THISDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCR=$(basename "${BASH_SOURCE[0]}")
THIS_SCRIPT=$THISDIR/$SCR

######################################################
## log()
##
##   parameter 1 - text to log
##
##   1. write parameter #1 to current logfile
##
######################################################
function log ()
{
    if [[ -e $LOG_DIR ]]; then
        echo "$(date +%Y/%m/%d_%H:%M:%S.%N) $1" >> $LOG_FILE
    fi
}

######################################################
## fatalError()
##
##   parameter 1 - text to log
##
##   1.  log a fatal error and exit
##
######################################################
function fatalError ()
{
    MSG=$1
    log "FATAL: $MSG"
    echo "ERROR: $MSG"
    exit -1
}

function mountMedia() {

    if [ -f /mnt/software/ogg4bd12301/V839824-01.zip ]; then
    
        log "mountMedia(): Filesystem already mounted"
        
    else
    
        umount /mnt/software
    
        mkdir -p /mnt/software
        
        eval `grep mediaStorageAccountKey $INI_FILE`
        eval `grep mediaStorageAccount $INI_FILE`
        eval `grep mediaStorageAccountURL $INI_FILE`

        l_str=""
        if [ -z $mediaStorageAccountKey ]; then
            l_str+="mediaStorageAccountKey not found in $INI_FILE; "
        fi
        if [ -z $mediaStorageAccount ]; then
            l_str+="mediaStorageAccount not found in $INI_FILE; "
        fi
        if [ -z $mediaStorageAccountURL ]; then
            l_str+="mediaStorageAccountURL not found in $INI_FILE; "
        fi
        if ! [ -z $l_str ]; then
            fatalError "mountMedia(): $l_str"
        fi

        cat > /etc/cifspw << EOF1
username=${mediaStorageAccount}
password=${mediaStorageAccountKey}
EOF1

        cat >> /etc/fstab << EOF2
//${mediaStorageAccountURL}     /mnt/software   cifs    credentials=/etc/cifspw,vers=3.0,gid=54321      0       0
EOF2

        mount -a
        
        if [ ! -f /mnt/software/ogg12201/V100692-01.zip ]; then
            fatalError "mountMedia(): media missing /mnt/software/ogg12201/V100692-01.zip"
        fi

    fi
    
}

installOGG()
{
    local l_installdir=${oggHome}
    local l_media1=/mnt/software/ogg12201/V100692-01.zip # OGG 12.2 media
    local l_media2=/mnt/software/ogg12201/V138402-01.zip # OGG4BD 12.2 media ... not used here
    local l_tmp_script=$LOG_DIR/$g_prog.installOGG.$$.sh
    local l_tmp_responsefile=$LOG_DIR/$g_prog.installOGG.$$.rsp
    local l_runInstaller_log=$LOG_DIR/$g_prog.installOGG.$$.runinstaller.log
    local l_ogginstall_log=$LOG_DIR/$g_prog.installOGG.$$.OGGinstall.log
    local l_ogg_stage=$STAGE_DIR/ogg1221
    
    if [ ! -f ${l_media1} ]; then
        fatalError "installOGG(): media missing ${l_media1}"
    fi

    eval `grep databaseHome $INI_FILE`
    eval `grep databaseVersion $INI_FILE`
    
    l_str=""
    if [ -z $databaseHome ]; then
        l_str+="databaseHome not found in $INI_FILE; "
    fi
    if [ -z $databaseVersion ]; then
        l_str+="databaseVersion not found in $INI_FILE; "
    elif [ "$databaseVersion" != "ORA12c" -a "$databaseVersion" != "ORA11g" ]; then
        l_str+="databaseVersion must be either ORA12c or ORA11g in $INI_FILE; "
    fi
    if ! [ -z $l_str ]; then
        fatalError "installOGG(): $l_str"
    fi
    
    ################################
    # Generate responsefile
    ################################
    cat > $l_tmp_responsefile << EOFiogg1
DATABASE_LOCATION=${databaseHome}
INSTALL_OPTION=${databaseVersion}
INVENTORY_LOCATION=/u01/app/oracle/oraInventory
MANAGER_PORT=7801
oracle.install.responseFileVersion=/oracle/install/rspfmt_ogginstall_response_schema_v12_1_2
SOFTWARE_LOCATION=${l_installdir}
START_MANAGER=true
UNIX_GROUP_NAME=oinstall
EOFiogg1

    chmod 644 ${l_tmp_responsefile}

    ################################
    # Create script to run as oracle
    ################################
    cat > $l_tmp_script << EOFiogg2
rm -rf $STAGE_DIR
mkdir -p ${l_ogg_stage}
unzip -q -d ${l_ogg_stage} ${l_media1}
cd ${l_ogg_stage}/fbo_ggs_Linux_x64_shiphome/Disk1
./runInstaller -silent -waitforcompletion -responseFile $l_tmp_responsefile |tee $l_runInstaller_log
rm -rf $STAGE_DIR
EOFiogg2

    ################################
    # Run the script
    ################################
    su - oracle -c "bash -x $l_tmp_script" |tee ${l_ogginstall_log}
    
}

function alterOracleProfile() 
{
    cat >> /home/oracle/.bash_profile << EOForacleProfile
    export OGG_HOME=${oggHome}
    export PATH=${oggHome}/bin:\$PATH
    export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:\$LD_LIBRARY_PATH
EOForacleProfile
}

function run()
{
    eval `grep platformEnvironment $INI_FILE`
    eval `grep ogg4bdMgrHost $INI_FILE`
    eval `grep ogg4bdMgrPort $INI_FILE`
	
    if [ -z $platformEnvironment ]; then    
        l_str+="$g_prog.run(): Unknown environment, check platformEnvironment setting in iniFile"
	fi
    if [ $platformEnvironment != "AZURE" ]; then    
        l_str+="$g_prog.run(): platformEnvironment=AZURE is the only valid setting currently"
    fi
    if [ -z $ogg4bdMgrHost ]; then
        l_str+="${g_prog}(): ogg4bdMgrHost not found in $INI_FILE; "
    fi
    if [ -z $ogg4bdMgrPort ]; then
        l_str+="${g_prog}(): ogg4bdMgrPort not found in $INI_FILE; "
    fi
    if ! [ -z $l_str ]; then
        fatalError "$g_prog(): $l_str"
    fi

    oggHome=/u01/app/oracle/product/12.2.1/ogg

    # function calls
    mountMedia
    installOGG
    alterOracleProfile
}


######################################################
## Main Entry Point
######################################################

log "$g_prog starting"
log "STAGE_DIR=$STAGE_DIR"
log "LOG_DIR=$LOG_DIR"
log "INI_FILE=$INI_FILE"
log "LOG_FILE=$LOG_FILE"
echo "$g_prog starting, LOG_FILE=$LOG_FILE"

if [[ $EUID -ne 0 ]]; then
    fatalError "$THIS_SCRIPT must be run as root"
    exit 1
fi

INI_FILE_PATH=$1

if [[ -z $INI_FILE_PATH ]]; then
    fatalError "${g_prog} called with null parameter, should be the path to the driving ini_file"
fi

if [[ ! -f $INI_FILE_PATH ]]; then
    fatalError "${g_prog} ini_file cannot be found"
fi

if ! mkdir -p $LOG_DIR; then
    fatalError "${g_prog} cant make $LOG_DIR"
fi

chmod 777 $LOG_DIR

cp $INI_FILE_PATH $INI_FILE

run

log "$g_prog ended cleanly"
exit $RETVAL

