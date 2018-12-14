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
    --- 执行脚本前请检查controller_ip ---
    --- 检查openstack环境 ---
    sh $0 --check
    --- 安装openstack实例 ---
    sh $0 --install <组件名>
EOF
}

DEPLOY_PATH=`getPath`
controller_ip=`crudini --get $DEPLOY_PATH/conf/auto-config default controller_ip`
RABBIT_PASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd RABBIT_PASS`
KEYSTONE_DBPASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd KEYSTONE_DBPASS`
GLANCE_DBPASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd GLANCE_DBPASS`
NOVA_DBPASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd NOVA_DBPASS`
NEUTRON_DBPASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd NEUTRON_DBPASS`
PLACEMENT_PASS=`crudini --get $DEPLOY_PATH/conf/auto-config passwd PLACEMENT_PASS`
METADATA_SECRET=`crudini --get $DEPLOY_PATH/conf/auto-config passwd METADATA_SECRET`

openstack_check(){
## 坚持openstack基础环境
    echo "开始检测openstack controller节点"
    echo "############################### mariadb #######################################"
    systemctl status mariadb.service
    echo "############################### rabbitmq #######################################"
    systemctl status rabbitmq-server.service
    echo "############################### memcached #######################################"
    systemctl status memcached.service
    echo "############################### keystone #######################################"
    systemctl status httpd.service
    echo "############################### glance #######################################"
    systemctl status openstack-glance-api.service openstack-glance-registry.service
    echo "############################### nova #######################################"
    systemctl status openstack-nova-api.service openstack-nova-consoleauth.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service
    echo "############################### neutron #######################################"
    systemctl status neutron-server.service neutron-linuxbridge-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service neutron-l3-agent.service
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
        echo "allow 172.16.0.0/16" >> /etc/chrony.conf
        systemctl restart chronyd.service
    elif [ "$1" = "rpm" ];then
        ## 安装openstack rpm
        yum -y install centos-release-openstack-ocata
        yum -y upgrade
        yum -y install python-openstackclient
        yum -y install openstack-selinux
    elif [ "$1" = "mysql" ];then
        yum -y install mariadb mariadb-server python2-PyMySQL
        yum -y install expect
        crudini --set /etc/my.cnf.d/openstack.cnf mysqld bind-address $controller_ip
        crudini --set /etc/my.cnf.d/openstack.cnf mysqld default-storage-engine innodb
        crudini --set /etc/my.cnf.d/openstack.cnf mysqld innodb_file_per_table on
        crudini --set /etc/my.cnf.d/openstack.cnf mysqld max_connections 4096
        crudini --set /etc/my.cnf.d/openstack.cnf mysqld collation-server utf8_general_ci
        crudini --set /etc/my.cnf.d/openstack.cnf mysqld character-set-server utf8
        crudini --set /etc/systemd/system.conf Manager DefaultLimitNOFILE 100000
        crudini --set /etc/systemd/system.conf Manager DefaultLimitNPROC 100000
        crudini --set /usr/lib/systemd/system/mariadb.service Service LimitNOFILE 50000
        crudini --set /usr/lib/systemd/system/mariadb.service Service LimitNPROC 50000
        systemctl daemon-reload
        systemctl enable mariadb.service
        systemctl start mariadb.service
        sleep 3
        sh $DEPLOY_PATH/common/mysql.sh
        sleep 3
        sh $DEPLOY_PATH/common/database.sh
    elif [ "$1" = "rabbitmq" ];then
        yum -y install rabbitmq-server
        systemctl enable rabbitmq-server.service
        systemctl start rabbitmq-server.service
        rabbitmqctl add_user openstack $RABBIT_PASS
        rabbitmqctl set_permissions openstack ".*" ".*" ".*"
    elif [ "$1" = "memcached" ];then
        yum -y install memcached python-memcached
        sed -i "s/127.0.0.1/$controller_ip/g" /etc/sysconfig/memcached
        systemctl enable memcached.service
        systemctl start memcached.service
    elif [ "$1" = "keystone" ];then
        yum -y install openstack-keystone httpd mod_wsgi
        crudini --set /etc/keystone/keystone.conf database connection mysql+pymysql://keystone:$KEYSTONE_DBPASS@$controller_ip/keystone
        crudini --set /etc/keystone/keystone.conf token provider fernet
        su -s /bin/sh -c "keystone-manage db_sync" keystone
        keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
        keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
        keystone-manage bootstrap --bootstrap-password $KEYSTONE_DBPASS --bootstrap-admin-url http://$controller_ip:35357/v3/ --bootstrap-internal-url http://$controller_ip:5000/v3/ --bootstrap-public-url http://$controller_ip:5000/v3/ --bootstrap-region-id RegionOne
        echo ServerName $controller_ip >> /etc/httpd/conf/httpd.conf
        ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
        systemctl enable httpd.service
        systemctl start httpd.service
        sh $DEPLOY_PATH/common/key.sh
        \cp $DEPLOY_PATH/common/admin-openrc.sh /home/
        \cp $DEPLOY_PATH/common/demo-openrc.sh /home/
    elif [ "$1" = "glance" ];then
        source /home/admin-openrc.sh
        openstack user create --domain default --password $GLANCE_DBPASS glance
        openstack role add --project service --user glance admin
        openstack service create --name glance --description "OpenStack Image" image
        openstack endpoint create --region RegionOne image public http://$controller_ip:9292
        openstack endpoint create --region RegionOne image internal http://$controller_ip:9292
        openstack endpoint create --region RegionOne image admin http://$controller_ip:9292
        yum -y install openstack-glance
        crudini --set /etc/glance/glance-api.conf database connection "mysql+pymysql://glance:$GLANCE_DBPASS@$controller_ip/glance"
        crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_uri "http://$controller_ip:5000"
        crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_url "http://$controller_ip:35357"
        crudini --set /etc/glance/glance-api.conf keystone_authtoken memcached_servers "$controller_ip:11211"
        crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_type password
        crudini --set /etc/glance/glance-api.conf keystone_authtoken project_domain_name default
        crudini --set /etc/glance/glance-api.conf keystone_authtoken user_domain_name default
        crudini --set /etc/glance/glance-api.conf keystone_authtoken project_name service
        crudini --set /etc/glance/glance-api.conf keystone_authtoken username glance
        crudini --set /etc/glance/glance-api.conf keystone_authtoken password $GLANCE_DBPASS
        crudini --set /etc/glance/glance-api.conf paste_deploy flavor keystone
        crudini --set /etc/glance/glance-api.conf glance_store stores "file,http"
        crudini --set /etc/glance/glance-api.conf glance_store default_store "file"
        crudini --set /etc/glance/glance-api.conf glance_store filesystem_store_datadir "/var/lib/glance/images/"
        crudini --set /etc/glance/glance-registry.conf database connection "mysql+pymysql://glance:$GLANCE_DBPASS@$controller_ip/glance"
        crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_uri "http://$controller_ip:5000"
        crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_url "http://$controller_ip:35357"
        crudini --set /etc/glance/glance-registry.conf keystone_authtoken memcached_servers "$controller_ip:11211"
        crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_type password
        crudini --set /etc/glance/glance-registry.conf keystone_authtoken project_domain_name default
        crudini --set /etc/glance/glance-registry.conf keystone_authtoken user_domain_name default
        crudini --set /etc/glance/glance-registry.conf keystone_authtoken project_name service
        crudini --set /etc/glance/glance-registry.conf keystone_authtoken username glance
        crudini --set /etc/glance/glance-registry.conf keystone_authtoken password $GLANCE_DBPASS
        crudini --set /etc/glance/glance-registry.conf paste_deploy flavor keystone
        su -s /bin/sh -c "glance-manage db_sync" glance
        systemctl enable openstack-glance-api.service openstack-glance-registry.service
        systemctl start openstack-glance-api.service openstack-glance-registry.service
    elif [ "$1" = "nova" ];then
        source /home/admin-openrc.sh
        openstack user create --domain default --password $NOVA_DBPASS nova
        openstack role add --project service --user nova admin
        openstack service create --name nova --description "OpenStack Compute" compute
        openstack endpoint create --region RegionOne compute public http://$controller_ip:8774/v2.1
        openstack endpoint create --region RegionOne compute internal http://$controller_ip:8774/v2.1
        openstack endpoint create --region RegionOne compute admin http://$controller_ip:8774/v2.1
        openstack user create --domain default --password $NOVA_DBPASS placement
        openstack role add --project service --user placement admin
        openstack service create --name placement --description "Placement API" placement
        openstack endpoint create --region RegionOne placement public http://$controller_ip:8778
        openstack endpoint create --region RegionOne placement internal http://$controller_ip:8778
        openstack endpoint create --region RegionOne placement admin http://$controller_ip:8778
        yum -y install openstack-nova-api openstack-nova-conductor openstack-nova-console openstack-nova-novncproxy openstack-nova-scheduler openstack-nova-placement-api
        crudini --set /etc/nova/nova.conf DEFAULT enabled_apis "osapi_compute,metadata"
        crudini --set /etc/nova/nova.conf DEFAULT transport_url "rabbit://openstack:$RABBIT_PASS@$controller_ip"
        crudini --set /etc/nova/nova.conf DEFAULT my_ip $controller_ip
        crudini --set /etc/nova/nova.conf DEFAULT use_neutron True
        crudini --set /etc/nova/nova.conf DEFAULT firewall_driver "nova.virt.firewall.NoopFirewallDriver"
        crudini --set /etc/nova/nova.conf api_database connection "mysql+pymysql://nova:$NOVA_DBPASS@$controller_ip/nova_api"
        crudini --set /etc/nova/nova.conf database connection "mysql+pymysql://nova:$NOVA_DBPASS@$controller_ip/nova"
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
        crudini --set /etc/nova/nova.conf vnc vncserver_listen $controller_ip
        crudini --set /etc/nova/nova.conf vnc vncserver_proxyclient_address $controller_ip
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
        sed -i '/<\/VirtualHost>/i\  <Directory />' /etc/httpd/conf.d/00-nova-placement-api.conf
        sed -i '/<\/VirtualHost>/i\    Options All' /etc/httpd/conf.d/00-nova-placement-api.conf
        sed -i '/<\/VirtualHost>/i\    AllowOverride All' /etc/httpd/conf.d/00-nova-placement-api.conf
        sed -i '/<\/VirtualHost>/i\    Require all granted' /etc/httpd/conf.d/00-nova-placement-api.conf
        sed -i '/<\/VirtualHost>/i\  </Directory>' /etc/httpd/conf.d/00-nova-placement-api.conf
        sed -i '/<\/VirtualHost>/i\  <Directory /usr/bin/nova-placement-api>' /etc/httpd/conf.d/00-nova-placement-api.conf
        sed -i '/<\/VirtualHost>/i\    Options All' /etc/httpd/conf.d/00-nova-placement-api.conf
        sed -i '/<\/VirtualHost>/i\    AllowOverride All' /etc/httpd/conf.d/00-nova-placement-api.conf
        sed -i '/<\/VirtualHost>/i\    Require all granted' /etc/httpd/conf.d/00-nova-placement-api.conf
        sed -i '/<\/VirtualHost>/i\  </Directory>' /etc/httpd/conf.d/00-nova-placement
        systemctl restart httpd
        su -s /bin/sh -c "nova-manage api_db sync" nova
        su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
        su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
        su -s /bin/sh -c "nova-manage db sync" nova
        nova-manage cell_v2 list_cells
        systemctl enable openstack-nova-api.service openstack-nova-consoleauth.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service
        systemctl start openstack-nova-api.service openstack-nova-consoleauth.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service
    elif [ "$1" = "neutron" ];then
        sh $DEPLOY_PATH/common/neutron.sh
        sleep 3
        source /home/admin-openrc.sh
        openstack user create --domain default --password $NEUTRON_DBPASS neutron
        openstack role add --project service --user neutron admin
        openstack service create --name neutron --description "OpenStack Networking" network
        openstack endpoint create --region RegionOne network public http://$controller_ip:9696
        openstack endpoint create --region RegionOne network internal http://$controller_ip:9696
        openstack endpoint create --region RegionOne network admin http://$controller_ip:9696
        yum -y install openstack-neutron openstack-neutron-ml2 openstack-neutron-linuxbridge ebtables
        crudini --set /etc/neutron/neutron.conf database connection "mysql+pymysql://neutron:$NEUTRON_DBPASS@$controller_ip/neutron"
        crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
        crudini --set /etc/neutron/neutron.conf DEFAULT service_plugins
        crudini --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips true
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
        crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes true
        crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes true
        crudini --set /etc/neutron/neutron.conf nova auth_url "http://$controller_ip:35357"
        crudini --set /etc/neutron/neutron.conf nova auth_type password
        crudini --set /etc/neutron/neutron.conf nova project_domain_name default
        crudini --set /etc/neutron/neutron.conf nova user_domain_name default
        crudini --set /etc/neutron/neutron.conf nova region_name RegionOne
        crudini --set /etc/neutron/neutron.conf nova project_name service
        crudini --set /etc/neutron/neutron.conf nova username nova
        crudini --set /etc/neutron/neutron.conf nova password $NOVA_DBPASS
        crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path "/var/lib/neutron/tmp"
        crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers "flat,vlan"
        crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types
        crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers "linuxbridge"
        crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security
        crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks provider
        #crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vxlan vni_ranges "1:1000"
        crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_ipset true
        crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini linux_bridge physical_interface_mappings "provider:eth0"
        crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan enable_vxlan false
        #crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan local_ip $controller_ip
        #crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan l2_population true
        crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup enable_security_group true
        crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup firewall_driver "neutron.agent.linux.iptables_firewall.IptablesFirewallDriver"
        crudini --set /etc/neutron/l3_agent.ini DEFAULT interface_driver linuxbridge
        crudini --set /etc/neutron/dhcp_agent.ini DEFAULT interface_driver linuxbridge
        crudini --set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
        crudini --set /etc/neutron/dhcp_agent.ini DEFAULT enable_isolated_metadata true
        crudini --set /etc/neutron/metadata_agent.ini DEFAULT nova_metadata_ip $controller_ip
        crudini --set /etc/neutron/metadata_agent.ini DEFAULT metadata_proxy_shared_secret $METADATA_SECRET
        crudini --set /etc/nova/nova.conf neutron url "http://$controller_ip:9696"
        crudini --set /etc/nova/nova.conf neutron auth_url "http://$controller_ip:35357"
        crudini --set /etc/nova/nova.conf neutron auth_type password
        crudini --set /etc/nova/nova.conf neutron project_domain_name default
        crudini --set /etc/nova/nova.conf neutron user_domain_name default
        crudini --set /etc/nova/nova.conf neutron region_name RegionOne
        crudini --set /etc/nova/nova.conf neutron project_name service
        crudini --set /etc/nova/nova.conf neutron username neutron
        crudini --set /etc/nova/nova.conf neutron password $NEUTRON_DBPASS
        crudini --set /etc/nova/nova.conf neutron service_metadata_proxy true
        crudini --set /etc/nova/nova.conf neutron metadata_proxy_shared_secret $METADATA_SECRET
        ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
        su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
        systemctl restart openstack-nova-api.service
        systemctl enable neutron-server.service neutron-linuxbridge-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service
        systemctl start neutron-server.service neutron-linuxbridge-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service
        systemctl enable neutron-l3-agent.service
        systemctl start neutron-l3-agent.service
    elif [ "$1" = "dashboard" ];then
        yum -y install openstack-dashboard
        \cp $DEPLOY_PATH/conf/openstack-dashboard/local_settings /etc/openstack-dashboard/local_settings
        systemctl restart httpd.service memcached.service
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
