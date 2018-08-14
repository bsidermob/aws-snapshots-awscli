import json
import os
import subprocess
import commands

print('Loading function')

def handler(event, context):
    #os.system("bash ec2.sh; uname -a;id;w;free -m;vmstat 2 10;df -h;netstat -in;cat /etc/issue; netstat -nr; echo $PATH;type aws; aws ec2 describe-instances; jq 2>&1; ls -l")
    # Change workdir as only /tmp is writable
    os.chdir("/tmp")
    print (commands.getstatusoutput('bash /var/task/backup.sh'))
