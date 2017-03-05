#!/bin/bash
#########################################################################################
## OGG Test Suite
#########################################################################################
# Configures Oracle Goldengate to replicate oracledb test suite schemas 
# [ see https://github.com/mgis-architects/oracledb ]
# This script only supports Azure currently, mainly due to the disk persistence method
#
# USAGE:
#
#    sudo ogg-testsuite.sh ~/ogg-testsuite.ini
#
# USEFUL LINKS: 
# 
# docs:    https://docs.oracle.com/goldengate/c1221/gg-winux/docs.htm
# install: https://docs.oracle.com/goldengate/c1221/gg-winux/GIORA/GUID-FBE6775F-A3F8-4765-BEAE-A302C7D8B6F9.htm#GIORA977
#
#########################################################################################

g_prog=ogg-testsuite
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

oggHome=/u01/app/oracle/product/12.2.1/ogg

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

function configureDbForOGG() {

    local l_tmp_script=$LOG_DIR/$g_prog.oggTestSuite.$$.installSimpleSchema.sh
    local l_log=$LOG_DIR/$g_prog.oggTestSuite.$$.installSimpleSchema.log
    
    ################################
    # Create script to run as oracle
    ################################
    cat > $l_tmp_script << EOFconfdb
    
    export ORACLE_SID=${cdbSID}
    
    sqlplus / as sysdba << EOFsql1
        alter database add supplemental log data;
        alter database force logging;
        SELECT supplemental_log_data_min, force_logging FROM v\\\$database;
        alter system set enable_goldengate_replication=true sid='*' scope=both;
        create user c##ggadmin identified by ${ggadminPassword} default tablespace users temporary tablespace temp;
        grant dba TO c##ggadmin CONTAINER=all;
        exec dbms_goldengate_auth.grant_admin_privilege('c##ggadmin',container=>'all');
EOFsql1

EOFconfdb
    
    ################################
    # Run the script
    ################################
    su - oracle -c "bash -x $l_tmp_script" |tee ${l_ogginstall_log}
}


