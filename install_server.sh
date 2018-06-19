#!/bin/bash



die () {
    echo "ERROR: $1. Aborting!"
    exit 1
}

printHelp () {
    echo "-h|--help:                 Get Help"
    echo "-n|--name:                 Cluster Name(default: mycluster)"
    echo "-p|--port:                 Redis Port(default: 6379)"
    echo "-sp|--sentinel-port:       Sentinel Port(default: 26379)"
    echo "-m|--master:               Master Ip:(default: localhost)"
    echo "-mp|--master-port:         Master Port:(default: 6379)"
    echo "-c|--config:               Redis Config FileName:(default: redis_<port>.conf)"
    echo "-sc|--sentinel-config:     Sentinel Config FileName:(default: redis_sentinel_<sentinel_port>.conf)"
    echo "-cd|--config-dir:          Config Dir:(default: /etc/redis/)"
    echo "-dd|--data-dir:            Master Ip:(default: /var/lib/redis/<PORT>)"
    exit 0
}

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -h|--help)
    printHelp
    ;;
    -n|--name)
    CLUSTER_NAME="$2"
    shift # past argument
    shift # past value
    ;;
    -m|--master)
    MASTER="$2"
    shift # past argument
    shift # past value
    ;;
    -mp|--master-port)
    MASTER_PORT="$2"
    shift # past argument
    shift # past value
    ;;
    --host)
    HOST="$2"
    shift # past argument
    shift # past value
    ;;
    -p|--port)
    REDIS_PORT="$2"
    shift # past argument
    shift # past value
    ;;
    -sp|--sentinel-port)
    SENTINEL_PORT="$2"
    shift # past argument
    shift # past value
    ;;
    -c|--config)
    REDIS_CONFIG="$2"
    shift # past argument
    shift # past value
    ;;
     -sc|--sentinel_config)
    SENTINEL_CONFIG="$2"
    shift # past argument
    shift # past value
    ;;
    -u|--user)
    REDIS_USER="$2"
    shift # past argument
    shift # past value
    ;;
    -v|--version)
    REDIS_VERSION="$2"
    shift # past argument
    shift # past value
    ;;
    -q|--quorum)
    QUORUM="$2"
    shift # past argument
    shift # past value
    ;;  
    -d|--down-after)
    DOWN_AFTER="$2"
    shift # past argument
    shift # past value
    ;; 
    -t|--failover-timeout)
    FAILOVER_TIMEOUT="$2"
    shift # past argument
    shift # past value
    ;;  
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters
if [ -z "$CLUSTER_NAME" ];then
    CLUSTER_NAME="mycluster"
fi
if [ -z "$MASTER" ];then
    MASTER="localhost"
fi
if [ -z "$MASTER_PORT" ];then
    MASTER_PORT=6379
fi
if [ -z "$HOST" ];then
    HOST="localhost"
fi

if [ -z "$QUORUM" ];then
    QUORUM=2
fi
if [ -z "$DOWN_AFTER" ];then
    DOWN_AFTER=10000
fi
if [ -z "$FAILOVER_TIMEOUT" ];then
    FAILOVER_TIMEOUT=30000
fi
if [ -z "$REDIS_VERSION" ];then
    die "redis version is mandatory"
fi
if [ -z "$REDIS_USER" ];then
    REDIS_USER="redis"
fi
if [ -z "$REDIS_PORT" ];then
    REDIS_PORT=6379
elif [[ $REDIS_PORT =~ ^-?[0-9]+$ ]];then
    :
else
    die "Redis Port should be an Integer"
fi
if [ -z "$SENTINEL_PORT" ];then
    SENTINEL_PORT=26379
elif [[ $SENTINEL_PORT =~ ^-?[0-9]+$ ]];then
    :
else
	die "Sentinel Port should be an Integer"
fi

echo "Setting Up Cluster: ${CLUSTER_NAME}"


SOURCE_DIR="/tmp/redis-${REDIS_VERSION}"
LOG_DIR="/var/log/redis"
CONF_DIR="/etc/redis"
REDIS_LOG_FILE="${LOG_DIR}/redis_${REDIS_PORT}.log"
SENTINEL_LOG_FILE="${LOG_DIR}/redis_sentinel_${SENTINEL_PORT}.log"
REDIS_CONFIG_FILE="${CONF_DIR}/redis_${REDIS_PORT}.conf"
SENTINEL_CONFIG_FILE="${CONF_DIR}/redis_sentinel_${SENTINEL_PORT}.conf"
REDIS_DATA_DIR="/var/lib/redis/${REDIS_PORT}" 

echo $REDIS_CONFIG_FILE

