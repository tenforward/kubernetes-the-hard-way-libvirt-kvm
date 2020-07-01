#!/bin/bash

. ./config

mkdir -p ./certs/newcerts
cp openssl.cnf ./certs
cd certs
touch index.txt
if [ ! -f serial ]; then
    echo "00" > serial
fi

REQ_COMMAND="openssl req -new -newkey rsa:4096 -config ./openssl.cnf -nodes"
CA_COMMAND="openssl ca -config ./openssl.cnf"

### CA
echo -n "Generating Certificate Authority: "
SUBJECT="${SUBJECT_BASE}/CN=TenForward OreOre CA"
KEY=ca-key.pem
CERT=${CA_CERTS}
if [ ! -f $KEY -o ! -f $CERT ]; then
    openssl req -new -newkey rsa:4096 \
	-x509 -days 365 \
	-config ./openssl.cnf \
	-nodes \
	-subj "$SUBJECT" \
	-out ca.pem \
	-keyout ca-key.pem
    echo "done. key is ca-key.pem, cert is ca.pem."
else
    echo "exists."
fi

### Admin
echo -n "Generating Admin Client Certificate: "
SUBJECT="${SUBJECT_BASE}/CN=admin"
KEY=admin-key.pem
REQ=admin.req
CERT=admin.pem
if [ ! -f $KEY -o ! -f $CERT ]; then
    $REQ_COMMAND \
	-keyout $KEY \
	-out $REQ \
	-subj "$SUBJECT"
    $CA_COMMAND \
	-in $REQ \
	-out $CERT
    echo "done."
else
    echo "exists."
fi

### worker
for w in ${WORKERS[@]}
do
    echo -n "Generating Worker ($w) Certificates: "
    KEY=${w}-key.pem
    CERT=${w}.pem
    SUBJECT="${SUBJECT_BASE}/CN=system:node:${w}.${DOMAIN}"
    if [ ! -f $KEY -o ! -f $CERT ]; then
	$REQ_COMMAND \
	    -keyout $KEY \
	    -out $REQ \
	    -subj "$SUBJECT"
	$CA_COMMAND \
	    -in $REQ \
	    -out $CERT
	echo "done."
    else
	echo "exists."
    fi
    echo "done."
done

# Controller manager client cert
echo -n "Generating Controller Manager Client Certificate: "
SUBJECT="${SUBJECT_BASE}/CN=system:kube-controller-manager"
KEY=kube-controller-manager-key.pem
REQ=kube-controller-manager.req
CERT=kube-controller-manager.pem
if [ ! -f $KEY -o ! -f $CERT ]; then
    $REQ_COMMAND \
	-keyout $KEY \
	-out $REQ \
	-subj "$SUBJECT"
    $CA_COMMAND \
	-in $REQ \
	-out $CERT
    echo "done."
else
    echo "exists."
fi

# Kube proxy
echo -n "Generating Kube Proxy Client Certificate: "
SUBJECT="${SUBJECT_BASE}/CN=system:kube-proxy"
KEY=kube-proxy-key.pem
REQ=kube-proxy.req
CERT=kube-proxy.pem
if [ ! -f $KEY -o ! -f $CERT ]; then
    $REQ_COMMAND \
	-keyout $KEY \
	-out $REQ \
	-subj "$SUBJECT"
    $CA_COMMAND \
	-in $REQ \
	-out $CERT
    echo "done."
else
    echo "exists."
fi

# Scheduler
echo -n "Generating Scheduler Client Certificate: "
SUBJECT="${SUBJECT_BASE}/CN=system:kube-scheduler"
KEY=kube-scheduler-key.pem
REQ=kube-scheduler.req
CERT=kube-scheduler.pem
if [ ! -f $KEY -o ! -f $CERT ]; then
    $REQ_COMMAND \
	-keyout $KEY \
	-out $REQ \
	-subj "$SUBJECT"
    $CA_COMMAND \
	-in $REQ \
	-out $CERT
    echo "done."
else
    echo "exists."
fi

# API server
echo -n "Generation API Server Certificate: "
SUBJECT="${SUBJECT_BASE}/CN=kubernetes"
KEY=kubernetes-key.pem
REQ=kubernetes.req
CERT=kubernetes.pem

SLN_IP=("10.32.0.1")

ALTNAME_FILE="api_sla.conf"
echo "subjectAltName = @alt_names" >> $ALTNAME_FILE
echo >> $ALTNAME_FILE
echo "[ alt_names ]" >> $ALTNAME_FILE

for i in $KUBERNETES_IPS
do
    IP="192.168.111.${i}"
    SLN_IP=("${SLN_IP[@]}" $IP)
done

SLN_IP=("${SLN_IP[@]}"
	"${KUBERNETES_BAREMETAL_ADDRESS}"
	"127.0.0.1")

i=1
for ip in ${SLN_IP[@]}
do
    echo "IP.${i} = ${ip}" >> $ALTNAME_FILE
    i=$(( i+1 ))
done

SLN_DNS=("loadbalancer"
	 "$DOMAIN")

for h in ${KUBERNETES_HOSTNAMES[@]}
do
    SLN_DNS=("${SLN_DNS[@]}"
	     "${h}")
done

i=1
for host in ${SLN_DNS[@]}
do
    echo "DNS.${i} = ${host}" >> $ALTNAME_FILE
    i=$(( i+1 ))
done

cat openssl.cnf $ALTNAME_FILE >> apiserver.cnf

if [ ! -f $KEY -o ! -f $CERT ]; then
    openssl req -new -newkey rsa:4096 \
	    -config $PWD/apiserver.cnf \
	    -nodes \
	    -keyout $KEY \
	    -out $REQ \
	    -subj "$SUBJECT"
    $CA_COMMAND \
	-in $REQ \
	-out $CERT
    echo "done."
else
    echo "exists."
fi

cd ..