function encryptOGG() {

    local l_tmp_script=$LOG_DIR/$g_prog.oggTestSuite.$$.encryptOGG.sh
    local l_log=$LOG_DIR/$g_prog.oggTestSuite.$$.encryptOGG.log
    
    ################################
    # Create script to run as oracle
    ################################
    cat > $l_tmp_script << EOFencrypt

        #############################################################################
        export OGG_HOME=${oggHome}
        export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:\$LD_LIBRARY_PATH
        cd \$OGG_HOME
        
        #############################################################################        
        ./ggsci > ~/.oggEncryptOutput << EOFogg1 
encrypt password ${ggadminPassword} BLOWFISH ENCRYPTKEY DEFAULT
exit
EOFogg1
        #############################################################################        
        eval \`grep 'Encrypted password' ~/.oggEncryptOutput | awk '{print "oggEncrypted="\$NF}'\`
        chmod 600 ~/.oggEncryptOutput

        #############################################################################        
        cat >> ${oggHome}/dirprm/mgr.prm << EOFmgr

userid c##ggadmin@${pdbConnectStr},password \${oggEncrypted}, BLOWFISH, ENCRYPTKEY DEFAULT
purgeoldextracts \$OGG_HOME/dirdat/*, usecheckpoints
EOFmgr

        #############################################################################        
        ./ggsci << EOFogg2
        stop manager \!
        start manager
EOFogg2

EOFencrypt

    su - oracle -c "bash -x $l_tmp_script" |tee ${l_log}
}


function oggInitialExtract() {

    local l_tmp_script=$LOG_DIR/$g_prog.oggTestSuite.$$.oggInitialExtract.sh
    local l_log=$LOG_DIR/$g_prog.oggTestSuite.$$.oggInitialExtract.log
    
    ################################
    # Create script to run as oracle
    ################################
    cat > $l_tmp_script << EOFiniext

        #############################################################################
        export OGG_HOME=${oggHome}
        export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:\$LD_LIBRARY_PATH
        cd \$OGG_HOME
        eval \`grep 'Encrypted password' ~/.oggEncryptOutput | awk '{print "oggEncrypted="\$NF}'\`

        #############################################################################        
        cat >> ${oggHome}/dirprm/ini_ext.prm << EOFextr
SOURCEISTABLE    
userid c##ggadmin@${cdbConnectStr},password \${oggEncrypted}, BLOWFISH, ENCRYPTKEY DEFAULT
RMTHOST ${ogg4bdHost}, MGRPORT ${ogg4bdMgrPort}
RMTFILE ${ogg4bdDestination}/initld, MEGABYTES 2, PURGE
SOURCECATALOG ${pdbName}
TABLE ${simpleSchema}.*;
EOFextr

        ./ggsci << EOFtrandata
        dblogin userid c##ggadmin@${cdbConnectStr},password \${oggEncrypted}, BLOWFISH, ENCRYPTKEY DEFAULT
        ADD SCHEMATRANDATA ${simpleSchema} ALLCOLS
        ADD SCHEMATRANDATA ${pdbName}.${simpleSchema}
EOFtrandata



        #############################################################################        
        ./extract paramfile dirprm/ini_ext.prm reportfile dirrpt/ini_ext.rpt
        ls -l ${ogg4bdDestination}/initld        

EOFiniext

    su - oracle -c "bash -x $l_tmp_script" |tee ${l_log}
}

function oggCreateExtract() {

    local l_tmp_script=$LOG_DIR/$g_prog.oggTestSuite.$$.oggCreateExtract.sh
    local l_log=$LOG_DIR/$g_prog.oggTestSuite.$$.oggCreateExtract.log
    
    ################################
    # Create script to run as oracle
    ################################
    cat > $l_tmp_script << EOFcrext

        #############################################################################
        export OGG_HOME=${oggHome}
        export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:\$LD_LIBRARY_PATH
        cd \$OGG_HOME
        eval \`grep 'Encrypted password' ~/.oggEncryptOutput | awk '{print "oggEncrypted="\$NF}'\`

        #############################################################################        
        cat > ${oggHome}/dirprm/exbasic1.prm << EOFexbasic1
extract exbasic1
userid c##ggadmin@${cdbConnectStr},password \${oggEncrypted}, BLOWFISH, ENCRYPTKEY DEFAULT
RMTHOST ${ogg4bdHost}, MGRPORT ${ogg4bdMgrPort}
RMTFILE ${ogg4bdDestination}/ss, MEGABYTES 2, PURGE
SOURCECATALOG ${pdbName}
DDL include objname ${simpleSchema}.*
TABLE ${simpleSchema}.*;
EOFexbasic1

        #############################################################################        
        ./ggsci << EOFggsci1
        dblogin userid c##ggadmin@${cdbConnectStr},password \${oggEncrypted}, BLOWFISH, ENCRYPTKEY DEFAULT
        register extract exbasic1 database container ($pdbName)
        ADD SCHEMATRANDATA ${pdbName}.${simpleSchema} ALLCOLS
        add extract exbasic1, INTEGRATED TRANLOG, BEGIN NOW
EOFggsci1


EOFcrext

    su - oracle -c "bash -x $l_tmp_script" |tee ${l_log}
}

function run()
{
    eval `grep platformEnvironment $INI_FILE`
    if [ -z $platformEnvironment ]; then    
        fatalError "$g_prog.run(): Unknown environment, check platformEnvironment setting in iniFile"
    elif [ $platformEnvironment != "AZURE" ]; then    
        fatalError "$g_prog.run(): platformEnvironment=AZURE is the only valid setting currently"
    fi

    eval `grep simpleSchema $INI_FILE`
    eval `grep pdbConnectStr $INI_FILE`
    eval `grep cdbConnectStr $INI_FILE`
    eval `grep cdbSID $INI_FILE`
    eval `grep ggadminPassword $INI_FILE`
    eval `grep pdbName $INI_FILE`
    eval `grep pdbDBA $INI_FILE`
    eval `grep pdbDBApassword $INI_FILE`
    eval `grep ogg4bdHost $INI_FILE`
    eval `grep ogg4bdMgrPort $INI_FILE`
	eval `grep ogg4bdDestination $INI_FILE`

    l_str=""
    if [ -z $simpleSchema ]; then
        l_str+="simpleSchema not found in $INI_FILE; "
    fi
    if [ -z $cdbSID ]; then
        l_str+="cdbSID not found in $INI_FILE; "
    fi
    if [ -z $cdbConnectStr ]; then
        l_str+="cdbConnectStr not found in $INI_FILE; "
    fi
    if [ -z $pdbConnectStr ]; then
        l_str+="pdbConnectStr not found in $INI_FILE; "
    fi
    if [ -z $pdbName ]; then
        l_str+="pdbName not found in $INI_FILE; "
    fi
    if [ -z $pdbDBA ]; then
        l_str+="pdbDBA not found in $INI_FILE; "
    fi
    if [ -z $ggadminPassword ]; then
        l_str+="ggadminPassword not found in $INI_FILE; "
    fi
    if [ -z $pdbDBApassword ]; then
        l_str+="pdbDBApassword not found in $INI_FILE; "
    fi
    if [ -z $ogg4bdHost ]; then
        l_str+="ogg4bdHost not found in $INI_FILE; "
    fi
    if [ -z $ogg4bdMgrPort ]; then
        l_str+="ogg4bdMgrPort not found in $INI_FILE; "
    fi
    if [ -z $ogg4bdDestination ]; then
        l_str+="ogg4bdDestination not found in $INI_FILE; "
    fi
    if ! [ -z $l_str ]; then
        fatalError "installSimpleSchema(): $l_str"
    fi

    # function calls
    configureDbForOGG
    encryptOGG
    oggInitialExtract
    oggCreateExtract
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

