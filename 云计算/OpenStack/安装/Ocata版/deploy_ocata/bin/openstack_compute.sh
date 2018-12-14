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

## usage
usage()
{
    cat<<EOF

Usage: sh $0 [OPTION]

optional arguments:
    --check
    --install           Install the docker
e.g:
    --- 执行脚本前请检查compute_ip ---
    --- 检查openstack环境 ---
    sh $0 --check
    --- 安装openstack实例 ---
    sh $0 --install <模块名>
EOF
}

DEPLOY_PATH=`getPath`
controller_ip=`crudini --get $DEPLOY_PATH/conf/auto-config default controller_ip`
compute_ip=`crudini --get $DEPLOY_PATH/conf/auto-config default compute_ip1`
RABBIT_PASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd RABBIT_PASS`
KEYSTONE_DBPASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd KEYSTONE_DBPASS`
GLANCE_DBPASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd GLANCE_DBPASS`
NOVA_DBPASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd NOVA_DBPASS`
PLACEMENT_PASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd PLACEMENT_PASS`
NEUTRON_DBPASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd NEUTRON_DBPASS`

openstack_check(){
## 坚持openstack基础环境
    echo "开始检测openstack compute节点"
    echo "############################### nova #######################################"
    systemctl status libvirtd.service openstack-nova-compute.service
    echo "############################### neutron #######################################"
    systemctl status neutron-linuxbridge-agent.service
}


