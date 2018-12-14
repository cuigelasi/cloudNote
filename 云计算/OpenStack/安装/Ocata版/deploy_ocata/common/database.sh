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
controller_ip=`crudini --get $DEPLOY_PATH/conf/auto-config default controller_ip`
KEYSTONE_DBPASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd KEYSTONE_DBPASS`
GLANCE_DBPASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd GLANCE_DBPASS`
NOVA_DBPASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd NOVA_DBPASS`
echo $controller_ip
echo $KEYSTONE_DBPASS
echo $GLANCE_DBPASS
echo $NOVA_DBPASS


mysql -uroot -p123qwe <<EOF
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@"$controller_ip" IDENTIFIED BY "$KEYSTONE_DBPASS";
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY "$KEYSTONE_DBPASS";
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@"$controller_ip" IDENTIFIED BY "$GLANCE_DBPASS";
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY "$GLANCE_DBPASS";
CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'$controller_ip' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'$controller_ip' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'$controller_ip' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';
EOF
