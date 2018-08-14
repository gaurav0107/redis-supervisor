#!/usr/bin/env python

import json
import optparse
import os
import paramiko
import urllib2
from pathlib import Path
import stat

def getConfig(filename):
    try:
        with open(filename) as config:
            redis_cluster_config = json.load(config)
    except IOError:
        print "Config File not found, pass --conf <config file>"
        os._exit(2)
    except ValueError:
        print "Invalid Config File"
        os._exit(2)
    return redis_cluster_config

def validateConfig(config):
    if "CLUSTER" not in config or not isinstance(config["CLUSTER"], list):
        print "Invalid Config File"
        os._exit(2)
    for host_conf in config["CLUSTER"]:
        if "host" not in host_conf:
            print "No host in Config File"
            os._exit(2)
        if "port" not in host_conf and not isinstance(host_conf["port"], int):
            print "Invalid port in Config File"
            os._exit(2)
        if "sentinel_port" not in host_conf:
            host_conf["sentinel_port"] = host_conf["port"] + 10000
        if "log_file" not in host_conf:
            host_conf["log_file"] = "redis_" + str(host_conf["port"]) + ".log"
        if "sentinel_log_file" not in host_conf:
            host_conf["sentinel_log_file"] = "redis_sentinel_" + str(host_conf["sentinel_port"]) + ".log"
    return config

def updateSSHCon(config):
    for host_conf in config["CLUSTER"]:
        client1=paramiko.SSHClient()
        client1.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client1.connect(host_conf["host"], username=host_conf["user"], 
                password=host_conf["pass"])
        host_conf["ssh_con"] = client1
    return config


def downloadRedis(con, version):
    url = "http://download.redis.io/releases/redis-"+version+".tar.gz"
    filename = "/tmp/redis-"+version+".tar.gz"
    u = urllib2.urlopen(url)
    f = open(filename, 'wb')
    meta = u.info()
    file_size = int(meta.getheaders("Content-Length")[0])
    print "Downloading: %s Bytes: %s" % (filename, file_size)
    file_size_dl = 0
    block_sz = 8192
    print "gaurav fetching"
    while True:
        buffer = u.read(block_sz)
        if not buffer:
            break
        file_size_dl += len(buffer)
        f.write(buffer)
        status = r"%10d  [%3.2f%%]" % (file_size_dl, file_size_dl * 100. / file_size)
        status = status + chr(8)*(len(status)+1)
        print status,
    f.close()
    redis_tar = Path(filename)
    if redis_tar.is_file():
        sftp = con.open_sftp()
        sftp.put(filename, filename)
        sftp.close()
        return True
    else:
        return False


def installRedis(host_conf, redis):
    filename= '/tmp/redis-'+redis["version"]+'.tar.gz'
    try:
        sftp = host_conf["ssh_con"].open_sftp()
        print(sftp.stat(filename))
        print "file exists"
    except IOError:
        print "File Not Exists Downloading ...!!!"
        if not downloadRedis(host_conf["ssh_con"], redis["version"]):
            return False
        print "File Download Successfull !!!"
    print "Extraction file:" + filename + 'tar xzf ' + filename+ ' --directory /tmp > /dev/null 2>&1\n'
    stdin, stdout, stderr = host_conf["ssh_con"].exec_command('tar xzf ' + filename+ ' --directory /tmp > /dev/null 2>&1\n')
    if stderr.read():
        print stderr.read()
        return False
    print "File Extraction Successfull !!!"
    print 'sudo make --directory=/tmp/redis-'+redis["version"]+' \n'
    stdin, stdout, stderr = host_conf["ssh_con"].exec_command('sudo pkill -9 -f redis \n')
    stdin, stdout, stderr = host_conf["ssh_con"].exec_command('sudo make distclean --directory=/tmp/redis-'+redis["version"]+' \n')
    stdin, stdout, stderr = host_conf["ssh_con"].exec_command('sudo make --directory=/tmp/redis-'+redis["version"]+' \n')
    if stderr.read():
        print stderr.read()
        return False
    stdin, stdout, stderr = host_conf["ssh_con"].exec_command('sudo make install --directory=/tmp/redis-'+redis["version"]  +'\n')
    if stderr.read():
        print stderr.read()
        return False
    return True