#Templates
REDIS_TMP_FILE="/tmp/redis_${REDIS_PORT}.conf"
SENTINEL_TMP_FILE="/tmp/redis_sentinel_${SENTINEL_PORT}.conf"
DEFAULT_REDIS_CONFIG="${SOURCE_DIR}/redis.conf"
DEFAULT_SENTINEL_CONFIG="${SOURCE_DIR}/sentinel.conf"
INIT_TPL_FILE="/tmp/redis_init_script.tpl"
INIT_SENTINEL_TPL_FILE="/tmp/redis_sentinel_script.tpl"
REDIS_INIT_SCRIPT_DEST="/etc/init.d/redis_${REDIS_PORT}"
SENTINEL_INIT_SCRIPT_DEST="/etc/init.d/redis_sentinel_${SENTINEL_PORT}"
REDIS_RUN_DIR="/var/run/redis"
REDIS_PIDFILE="${REDIS_RUN_DIR}/redis_${REDIS_PORT}.pid"
SENTINEL_PIDFILE="${REDIS_RUN_DIR}/redis_sentinel_${SENTINEL_PORT}.pid"

REDIS_EXECUTABLE="redis-server"
CLI_EXEC="redis-cli"
REDIS_INIT_TMP_FILE="/tmp/redis_tmp_init"
REDIS_SENTINEL_INIT_TMP_FILE="/tmp/redis_sentinel_tmp_init"
#REDIS_SUPERVISOR_TPL_FILE="/tmp/redis_supervisor_conf.tpl"
#REDIS_SUPERVISOR_TMP_FILE="/tmp/redis_${REDIS_PORT}.conf"
#REDIS_SUPERVISOR_SENTINEL_TMP_FILE="/tmp/redis_sentinel_${SENTINEL_PORT}.conf"


sudo chmod 777 "/tmp/redis_init_script.tpl"
sudo chmod 777 "/tmp/redis_sentinel_script.tpl"


#Create User
if ! id -u ${REDIS_USER} > /dev/null 2>&1; then
    sudo useradd -r -s /bin/false ${REDIS_USER}
fi

#Creating Directories
sudo mkdir -p `dirname "$REDIS_CONFIG_FILE"` || die "Could not create redis config directory"
sudo mkdir -p `dirname "$REDIS_LOG_FILE"` || die "Could not create redis log dir"
sudo mkdir -p "$REDIS_DATA_DIR" || die "Could not create redis data directory"
sudo mkdir -p "$REDIS_RUN_DIR" || die "Could not create redis run directory"
sudo mkdir -p "$LOG_DIR" || die "Could not create redis log directory"

#Installing Dependencies
echo "Installing Dependencies..."
sudo apt-get install tcl -y > /dev/null 2>&1
#sudo apt-get install supervisor -y > /dev/null 2>&1
#sudo service supervisor restart

#Adding Permissions to user
sudo chown -R ${REDIS_USER}:${REDIS_USER} ${CONF_DIR}
sudo chown -R ${REDIS_USER}:${REDIS_USER} ${REDIS_DATA_DIR}
sudo chown -R ${REDIS_USER}:${REDIS_USER} ${REDIS_RUN_DIR}
sudo chown -R ${REDIS_USER}:${REDIS_USER} ${LOG_DIR}


echo $DEFAULT_REDIS_CONFIG

if [ ! -f "$DEFAULT_REDIS_CONFIG" ]; then
    echo "Mmmmm... the default config is missing. Did you switch to the utils directory?"
    exit 1
fi

echo "## Generated by sentinel_installer.sh ##" > $REDIS_TMP_FILE

read -r SED_EXPR <<-EOF
s#^port .\+#port ${REDIS_PORT}#; \
s#^logfile .\+#logfile ${REDIS_LOG_FILE}#; \
s#^dir .\+#dir ${REDIS_DATA_DIR}#; \
s#^pidfile .\+#pidfile ${REDIS_PIDFILE}#; \
s/bind 127.0.0.1/bind 0.0.0.0/g; \
s#^daemonize no#daemonize yes#;
EOF

echo "$MASTER $HOST"
if [ $MASTER == $HOST ];then
    if [ $MASTER_PORT == $REDIS_PORT ] ;then
	:
    else
        SED_EXPR=${SED_EXPR}" s/# slaveof <masterip> <masterport>/slaveof ${MASTER} ${MASTER_PORT}/g;"
    fi

else
    SED_EXPR=${SED_EXPR}" s/# slaveof <masterip> <masterport>/slaveof ${MASTER} ${MASTER_PORT}/g;"
fi


sed "$SED_EXPR" $DEFAULT_REDIS_CONFIG >> $REDIS_TMP_FILE

sudo cp $REDIS_TMP_FILE $REDIS_CONFIG_FILE || die "Could not write redis config file $REDIS_CONFIG_FILE"
rm -f $REDIS_TMP_FILE

echo "## Generated by sentinel_installer.sh ##" > $SENTINEL_TMP_FILE

read -r SED_EXPR <<-EOF
s#^port .\+#port ${SENTINEL_PORT}#; \
s/sentinel monitor mymaster 127.0.0.1 6379 2/sentinel monitor ${CLUSTER_NAME} ${MASTER} ${MASTER_PORT} ${QUORUM}/g; \
s/sentinel down-after-milliseconds mymaster 30000/sentinel down-after-milliseconds ${CLUSTER_NAME} ${DOWN_AFTER}/g; \
s/sentinel parallel-syncs mymaster 1/sentinel parallel-syncs ${CLUSTER_NAME} 1/g; \
s/sentinel failover-timeout mymaster 180000/sentinel failover-timeout ${CLUSTER_NAME} ${FAILOVER_TIMEOUT}/g; \
s#^daemonize no#daemonize yes#;
EOF
sed "$SED_EXPR" $DEFAULT_SENTINEL_CONFIG >> $SENTINEL_TMP_FILE
echo "daemonize yes" >> $SENTINEL_TMP_FILE
echo "logfile ${SENTINEL_LOG_FILE}" >> $SENTINEL_TMP_FILE

