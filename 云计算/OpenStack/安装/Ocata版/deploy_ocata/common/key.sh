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
ADMIN_PASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd ADMIN_PASS`
DEMO_PASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd DEMO_PASS`
controller_ip=`crudini --get $DEPLOY_PATH/conf/auto-config default controller_ip`
echo $ADMIN_PASS
echo $controller_ip
echo $DEMO_PASS

export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://$controller_ip:35357/v3
export OS_IDENTITY_API_VERSION=3

openstack project create --domain default --description "Service Project" service
openstack project create --domain default --description "Demo Project" demo
openstack user create --domain default --password $DEMO_PASS demo
openstack role create user
openstack role add --project demo --user demo user

unset OS_AUTH_URL OS_PASSWORD
