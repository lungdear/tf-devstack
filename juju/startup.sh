#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"

export WORKSPACE="$(pwd)"

export CONTAINER_REGISTRY
export CONTRAIL_CONTAINER_TAG
export NODE_IP
export CONTROLLER_NODES

# default env variables
export JUJU_REPO=${JUJU_REPO:-$WORKSPACE/contrail-charms}
export ORCHESTRATOR=${ORCHESTRATOR:-openstack}  # openstack | kubernetes
export CLOUD=${CLOUD:-aws}  # aws | manual
export UBUNTU_SERIES=${UBUNTU_SERIES:-'bionic'}

AWS_ACCESS_KEY=${AWS_ACCESS_KEY:-''}
AWS_SECRET_KEY=${AWS_SECRET_KEY:-''}
AWS_REGION=${AWS_REGION:-'us-east-1'}

SKIP_JUJU_BOOTSTRAP=${SKIP_JUJU_BOOTSTRAP:-false}
SKIP_JUJU_ADD_MACHINES=${SKIP_JUJU_ADD_MACHINES:-false}
SKIP_DEPLOY_ORCHESTRATOR=${SKIP_DEPLOY_ORCHESTRATOR:-false}
SKIP_DEPLOY_CONTRAIL=${SKIP_DEPLOY_CONTRAIL:-false}

# install juju
if [ $SKIP_JUJU_BOOTSTRAP == false ]; then
    echo "Installing JuJu, setup and bootstrap JuJu controller"
    $my_dir/../common/deploy_juju.sh
fi

# add-machines to juju
if [ $SKIP_JUJU_ADD_MACHINES == false ]; then
    echo "Add machines to Jujus"
    $my_dir/../common/add_juju_machines.sh
fi

# deploy orchestrator
if [ $SKIP_DEPLOY_ORCHESTRATOR == false ]; then
    echo "Deploy ${ORCHESTRATOR^}"
    if [[ $ORCHESTRATOR == 'openstack' ]] ; then
        export BUNDLE_TEMPLATE="$my_dir/bundle_os_${CLOUD}.yaml.tmpl"
    elif [[ $ORCHESTRATOR == 'kubernetes' ]] ; then
        export BUNDLE_TEMPLATE="$my_dir/bundle_k8s_${CLOUD}.yaml.tmpl"
    fi
    $my_dir/../common/deploy_juju_bundle.sh
fi

# deploy contrail
if [ $SKIP_DEPLOY_CONTRAIL == false ]; then
    echo "Deploy Contrail"
    export BUNDLE_TEMPLATE="$my_dir/bundle_contrail.yaml.tmpl"

    # get contrail-charms
    [ -d $JUJU_REPO ] || git clone https://github.com/Juniper/contrail-charms -b R5 $JUJU_REPO
    cd $JUJU_REPO

    $my_dir/../common/deploy_juju_bundle.sh

    # add relations between orchestrator and Contrail
    if [[ $ORCHESTRATOR == 'openstack' ]] ; then        
        juju add-relation contrail-controller ntp
        juju add-relation contrail-keystone-auth keystone
        juju add-relation contrail-openstack neutron-api
        juju add-relation contrail-openstack heat
        juju add-relation contrail-openstack nova-compute
        juju add-relation contrail-agent:juju-info nova-compute:juju-info
    elif [[ $ORCHESTRATOR == 'kubernetes' ]] ; then
        juju add-relation contrail-kubernetes-node:cni kubernetes-master:cni
        juju add-relation contrail-kubernetes-node:cni kubernetes-worker:cni
        juju add-relation contrail-kubernetes-master:contrail-controller contrail-controller:contrail-controller
        juju add-relation contrail-kubernetes-master:kube-api-endpoint kubernetes-master:kube-api-endpoint
        juju add-relation contrail-agent:juju-info kubernetes-worker:juju-info
        juju add-relation contrail-kubernetes-master:contrail-kubernetes-config contrail-kubernetes-node:contrail-kubernetes-config
    fi

    if [[ $ORCHESTRATOR == 'kubernetes' && $CLOUD == 'manual' ]]; then
        JUJU_MACHINES=`timeout -s 9 30 juju machines --format tabular | tail -n +2 | grep -v \/lxd\/ | awk '{print $1}'`
        # fix /etc/hosts
        for machine in $JUJU_MACHINES ; do
            juju_node_ip=`juju ssh $machine "hostname -i" | tr -d '\r'`
            juju_node_hostname=`juju ssh $machine "hostname" | tr -d '\r'`
            juju ssh $machine "sudo bash -c 'echo $juju_node_ip $juju_node_hostname >> /etc/hosts'" 2>/dev/null
        done
    fi

    # show results
    echo "Deployment scripts are finished"
    echo "Now you can monitor when contrail becomes available with:"
    echo "juju status"
    echo "All applications and units should become active, before you can use Contrail"
    echo "Contrail Web UI will be available at https://$NODE_IP:8143"
fi