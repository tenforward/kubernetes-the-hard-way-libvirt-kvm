# Provisioning Compute Resources

Kubernetes requires a set of machines to host the Kubernetes control plane and the worker nodes where containers are ultimately run. In this lab you will provision the compute resources required for running a secure and highly available Kubernetes cluster.

## Networking

The Kubernetes [networking model](https://kubernetes.io/docs/concepts/cluster-administration/networking/#kubernetes-model) assumes a flat network in which containers and nodes can communicate with each other. In cases where this is not desired [network policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) can limit how groups of containers are allowed to communicate with each other and external network endpoints.

> Setting up network policies is out of scope for this tutorial.

### Virtual Machines Network

The VM network is a network where all the VMs are executed. Actually this is a virtual network configured as type 'nated', e.g. all VMs will be placed in the same network address range, they will have access to the outside world using the baremetal server virtual bridge as a default gateway (NAT). However, take into account that any remote server won't be able to reach any VM since they are behind the baremetal server.

> Since the baremetal server hosts the virtual infrastructure it is able to connect to any of the VMs. So, as we will see further in this tutorial, anytime you need to execute commands on any of the VMs, you need to connect first to the baremetal server.

By default as commented in the previous sections, there is a default virtual network named as default configured:
```
$ virsh net-list
```
Output expected

```
 名前               状態     自動起動  永続
----------------------------------------------------------
 default              動作中  いいえ (no) いいえ (no)
```

We are going to create a new virtual network to place all the Kubernetes cluster resources:

* The network address range is 192.168.111.0/24
* Name of the network is k8s-net
* The domain of this network is k8s-thw.local. This is important since all VMs in this virtual network will get this domain name as part of its fully qualified name.

![define network](images/define_network.png)

Check the list of virtual networks available:

```
$ virsh net-list 
 名前               状態     自動起動  永続
----------------------------------------------------------
 default            動作中  いいえ (no) いいえ (no)
 k8s-net            動作中  はい (yes)  はい (yes)
```

## Images

To be able to create instances, an image should be provided. In this guide we will use CentOS 7 as the base operating system for all the VMs. We download the CentOS 7 image from mirror site, for example:

```
vmhost# cd (libvirt stroage directory, for example: /var/lib/libvirt/storage)
vmhost# wget http://ftp.jaist.ac.jp/pub/Linux/CentOS/7/isos/x86_64/CentOS-7-x86_64-NetInstall-1908.iso
```

## DNS

It is required to have a proper DNS configuration that must resolve direct and reverse queries of all the VMs. Unlike other similar tutorials, kcli makes really easy to configure a proper DNS resolution of each VM. Everytime you create a new instance it is possible to create a DNS record into **libvirt dnsmasq** running on the baremetal host. It also can even create a /etc/hosts record in the host that executes the instance creation. This information can be found in the kcli official documentation, section [ip, dns and host reservations](https://kcli.readthedocs.io/en/latest/#ip-dns-and-host-reservations)

> There is no need to maintain a DNS server since DNS record can be automatically created when launching a new instance


## Configuring SSH Access

SSH will be used to configure the loadbalancer, controller and worker instances. By leveraging kcli there is no need to manually exchange the ssh key among all the instances. Kcli automatically injects (using cloudinit) the public ssh key from the baremetal server to all the instances at creation time. Therefore, once the instance is up and running you can easily running `kcli ssh vm_name`


## Compute Instances

Each compute instance will be provisioned with a fixed private IP address to simplify the Kubernetes bootstrapping process.

### Kubernetes Controllers

Create three compute instances which will host the Kubernetes **control plane**. Basically we are creating 3 new instances configured with:

- CentOS image as OS
- 16 GB disk
- Connected to the k8s-net (192.168.111.0/24)
- 16GB of memory and 1 vCPus
- Create a DNS record, in this case ${node}.k8s-thw.local which will included in libvirt's dnsmasq
- Reserve the IP, so it is not available to any other VM
- Create an record into baremetal server's /etc/host so it can be reached from outside the virtual network domain as well.
- Execute "yum update -y" once the server is up and running. This command is injected into the cloudinit, so all instances are up to date since the very beginning.

#### Create VMs

We create VMs using virt-manager's UI.

![create vm 1](images/createvm01.png)

and clone VMs from master00 to master01,02.

![clone_vm](images/clonevm01.png)

After complete clone, You should change hostname to master0{1,2} on each host.

```
$ sudo hostnamectl set-hostname master01.k8s-thw.local
```

Verify your masters are up and running

```
vmhost$ virsh list
 Id    名前                         状態
----------------------------------------------------
 5     master01                       実行中
 6     master02                       実行中
 7     master00                       実行中

$ virsh net-dhcp-leases k8s-net
 Expiry Time          MAC アドレス   Protocol  IP address                Hostname        Client ID or DUID
-------------------------------------------------------------------------------------------------------------------
 2020-04-17 14:15:34  52:54:00:5e:53:fb  ipv4      192.168.111.150/24        master00        -
 2020-04-17 14:14:57  52:54:00:b5:06:ff  ipv4      192.168.111.135/24        master01        -
 2020-04-17 14:14:20  52:54:00:bb:7b:85  ipv4      192.168.111.147/24        master02        -
```

#### Assign fixed IP addresses to each master

We use `virsh net-edit` command,

```
vmhost$ virsh net-edit k8s-net
```

then open your editor,

```
<network>
  <name>k8s-net</name>
  <uuid>231ecaaa-88ab-4c38-b955-c91b1dff203b</uuid>
  <forward dev='eth0' mode='nat'>
    <interface dev='eth0'/>
  </forward>
  <bridge name='virbr1' stp='on' delay='0'/>
  <mac address='52:54:00:06:ec:15'/>
  <domain name='k8s-thw.local'/>
  <ip address='192.168.111.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.111.8' end='192.168.111.254'/>
	  <host mac='52:54:00:5e:53:fb' name='master00.k8s-thw.local' ip='192.168.111.150'/> (<- Append!!)
      <host mac='52:54:00:b5:06:ff' name='master01.k8s-thw.local' ip='192.168.111.135'/> (<- Append!!)
 	  <host mac='52:54:00:bb:7b:85' name='master02.k8s-thw.local' ip='192.168.111.147'/> (<- Append!!)
      <host mac='52:54:00:5f:a2:ef' name='loadbalancer.k8s-thw.local' ip='192.168.111.248'/> (<- Append!!)
    </dhcp>
  </ip>
</network>
```

and restart `k8s-net`:

```
vmhost$ virsh net-destroy k8s-net
ネットワーク k8s-net は強制停止されました

vmhost$ virsh net-start k8s-net
ネットワーク k8s-net が起動されました

vmhost$ virsh net-dumpxml k8s-net
<network>
  <name>k8s-net</name>
  <uuid>231ecaaa-88ab-4c38-b955-c91b1dff203b</uuid>
  <forward dev='eth0' mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
    <interface dev='eth0'/>
  </forward>
  <bridge name='virbr1' stp='on' delay='0'/>
  <mac address='52:54:00:06:ec:15'/>
  <domain name='k8s-thw.local'/>
  <ip address='192.168.111.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.111.8' end='192.168.111.254'/>
      <host mac='52:54:00:5e:53:fb' name='master00.k8s-thw.local' ip='192.168.111.150'/>
      <host mac='52:54:00:5e:53:fb' name='master01.k8s-thw.local' ip='192.168.111.135'/>
      <host mac='52:54:00:5e:53:fb' name='master02.k8s-thw.local' ip='192.168.111.147'/>
    </dhcp>
  </ip>
</network>
```

If VMs is running, then you have to restart.

#### register dns host entry to dnsmasq

We use `virsh net-edit` again,

```
$ virsh net-edit k8s-net
```

then,

```
<network>
  <name>k8s-net</name>
  <uuid>231ecaaa-88ab-4c38-b955-c91b1dff203b</uuid>
  <forward dev='eth0' mode='nat'>
    <interface dev='eth0'/>
  </forward>
  <bridge name='virbr1' stp='on' delay='0'/>
  <mac address='52:54:00:06:ec:15'/>
  <!-- Append from here -->
  <domain name='k8s-thw.local'/>
  <dns>
    <host ip='192.168.111.150'>
      <hostname>master00.k8s-thw.local</hostname>
    </host>
    <host ip='192.168.111.135'>
      <hostname>master01.k8s-thw.local</hostname>
    </host>
    <host ip='192.168.111.147'>
      <hostname>master02.k8s-thw.local</hostname>
    </host>
    <host ip='192.168.111.248'>
      <hostname>loadbalancer.k8s-thw.local</hostname>
    </host>
  </dns>
  <!-- Append to here -->
  <ip address='192.168.111.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.111.8' end='192.168.111.254'/>
      <host mac='52:54:00:5e:53:fb' name='master00.k8s-thw.local' ip='192.168.111.150'/>
      <host mac='52:54:00:b5:06:ff' name='master01.k8s-thw.local' ip='192.168.111.135'/>
      <host mac='52:54:00:bb:7b:85' name='master02.k8s-thw.local' ip='192.168.111.147'/>
    </dhcp>
  </ip>
</network>
```

### Load Balancer

In order to have a proper Kubernetes high available environment, a Load balancer is required to distribute the API load. In this case we are going to create an specific instance to run a HAProxy loadbalancer service. First, create an instance to host the load balancer service. Below we are about to create a new instance with:

```
# kcli create vm -i centos7 -P disks=[20] -P nets=[k8s-net] -P memory=2048 -P numcpus=2 \
  -P cmds=["yum -y update"] -P reserverdns=yes -P reserverip=yes -P reserverhost=yes loadbalancer
```

Check your **loadbalancer** instance is up and running

```
kcli list vm
+--------------+--------+-----------------+------------------------------------+-------+---------+--------+
|     Name     | Status |       Ips       |               Source               |  Plan | Profile | Report |
+--------------+--------+-----------------+------------------------------------+-------+---------+--------+
| loadbalancer |   up   |  192.168.111.68 | CentOS-7-x86_64-GenericCloud.qcow2 | kvirt | centos7 |        |
|   master00   |   up   |  192.168.111.72 | CentOS-7-x86_64-GenericCloud.qcow2 | kvirt | centos7 |        |
|   master01   |   up   | 192.168.111.173 | CentOS-7-x86_64-GenericCloud.qcow2 | kvirt | centos7 |        |
|   master02   |   up   | 192.168.111.230 | CentOS-7-x86_64-GenericCloud.qcow2 | kvirt | centos7 |        |
+--------------+--------+-----------------+------------------------------------+-------+---------+--------+
```
#### Load balancer service

The following steps shows how to install a load balancer service using HAProxy in the instance previously created.

We install and configure using ansible.

First, add loadbalancer entry to ansible hosts file:

```
[lb]
loadbalancer.k8s-thw.local
```

then create playbook:

```
$ cat 01_lb_haproxy.yaml 
- hosts: lb
  become: yes
  become_user: root
  tasks:
    - name: install haproxy
      yum:
        name:
          - haproxy
          - policycoreutils-python
        state: present
    - name: place haproxy.cfg
      copy:
        src: ./files/haproxy.cfg
        dest: /etc/haproxy/haproxy.cfg
        owner: root
        group: root
        mode: 0644
    - name: tweak selinux for haproxy
      command: semanage port --add --type http_port_t --proto tcp 6443
    - name: verify haproxy config
      command: haproxy -c -V -f /etc/haproxy/haproxy.cfg
    - name: enable haproxy
      systemd:
        daemon_reload: yes
        name: haproxy
        state: restarted
```

Here, `haproxy.cfg` is a file as follows:

```
global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon
    stats socket /var/lib/haproxy/stats

defaults
    log                     global
    option                  httplog
    option                  dontlognull
    option                  http-server-close
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

listen stats :9000
    stats enable
    stats realm Haproxy\ Statistics
    stats uri /haproxy_stats
    stats auth admin:password
    stats refresh 30
    mode http

frontend  main *:6443
    default_backend mgmt6443
    option tcplog

backend mgmt6443
    balance source
    mode tcp
    # MASTERS 6443
    server master00.k8s-thw.local 192.168.111.72:6443 check
    server master01.k8s-thw.local 192.168.111.173:6443 check
    server master02.k8s-thw.local 192.168.111.230:6443 check
```

then, run `ansible-playbook`:

```
$ ansible-playbook 01_lb_haproxy.yaml
$ ansible lb -a "systemctl status haproxy"
loadbalancer.k8s-thw.local | CHANGED | rc=0 >>
● haproxy.service - HAProxy Load Balancer
   Loaded: loaded (/usr/lib/systemd/system/haproxy.service; disabled; vendor preset: disabled)
   Active: active (running) since Mon 2020-04-20 20:50:47 JST; 5min ago
 Main PID: 3056 (haproxy-systemd)
   CGroup: /system.slice/haproxy.service
           ├─3056 /usr/sbin/haproxy-systemd-wrapper -f /etc/haproxy/haproxy.cfg -p /run/haproxy.pid
           ├─3058 /usr/sbin/haproxy -f /etc/haproxy/haproxy.cfg -p /run/haproxy.pid -Ds
           └─3059 /usr/sbin/haproxy -f /etc/haproxy/haproxy.cfg -p /run/haproxy.pid -Ds

Apr 20 20:50:47 loadbalancer.k8s-thw.local systemd[1]: Started HAProxy Load Balancer.
Apr 20 20:50:47 loadbalancer.k8s-thw.local haproxy-systemd-wrapper[3056]: haproxy-systemd-wrapper: executing /usr/sbin/haproxy -f /etc/haproxy/haproxy.cfg -p /run/haproxy.pid -Ds
```


### Kubernetes Workers

Create a compute instances which will host the Kubernetes worker nodes. We also clone a master node or a loadbalancer VM, and change hostname, define ip address.

```
vmhost$ virsh net-edit k8s-net
vmhost$ virsh net-destroy k8s-net
ネットワーク k8s-net は強制停止されました

vmhost$ virsh net-start k8s-net
ネットワーク k8s-net が起動されました

vmhost$ virsh net-dumpxml k8s-net
<network>
  <name>k8s-net</name>
  <uuid>231ecaaa-88ab-4c38-b955-c91b1dff203b</uuid>
  <forward dev='eth0' mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
    <interface dev='eth0'/>
  </forward>
  <bridge name='virbr1' stp='on' delay='0'/>
  <mac address='52:54:00:06:ec:15'/>
  <domain name='k8s-thw.local'/>
  <dns>
    <host ip='192.168.111.150'>
      <hostname>master00.k8s-thw.local</hostname>
    </host>
    <host ip='192.168.111.135'>
      <hostname>master01.k8s-thw.local</hostname>
    </host>
    <host ip='192.168.111.147'>
      <hostname>master02.k8s-thw.local</hostname>
    </host>
    <host ip='192.168.111.248'>
      <hostname>loadbalancer.k8s-thw.local</hostname>
    </host>
	<!-- append from here -->
    <host ip='192.168.111.98'>
      <hostname>worker00.k8s-thw.local</hostname>
    </host>
	<!-- append to here -->
  </dns>
  <ip address='192.168.111.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.111.8' end='192.168.111.254'/>
      <host mac='52:54:00:5e:53:fb' name='master00.k8s-thw.local' ip='192.168.111.150'/>
      <host mac='52:54:00:b5:06:ff' name='master01.k8s-thw.local' ip='192.168.111.135'/>
      <host mac='52:54:00:bb:7b:85' name='master02.k8s-thw.local' ip='192.168.111.147'/>
      <host mac='52:54:00:5f:a2:ef' name='loadbalancer.k8s-thw.local' ip='192.168.111.248'/>
      <host mac='52:54:00:bf:ca:b4' name='worker00.k8s-thw.local' ip='192.168.111.98'/> <!-- append this line -->
    </dhcp>
  </ip>
</network>

vmhost$ virsh shutdown worker00
vmhost$ virsh start worker00
vmhost$ virsh net-dhcp-leases k8s-net
 Expiry Time          MAC アドレス   Protocol  IP address                Hostname        Client ID or DUID
-------------------------------------------------------------------------------------------------------------------
 2020-04-23 21:50:12  52:54:00:bf:ca:b4  ipv4      192.168.111.98/24         worker00        -


```

> The Kubernetes cluster CIDR range is defined by the Controller Manager's `--cluster-cidr` flag. In this tutorial the cluster CIDR range will be set to `10.200.0.0/16`, which supports 254 subnets.

> Each worker instance requires a pod subnet allocation from the Kubernetes cluster CIDR range. The pod subnet allocation will be used to configure container networking in a later exercise. The `/home/centos/pod_cidr.txt` file contains the subnet assigned to each worker.

```
# kcli create vm -i centos7 -P disks=[50] -P nets=[k8s-net] -P memory=16384 -P numcpus=4 \
 -P cmds=["yum -y update",'echo "10.200.0.0/24" > /home/centos/pod_cidr.txt'] -P reservedns=yes -P reserveip=yes -P reservehost=yes worker00

# kcli create vm -i centos7 -P disks=[50] -P nets=[k8s-net] -P memory=16384 -P numcpus=4 \
  -P cmds=["yum -y update",'echo "10.200.1.0/24" > /home/centos/pod_cidr.txt'] -P reservedns=yes -P reserveip=yes -P reservehost=yes worker01
# kcli create vm -i centos7 -P disks=[50] -P nets=[k8s-net] -P memory=16384 -P numcpus=4 \
-P cmds=["yum -y update",'echo "10.200.2.0/24" > /home/centos/pod_cidr.txt'] -P reservedns=yes -P reserveip=yes -P reservehost=yes worker02
```

### Verification

List the compute instances:

```
# kcli list vm
```

> output

```
+--------------+--------+-----------------+--------+------+---------+--------+
|     Name     | Status |       Ips       | Source | Plan | Profile | Report |
+--------------+--------+-----------------+--------+------+---------+--------+
| loadbalancer |   up   | 192.168.111.248 |        |      |         |        |
|   master00   |   up   | 192.168.111.150 |        |      |         |        |
|   master01   |   up   | 192.168.111.135 |        |      |         |        |
|   master02   |   up   | 192.168.111.147 |        |      |         |        |
|   worker00   |   up   |  192.168.111.98 |        |      |         |        |
+--------------+--------+-----------------+--------+------+---------+--------+
```

## DNS Verification

Once all the instances are deployed, we need to verify that the DNS records are correctly configured before starting the Kubernetes cluster installation. Verify instances are resolved in the baremetal server, note that the records were stored in the /etc/hosts

```
getent hosts 192.168.111.248
```

Output

```
192.168.111.248  loadbalancer loadbalancer.k8s-net
```
Content of the baremetal server /etc/hosts should be similar to the following:

```
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
192.168.111.150 master00.k8s-thw.local master00
192.168.111.135 master01.k8s-thw.local master01
192.168.111.147 master02.k8s-thw.local master02
192.168.111.248 loadbalancer.k8s-thw.local loadbalancer
192.168.111.98  worker00.k8s-thw.local worker00

```

Content of the baremetal server /etc/ansible/hosts:

```
vmhost$ cat /etc/ansible/hosts
[master]
master00.k8s-thw.local
master01.k8s-thw.local
master02.k8s-thw.local

[lb]
loadbalancer.k8s-thw.local

[worker]
worker00.k8s-thw.local

vmhost$ ansible all -m ping
master00.k8s-thw.local | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
worker00.k8s-thw.local | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
loadbalancer.k8s-thw.local | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
master02.k8s-thw.local | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
master01.k8s-thw.local | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
```

Finally, verify that each instance is able to resolve another instance hostname. As shown below, master01 is able to resolved loadbalancer hostname:

```
vmhost$ ssh master01 ping -c 3 loadbalancer
```

Output expected:

```
PING loadbalancer.k8s-thw.local (192.168.111.248) 56(84) bytes of data.
64 bytes from loadbalancer.k8s-thw.local (192.168.111.248): icmp_seq=1 ttl=64 time=0.192 ms
64 bytes from loadbalancer.k8s-thw.local (192.168.111.248): icmp_seq=2 ttl=64 time=0.255 ms
64 bytes from loadbalancer.k8s-thw.local (192.168.111.248): icmp_seq=3 ttl=64 time=0.232 ms

--- loadbalancer.k8s-thw.local ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2000ms
rtt min/avg/max/mdev = 0.192/0.226/0.255/0.028 ms
```

## update pacakges 

Finally, we update all packages on all hosts.

```
$ ansible all -a "sudo yum -y update"
```


Next: [Provisioning a CA and Generating TLS Certificates](04-certificate-authority.md)
