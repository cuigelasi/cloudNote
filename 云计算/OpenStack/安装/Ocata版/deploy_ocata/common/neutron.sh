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
NEUTRON_DBPASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd NEUTRON_DBPASS`
echo $controller_ip
echo $KEYSTONE_DBPASS
echo $GLANCE_DBPASS
echo $NOVA_DBPASS
echo $NEUTRON_DBPASS


mysql -uroot -p123qwe <<EOF
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@"$controller_ip" IDENTIFIED BY "$NEUTRON_DBPASS";
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY "$NEUTRON_DBPASS";
EOF
