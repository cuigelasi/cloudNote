#!/bin/bash
## 获取目录路径
getPath(){
    this_dir=`pwd`
    dirname $0 | grep "^/" >/dev/null
    if [ $? -eq 0 ]; then
        this_dir=`dirname $0`
    else
        dirname $0 | grep "^\." >/dev/null
        retval=$?
        if [ $retval -eq 0 ]; then
            this_dir=`dirname $0 | sed "s#^.#$this_dir#"`
        else
            this_dir=`dirname $0 | sed "s#^#$this_dir/#"`
        fi
    fi
    echo `dirname $this_dir`
}

DEPLOY_PATH=`getPath`
DB_PASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd DB_PASS`
echo $DB_PASS

/usr/bin/expect <<EOF
spawn mysql_secure_installation
expect "Enter current password for root (enter for none):" {
send "\r";exp_continue
} "Set root password?" {
send "y\r";exp_continue
} "New password:" {
send "$DB_PASS\r";exp_continue
} "Re-enter new password:" {
send "$DB_PASS\r";exp_continue
} "Remove anonymous users?" {
send "y\r";exp_continue
} "Disallow root login remotely?" {
send "n\r";exp_continue
} "Remove test database and access to it?" {
send "y\r";exp_continue
} "Reload privilege tables now?" {
send "y\r";exp_continue
}
EOF