sudo cp $SENTINEL_TMP_FILE $SENTINEL_CONFIG_FILE || die "Could not write sentinel config file $SENTINEL_CONFIG_FILE"
rm -f $SENTINEL_TMP_FILE



#echo "## Generated by sentinel_installer.sh ##" > $REDIS_SUPERVISOR_TMP_FILE
#echo "[program:redis_${REDIS_PORT}]" >> $REDIS_SUPERVISOR_TMP_FILE
#read -r SED_EXPR <<-EOF
#s#^command.\+#command=/usr/local/bin/redis-server ${REDIS_CONFIG_FILE}#;\
#s#^user.\+#user=${REDIS_USER}#;
#EOF
#sed "$SED_EXPR" $REDIS_SUPERVISOR_TPL_FILE >> $REDIS_SUPERVISOR_TMP_FILE
#sudo cp $REDIS_SUPERVISOR_TMP_FILE /etc/supervisor/conf.d/

#echo "## Generated by sentinel_installer.sh ##" > $REDIS_SUPERVISOR_SENTINEL_TMP_FILE
#echo "[program:redis_sentinel_${SENTINEL_PORT}]" >> $REDIS_SUPERVISOR_SENTINEL_TMP_FILE
#read -r SED_EXPR <<-EOF
#s#^command.\+#command=/usr/local/bin/redis-server ${SENTINEL_CONFIG_FILE} --sentinel#;\
#s#^user.\+#user=${REDIS_USER}#;
#EOF
#sed "$SED_EXPR" $REDIS_SUPERVISOR_TPL_FILE >> $REDIS_SUPERVISOR_SENTINEL_TMP_FILE
#sudo cp $REDIS_SUPERVISOR_SENTINEL_TMP_FILE /etc/supervisor/conf.d/


cat > ${REDIS_INIT_TMP_FILE} <<EOT
#!/bin/sh
#Configurations injected by install_server below....

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
DAEMON="/usr/local/bin/$REDIS_EXECUTABLE"
PIDFILE="$REDIS_PIDFILE"
RUNDIR="$REDIS_RUN_DIR"
REDIS_USER="$REDIS_USER"
DAEMON_ARGS="$REDIS_CONFIG_FILE"
REDISPORT="$REDIS_PORT"
###############
# SysV Init Information
# chkconfig: - 58 74
# description: redis_${REDIS_PORT} is the redis daemon.
### BEGIN INIT INFO
# Provides: redis_${REDIS_PORT}
# Required-Start: \$network \$local_fs \$remote_fs
# Required-Stop: \$network \$local_fs \$remote_fs
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Should-Start: \$syslog \$named
# Should-Stop: \$syslog \$named
# Short-Description: start and stop redis_${REDIS_PORT}
# Description: Redis daemon
### END INIT INFO

EOT
cat ${INIT_TPL_FILE} >> ${REDIS_INIT_TMP_FILE}
sudo cp ${REDIS_INIT_TMP_FILE} "/etc/init.d/redis_${REDIS_PORT}"
sudo chmod a+x "/etc/init.d/redis_${REDIS_PORT}"



cat > ${REDIS_SENTINEL_INIT_TMP_FILE} <<EOT
#!/bin/sh
#Configurations injected by install_server below....

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
DAEMON="/usr/local/bin/$REDIS_EXECUTABLE"
PIDFILE="$SENTINEL_PIDFILE"
RUNDIR="$REDIS_RUN_DIR"
REDIS_USER="$REDIS_USER"
DAEMON_ARGS="$SENTINEL_CONFIG_FILE --sentinel"
###############
# SysV Init Information
# chkconfig: - 58 74
# description: redis_sentinel_${SENTINEL_PORT} is the redis daemon.
### BEGIN INIT INFO
# Provides: redis_sentinel_${SENTINEL_PORT}
# Required-Start: \$network \$local_fs \$remote_fs
# Required-Stop: \$network \$local_fs \$remote_fs
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Should-Start: \$syslog \$named
# Should-Stop: \$syslog \$named
# Short-Description: start and stop redis_sentinel_${SENTINEL_PORT}
# Description: Redis daemon
### END INIT INFO

EOT
cat ${INIT_TPL_FILE} >> ${REDIS_SENTINEL_INIT_TMP_FILE}




sudo cp ${REDIS_SENTINEL_INIT_TMP_FILE} "/etc/init.d/redis_sentinel_${SENTINEL_PORT}"
sudo chmod a+x "/etc/init.d/redis_sentinel_${SENTINEL_PORT}"
sudo chown ${REDIS_USER}:${REDIS_USER} -R /etc/redis
sudo chmod 777 -R /etc/redis

echo "Installation Successfull"