def checkAndInstallRedis(config):
    status = list()
    for host_conf in config["CLUSTER"]:
        k = installRedis(host_conf, config["REDIS"])
        if k:
            stdin, stdout, stderr = host_conf["ssh_con"].exec_command('redis-server -v\n')
            out = stdout.read()
            if "v="+config["REDIS"]["version"] in out:
                print "Redis Version already exists"
                status.append(True)
            else:
                status.append(False)
    if False in status:
        return False
    return True


def setUpConfiguration(host_conf, redis):
    os.system("rsync -avrz install_server.sh %s@%s:/tmp/install_server.sh  > /dev/null 2>&1" %(host_conf["user"], host_conf["host"]))
    os.system("rsync -avrz redis_init_script.tpl %s@%s:/tmp/redis_init_script.tpl  > /dev/null 2>&1" %(host_conf["user"], host_conf["host"]))
    os.system("rsync -avrz redis_sentinel_script.tpl %s@%s:/tmp/redis_sentinel_script.tpl  > /dev/null 2>&1" %(host_conf["user"], host_conf["host"]))
    os.system("rsync -avrz redis_supervisor_conf.tpl %s@%s:/tmp/redis_supervisor_conf.tpl  > /dev/null 2>&1" %(host_conf["user"], host_conf["host"]))

def choseRandomMaster(config_file):
    import random
    return random.choice(config_file["CLUSTER"])


def setUpCluster(config_file):
    config = updateSSHCon(validateConfig(getConfig(config_file)))
    if not checkAndInstallRedis(config):
        os._exit(2)
        
    for host_conf in config["CLUSTER"]:
        setUpConfiguration(host_conf, config["REDIS"])
    
    ###setup cluster
    master = choseRandomMaster(config)
    slave_list = [x for x in config["CLUSTER"] if x != master]

    #Configure Master
    print "Setting up Master: " + master["host"] + "  " + str(master["port"])
    stdin, stdout, stderr = master["ssh_con"].exec_command('sudo /tmp/install_server.sh -n %s -u %s --host %s -p %s -sp %s -v %s -d %s -t %s -q %s -m %s -mp %s\n' %(config["SENTINEL"]["name"], config["REDIS"]["user"], master["host"], str(master["port"]), str(master["sentinel_port"]), config["REDIS"]["version"], str(config["SENTINEL"]["down-after-milliseconds"]), str(config["SENTINEL"]["failover-timeout"]), str(config["SENTINEL"]["quorum"]), master["host"], str(master["port"])))
    
    print (stdout.read(), stderr.read())
    
    #Configure Slave
    for slave in slave_list:
        print "Setting up Slave" +  slave["host"] + "  " + str(slave["port"])
        stdin, stdout, stderr = slave["ssh_con"].exec_command('sudo /tmp/install_server.sh -n %s -u %s --host %s -p %s -sp %s -v %s -d %s -t %s -q %s -m %s -mp %s\n' %(config["SENTINEL"]["name"], config["REDIS"]["user"], slave["host"], slave["port"],  slave["sentinel_port"], config["REDIS"]["version"], config["SENTINEL"]["down-after-milliseconds"], config["SENTINEL"]["failover-timeout"], config["SENTINEL"]["quorum"], master["host"], master["port"]))
        print (stdout.read(), stderr.read())

    #Starting Master
    stdin, stdout, stderr = master["ssh_con"].exec_command('sudo service redis_'+ str(master["port"]) + ' restart \n')
    print (stdout.read(), stderr.read())
    stdin, stdout, stderr = master["ssh_con"].exec_command('sudo service redis_sentinel_'+ str(master["sentinel_port"]) + ' restart \n')
    print (stdout.read(), stderr.read())

    for slave in slave_list:
        stdin, stdout, stderr = master["ssh_con"].exec_command('sudo service redis_'+ str(slave["port"]) + ' restart \n')
        print (stdout.read(), stderr.read())
        stdin, stdout, stderr = master["ssh_con"].exec_command('sudo service redis_sentinel_'+ str(slave["sentinel_port"]) + ' restart \n')
        print (stdout.read(), stderr.read())


if __name__ == '__main__':
    parser = optparse.OptionParser()
    parser.add_option('-c', '--config', dest="config",
    help="config file", default="")
    options, args = parser.parse_args()
    setUpCluster(options.config)
