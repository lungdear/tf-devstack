#!/bin/bash -e

source ~/rhosp-environment.sh
source ~/stackrc
export OVERCLOUD_HOSTS="${overcloud_cont_prov_ip} ${overcloud_compute_prov_ip} ${overcloud_ctrlcont_prov_ip}"
/usr/share/openstack-tripleo-heat-templates/deployed-server/scripts/enable-ssh-admin.sh >/dev/null