openstack_install(){
    echo controller_ip
    echo $controller_ip
    echo RABBIT_PASS
    echo $RABBIT_PASS
    echo KEYSTONE_DBPASS
    echo $KEYSTONE_DBPASS
    echo GLANCE_DBPASS
    echo $GLANCE_DBPASS
    echo NOVA_DBPASS
    echo $NOVA_DBPASS
    echo PLACEMENT_PASS
    echo $PLACEMENT_PASS
    echo NEUTRON_DBPASS
    echo $NEUTRON_DBPASS
    echo compute_ip
    echo $compute_ip

    if [ "$1" = "selinux" ];then
        check_selinux=`getenforce`
        [ "$check_selinux" = "Disabled" ] && sed -i "s/^SELINUX=.*/SELINUX=disabled/" /etc/selinux/config
        [ "$check_selinux" = "Disabled" ] && setenforce 0
    elif [ "$1" = "firewalld" ];then
        systemctl stop firewalld
        systemctl disable firewalld
    elif [ "$1" = "hostname" ];then
        hostnamectl set-hostname $2 --static
        hostnamectl set-hostname $2 --transient
        hostnamectl set-hostname $2 --pretty
        echo -e "是否重启，使主机名更改为$2?(y/n) \r"
        echo -e "请输入: \c"
        read select_results
        [ "$select_results" = "y" ] && reboot
    elif [ "$1" = "ntp" ];then
        ## 安装chrony
        ## yum install chrony
        echo "server controller iburst" >> /etc/chrony.conf
        #echo "allow 172.16.0.0/16" >> /etc/chrony.conf
        systemctl restart chronyd.service
    elif [ "$1" = "rpm" ];then
        ## 安装openstack rpm
        yum -y install centos-release-openstack-ocata
        yum -y upgrade
        yum -y install python-openstackclient
        yum -y install openstack-selinux
    elif [ "$1" = "nova" ];then
        yum -y install openstack-nova-compute
        crudini --set /etc/nova/nova.conf DEFAULT enabled_apis "osapi_compute,metadata"
        crudini --set /etc/nova/nova.conf DEFAULT transport_url "rabbit://openstack:$RABBIT_PASS@$controller_ip"
        crudini --set /etc/nova/nova.conf DEFAULT my_ip $controller_ip
        crudini --set /etc/nova/nova.conf DEFAULT use_neutron True
        crudini --set /etc/nova/nova.conf DEFAULT firewall_driver "nova.virt.firewall.NoopFirewallDriver"
        crudini --set /etc/nova/nova.conf api auth_strategy keystone
        crudini --set /etc/nova/nova.conf keystone_authtoken auth_uri "http://$controller_ip:5000"
        crudini --set /etc/nova/nova.conf keystone_authtoken auth_url "http://$controller_ip:35357"
        crudini --set /etc/nova/nova.conf keystone_authtoken memcached_servers "$controller_ip:11211"
        crudini --set /etc/nova/nova.conf keystone_authtoken auth_type password
        crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_name default
        crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_name default
        crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
        crudini --set /etc/nova/nova.conf keystone_authtoken username nova
        crudini --set /etc/nova/nova.conf keystone_authtoken password $NOVA_DBPASS
        crudini --set /etc/nova/nova.conf vnc enabled "true"
        crudini --set /etc/nova/nova.conf vnc vncserver_listen "0.0.0.0"
        crudini --set /etc/nova/nova.conf vnc vncserver_proxyclient_address $controller_ip
        crudini --set /etc/nova/nova.conf vnc novncproxy_base_url "http://$controller_ip:6080/vnc_auto.html"
        crudini --set /etc/nova/nova.conf glance api_servers "http://$controller_ip:9292"
        crudini --set /etc/nova/nova.conf oslo_concurrency lock_path "/var/lib/nova/tmp"
        crudini --set /etc/nova/nova.conf placement os_region_name RegionOne
        crudini --set /etc/nova/nova.conf placement project_domain_name default
        crudini --set /etc/nova/nova.conf placement project_name service
        crudini --set /etc/nova/nova.conf placement auth_type password
        crudini --set /etc/nova/nova.conf placement user_domain_name default
        crudini --set /etc/nova/nova.conf placement auth_url "http://$controller_ip:35357/v3"
        crudini --set /etc/nova/nova.conf placement username placement
        crudini --set /etc/nova/nova.conf placement password "$PLACEMENT_PASS"
        systemctl enable libvirtd.service openstack-nova-compute.service
        systemctl start libvirtd.service openstack-nova-compute.service
    elif [ "$1" = "neutron" ];then
        yum -y install openstack-neutron-linuxbridge ebtables ipset
        crudini --set /etc/neutron/neutron.conf DEFAULT transport_url "rabbit://openstack:$RABBIT_PASS@$controller_ip"
        crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
        crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_uri "http://$controller_ip:5000"
        crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_url "http://$controller_ip:35357"
        crudini --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers "$controller_ip:11211"
        crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
        crudini --set /etc/neutron/neutron.conf keystone_authtoken project_domain_name default
        crudini --set /etc/neutron/neutron.conf keystone_authtoken user_domain_name default
        crudini --set /etc/neutron/neutron.conf keystone_authtoken project_name service
        crudini --set /etc/neutron/neutron.conf keystone_authtoken username neutron
        crudini --set /etc/neutron/neutron.conf keystone_authtoken password $NEUTRON_DBPASS
        crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp
        crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini linux_bridge physical_interface_mappings "provider:eth0"
        crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan enable_vxlan true
        crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan local_ip $compute_ip
        crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan l2_population true
        crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup enable_security_group true
        crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini firewall_driver "neutron.agent.linux.iptables_firewall.IptablesFirewallDriver"
        crudini --set /etc/nova/nova.conf neutron url "http://$controller_ip:9696"
        crudini --set /etc/nova/nova.conf neutron auth_url "http://$controller_ip:35357"
        crudini --set /etc/nova/nova.conf neutron auth_type password
        crudini --set /etc/nova/nova.conf neutron project_domain_name default
        crudini --set /etc/nova/nova.conf neutron user_domain_name default
        crudini --set /etc/nova/nova.conf neutron region_name RegionOne
        crudini --set /etc/nova/nova.conf neutron project_name service
        crudini --set /etc/nova/nova.conf neutron username neutron
        crudini --set /etc/nova/nova.conf neutron password $NEUTRON_DBPASS
        systemctl restart openstack-nova-compute.service
        systemctl enable neutron-linuxbridge-agent.service
        systemctl start neutron-linuxbridge-agent.service
    fi
}

### script start ###
case $1 in
--check)
    openstack_check
;;
--install)
    openstack_install $2
;;
*)
    usage
;;
esac
