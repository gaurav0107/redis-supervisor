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
            host_conf["sentinel_port"] = host_conf["port"] + 20000
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
        print "File Already Exists !!!"
    except IOError:
        print "File Not Exists Downloading ...!!!"
        if not downloadRedis(host_conf["ssh_con"], redis["version"]):
            return False
        print "File Download Successfull !!!"
    print "Extraction file:" + filename + 'tar xzf ' + filename+ ' --directory /tmp\n'
    stdin, stdout, stderr = host_conf["ssh_con"].exec_command('tar xzf ' + filename+ ' --directory /tmp\n')
    if stderr.read():
        print stderr.read()
        return False
    print "File Extraction Successfull !!!"
    stdin, stdout, stderr = host_conf["ssh_con"].exec_command('sudo make --directory=/tmp/redis-'+redis["version"]+' \n')
    stdin, stdout, stderr = host_conf["ssh_con"].exec_command('sudo make intall --directory=/tmp/redis-'+redis["version"]  +'\n')
    return True


def checkExistingVersion(config):
    status = list()
    for host_conf in config["CLUSTER"]:
        stdin, stdout, stderr = host_conf["ssh_con"].exec_command('redis-server -v\n')
        out = stdout.read()
        if "v="+config["REDIS"]["version"] in out:
            print "Redis Version already exists"
            status.append(True)
        elif "v=" in out:
            print "Some Other version present on %s, Please Uninstall"  %(host_conf["host"])
            status.append(False)
        else:
            status.append(installRedis(host_conf, config["REDIS"]))
    if False in status:
        return False
    return True


def setUpConfiguration(host_conf, redis):
    os.system("rsync -avrz install_server.sh %s@%s:/tmp/install_server.sh  > /dev/null 2>&1" %(host_conf["user"], host_conf["host"]))
    os.system("rsync -avrz redis_init_script.tpl %s@%s:/tmp/redis_init_script.tpl  > /dev/null 2>&1" %(host_conf["user"], host_conf["host"]))
    os.system("rsync -avrz redis_sentinel_script.tpl %s@%s:/tmp/redis_sentinel_script.tpl  > /dev/null 2>&1" %(host_conf["user"], host_conf["host"]))

def choseRandomMaster(config_file):
    import random
    return random.choice(config_file["CLUSTER"])


def setUpCluster(config_file):
    config = updateSSHCon(validateConfig(getConfig(config_file)))
    if not checkExistingVersion(config):
        os._exit(2)
    ###setup cluster
    master = choseRandomMaster(config)
    slave_list = [x for x in config["CLUSTER"] if x != master]
    print "Randomly Chosen Master is: " + str(master)
    print "Slave list is: " + str(slave_list)
    for host_conf in config["CLUSTER"]:
        setUpConfiguration(host_conf, config["REDIS"])
    #Configure Master
    print "Setting up Master: " + master["host"] + "  " + str(master["port"])
    stdin, stdout, stderr = master["ssh_con"].exec_command('sudo /tmp/install_server.sh -u %s -p %s -sp %s -v %s -d %s -t %s -q %s \n' %(config["REDIS"]["user"], master["port"], master["sentinel_port"], config["REDIS"]["version"], config["SENTINEL"]["down-after-milliseconds"] ,config["SENTINEL"]["failover-timeout"], config["SENTINEL"]["quorum"]))
    
    print stdout.read()
    print stderr.read()
    
    #Configure Slave
    for slave in slave_list:
        print "Setting up Slave" +  slave["host"] + "  " + str(slave["port"])
        stdin, stdout, stderr = slave["ssh_con"].exec_command('sudo /tmp/install_server.sh -u %s -p %s -sp %s -v %s -d %s -t %s -q %s -m %s -mp %s\n' %(config["REDIS"]["user"], slave["port"],  slave["sentinel_port"], config["REDIS"]["version"], config["SENTINEL"]["down-after-milliseconds"], config["SENTINEL"]["failover-timeout"], config["SENTINEL"]["quorum"], master["host"], master["port"]))
        print stdout.read()
        print stderr.read()


if __name__ == '__main__':
    parser = optparse.OptionParser()
    parser.add_option('-c', '--config', dest="config",
    help="config file", default="")
    options, args = parser.parse_args()
    setUpCluster(options.config)
