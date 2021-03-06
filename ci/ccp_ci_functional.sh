#!/bin/bash
mark_failure()
{
    echo "====================CI-failed====================="
    echo "$1"
    echo "=================================================="
    if [ $CI_DEBUG -eq 0 ]
    then
        echo "CI is complete, releasing the nodes."
        cico node done $cico_node_key
    else
        echo "====================================================================="
        echo "DEBUG mode is set for CI, keeping the nodes for 2 hour for debugging."
        echo "====================================================================="
        sleep $DEBUG_PERIOD
        cico node done $cico_node_key
    fi
    exit 1
}

set +e
export CICO_API_KEY=$(cat ~/duffy.key)
rtn_code=0
# debug period = 2 hours = 7200 seconds
DEBUG_PERIOD=7200

echo "Get nodes from duffy pool"
IFS=' ' read -ra node_details <<< $(cico node get --count 4 -f value -c hostname -c ip_address -c comment)
ansible_node_host=${node_details[0]}.ci.centos.org
ansible_node=${node_details[1]}
nfs_node=${node_details[3]}.ci.centos.org
nfs_node_ip=${node_details[4]}
openshift_1_node=${node_details[6]}.ci.centos.org
openshift_1_node_ip=${node_details[7]}
openshift_2_node=${node_details[9]}.ci.cento.org
openshift_2_node_ip=${node_details[10]}
cico_node_key=${node_details[11]}
cluster_subnet_ip="172.19.2.0"

if [ ${#cico_node_key} -le 3 ]
then
    cico_node_key=${node_details[2]}
    mark_failure "Could not get nodes from CICO exiting"
fi

echo "=========================Node Details========================"
echo "Ansible node hostname: $ansible_node_host"
echo "Ansible node: $ansible_node"
echo "NFS node: $nfs_node"
echo "NFS node IP: $nfs_node_ip"
echo "Openshift Node 1: $openshift_1_node"
echo "Openshift Node 1 IP: $openshift_1_node_ip"
echo "Openshift Node 2: $openshift_2_node"
echo "Openshift Node 2 IP: $openshift_2_node_ip"
echo "Node hash: $cico_node_key"
echo "Cluster subnet: $cluster_subnet_ip"
echo "=============================================================\n\n"

git_repo=$1
git_branch=$2
git_actual_commit=$3
CI_DEBUG=$4

echo "========================Git repo details====================="
echo "Base git repo: $git_repo "
echo "Base git branch: $git_branch"
echo "Acutal git commit: $git_actual_commit"
echo "DEBUG mode is set to: $CI_DEBUG"
echo "=============================================================\n\n"

export sshopts="-tt -o LogLevel=quiet -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -l root"
export sshoptserr="-tt -o LogLevel=error -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -l root"
echo "Create etc hosts in ansible node"
ssh $sshopts $ansible_node "echo \"$openshift_1_node_ip $openshift_1_node\" >> /etc/hosts"
ssh $sshopts $ansible_node "echo \"$openshift_2_node_ip $openshift_2_node\" >> /etc/hosts"
ssh $sshopts $ansible_node "echo \"$nfs_node_ip $nfs_node\" >> /etc/hosts"

echo "Add ssh keys to all the nodes"
# generate ssh key for ansible node
ssh $sshopts $ansible_node 'rm -rf ~/.ssh/id_rsa* && ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa' >> /dev/null
public_key=$(ssh $sshopts $ansible_node 'cat ~/.ssh/id_rsa.pub')

# Add public key to all the ci nodes
for node in {$nfs_node_ip,$openshift_1_node_ip,$openshift_2_node_ip}
do
    ssh $sshopts $node "echo \"$public_key\" >> ~/.ssh/authorized_keys"
done

echo "Add ssh fringer prints for all node to ansible controller"
for node in {$nfs_node,$openshift_1_node,$openshift_2_node}
do
    ssh $sshopts $ansible_node "ssh-keyscan -t rsa,dsa $node 2>/dev/null >> ~/.ssh/known_hosts"
done

echo "Setup ansible controller node for running openshift 311 deployment"
# setup ansible node
ssh $sshopts $ansible_node 'yum install -y git && yum install -y rsync && yum install -y gcc libffi-devel python-devel openssl-devel && yum install -y epel-release && yum install -y PyYAML python-networkx python-nose python-pep8 python-jinja2 rsync centos-release-openshift-origin311.noarch && yum install -y ansible openshift-ansible' >> /dev/null

#fix for python-docker-py issue in openshift-ansible
#https://github.com/openshift/openshift-ansible/issues/10440
ssh $sshopts $ansible_node sed -i "s/python-docker\'/python-docker-py\'/g" /usr/share/ansible/openshift-ansible/playbooks/init/base_packages.yml

echo "Copy source code to ansible controller node"
rsync -e "ssh -t -o LogLevel=error -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -l root" -Ha $(pwd)/ $ansible_node:/opt/ccp-openshift

echo "Prepare ansible inventory for service setup"
# generate inventory file for service deployment
ssh $sshoptserr $ansible_node sed -i "s/nfs_serv/$nfs_node/g" /opt/ccp-openshift/provision/hosts.ci
ssh $sshoptserr $ansible_node sed -i "s/openshift_1/$openshift_1_node/g" /opt/ccp-openshift/provision/hosts.ci
ssh $sshoptserr $ansible_node sed -i "s/openshift_2/$openshift_2_node/g" /opt/ccp-openshift/provision/hosts.ci
ssh $sshoptserr $ansible_node sed -i "s/openshift_ip_1/$openshift_1_node_ip/g" /opt/ccp-openshift/provision/hosts.ci
ssh $sshoptserr $ansible_node sed -i "s/openshift_ip_2/$openshift_2_node_ip/g" /opt/ccp-openshift/provision/hosts.ci
ssh $sshoptserr $ansible_node sed -i "s/cluster_subnet_ip/$cluster_subnet_ip/g" /opt/ccp-openshift/provision/hosts.ci
ssh $sshoptserr $ansible_node sed -i "s/oc_username/cccp/g" /opt/ccp-openshift/provision/hosts.ci
ssh $sshoptserr $ansible_node sed -i "s/oc_passwd/developer/g" /opt/ccp-openshift/provision/hosts.ci
inventory_updated=$?

if [ $inventory_updated -ne 0 ]
then
    mark_failure "Source code is not in proper location"
fi

echo "Run ansible playbook for setting service"
ssh $sshoptserr $ansible_node "cd /opt/ccp-openshift/provision && ansible-playbook -i /opt/ccp-openshift/provision/hosts.ci main.yaml" >> /tmp/service_provision_logs.txt
service_setup_done=$?

if [ $service_setup_done -ne 0 ]
then
    echo "===========================Service provision logs========================"
    cat /tmp/service_provision_logs.txt
    echo "========================================================================="
    mark_failure "Error deploying the service in CICO"
fi

echo "Build Jenkins slave image to include the code base in this PR"
ssh $sshoptserr $openshift_1_node_ip "cd /opt/ccp-openshift && docker build -t $nfs_node:5000/pipeline-images/ccp-openshift-slave:latest -f Dockerfiles/ccp-openshift-slave/Dockerfile . && docker push $nfs_node:5000/pipeline-images/ccp-openshift-slave:latest" >> /tmp/slave_image_build_logs.txt
slave_image_built=$?

if [ $slave_image_built -ne 0 ]
then
    echo "==========================Slave image build logs==============================="
    cat /tmp/slave_image_build_logs.txt
    echo "==============================================================================="
    mark_failure "ERROR: Jenkins slave image could not be built or pushed to the registry"
fi


echo "Cluster is set lets go for tests"

echo "Setting variables for pipeline run"

export REGISTRY_URL=$nfs_node:5000
export CONTAINER_INDEX_REPO=https://github.com/CentOS/container-index
export CONTAINER_INDEX_BRANCH=ci
export CONTAINER_INDEX_DELETE_CHECK_BRANCH=ci-delete-check
export FROM_ADDRESS=container-build-reports@centos.org
export SMTP_SERVER=smtp://mail.centos.org
export CCP_OPENSHIFT_SLAVE_IMAGE=$nfs_node:5000/pipeline-images/ccp-openshift-slave:latest

echo "Delete build configs if present"
ssh $sshoptserr $openshift_1_node_ip "oc login --username='cccp' --password='developer'"
ssh $sshoptserr $openshift_1_node_ip 'for i in `oc get bc -o name`; do oc delete $i; done'

echo "Command to run"
echo "cd /opt/ccp-openshift && oc process REGISTRY_URL=${REGISTRY_URL} -p NAMESPACE=cccp -p CONTAINER_INDEX_REPO=${CONTAINER_INDEX_REPO} -p CONTAINER_INDEX_BRANCH=${CONTAINER_INDEX_BRANCH} -p FROM_ADDRESS=${FROM_ADDRESS} -p SMTP_SERVER=${SMTP_SERVER} -p CCP_OPENSHIFT_SLAVE_IMAGE=${CCP_OPENSHIFT_SLAVE_IMAGE} -f seed-job/buildtemplate.yaml | oc create -f -"

ssh $sshoptserr $openshift_1_node_ip "cd /opt/ccp-openshift && oc process REGISTRY_URL=${REGISTRY_URL} -p NAMESPACE=cccp -p CONTAINER_INDEX_REPO=${CONTAINER_INDEX_REPO} -p CONTAINER_INDEX_BRANCH=${CONTAINER_INDEX_BRANCH} -p FROM_ADDRESS=${FROM_ADDRESS} -p SMTP_SERVER=${SMTP_SERVER} -p CCP_OPENSHIFT_SLAVE_IMAGE=${CCP_OPENSHIFT_SLAVE_IMAGE} -f seed-job/buildtemplate.yaml | oc create -f -"
seed_job_created=$?

if [ $seed_job_created -ne 0 ]
then
    mark_failure "Error while creating seed job build config"
fi

echo "Waiting for seed job to complete"
index_read_done=$(ssh $sshopts $openshift_1_node_ip "oc get builds seed-job-1 -o template --template={{.status.phase}}")
echo "Current build status: $index_read_done"

while [[ $index_read_done != 'Complete' && $index_read_done != 'Failed' ]]
do
    sleep 30
    index_read_done=$(ssh $sshopts $openshift_1_node_ip "oc get builds seed-job-1 -o template --template={{.status.phase}}")
done

echo "===========================seed-job-log================="
ssh $sshoptserr $nfs_node_ip "cat /jenkins/jobs/cccp/jobs/cccp-seed-job/builds/1/log"
echo "========================================================"

if [ $index_read_done == 'Failed' ]
then
    mark_failure "ERROR: seed-job failed to process the index"
fi

echo "create CI success build pipeline for master job"
ssh $sshoptserr $openshift_1_node_ip "cd /opt/ccp-openshift && oc process -p CCP_OPENSHIFT_SLAVE_IMAGE=${CCP_OPENSHIFT_SLAVE_IMAGE} -f ci/cisuccessjob.yaml | oc create -f -"

echo "Start ci success pipeline for master job"
build_id=$(ssh $sshoptserr $openshift_1_node_ip "oc start-build ci-success-job -n cccp -o name")

echo "Build started with build id: $build_id"

build_id=$(echo $build_id|tr -d '"'|tr -d '\r')

echo "Trimmed build id is: ===$build_id==="

echo "Waiting for the ci to start"
build_status=$(ssh $sshopts $openshift_1_node_ip "oc get ${build_id} -o template --template={{.status.phase}}")
echo "Current build status: $build_status"

echo "Waiting for the job to complete"
while [[ $build_status != 'Complete' && $build_status != 'Failed' ]]
do
    sleep 30
    build_status=$(ssh $sshopts $openshift_1_node_ip "oc get ${build_id} -o template --template={{.status.phase}}")
done

if [ $build_status == 'Failed' ]
then
    echo "=========================Success check build logs==================="
    ssh $sshoptserr $nfs_node_ip "cat /jenkins/jobs/cccp/jobs/cccp-bamachrn-python-release/builds/lastFailedBuild/log"
    echo "===================================================================="
    mark_failure "Success build check failed: FAILURE"
    echo "===================================================================="
else
    echo "=========================Success check build logs==================="
    ssh $sshoptserr $nfs_node_ip "cat /jenkins/jobs/cccp/jobs/cccp-bamachrn-python-release/builds/lastSuccessfulBuild/log"
    echo "===================================================================="
    echo "Success Build check Passed: SUCCESS"
    echo "===================================================================="
fi

echo "create CI failure build pipeline for master job"
ssh $sshoptserr $openshift_1_node_ip "cd /opt/ccp-openshift && oc process -p CCP_OPENSHIFT_SLAVE_IMAGE=${CCP_OPENSHIFT_SLAVE_IMAGE} -f ci/cifailurejob.yaml | oc create -f -"

echo "Start ci failure pipeline for master job"
build_id=$(ssh $sshoptserr $openshift_1_node_ip "oc start-build ci-failure-job -n cccp -o name")

echo "Build started with build id: $build_id"

build_id=$(echo $build_id|tr -d '"'|tr -d '\r')

echo "Trimmed build id is: ===$build_id==="

echo "Waiting for the ci to start"
build_status=$(ssh $sshopts $openshift_1_node_ip "oc get ${build_id} -o template --template={{.status.phase}}")
echo "Current build status: $build_status"

echo "Waiting CI for Fail check to complete"
while [[ $build_status != 'Complete' && $build_status != 'Failed' ]]
do
    sleep 30
    build_status=$(ssh $sshopts $openshift_1_node_ip "oc get ${build_id} -o template --template={{.status.phase}}")
done

echo "========================Master Job Fail check build logs==========================="
ssh $sshoptserr $nfs_node_ip "cat /jenkins/jobs/cccp/jobs/cccp-nshaikh-build-fail-test-latest/builds/lastFailedBuild/log"
echo "========================================================================"

if [ $build_status == 'Failed' ]
then
    mark_failure "Failed build check failed: FAILURE"
else
    echo "Failed Build check Passed: SUCCESS"
fi

echo "======================checking for seedjob functions================="
echo "Creating seedjob pipeline for checking seed job functionalities"
ssh $sshoptserr $openshift_1_node_ip "cd /opt/ccp-openshift && oc process REGISTRY_URL=${REGISTRY_URL} -p NAMESPACE=cccp -p CONTAINER_INDEX_REPO=${CONTAINER_INDEX_REPO} -p CONTAINER_INDEX_BRANCH=${CONTAINER_INDEX_DELETE_CHECK_BRANCH} -p FROM_ADDRESS=${FROM_ADDRESS} -p SMTP_SERVER=${SMTP_SERVER} -p CCP_OPENSHIFT_SLAVE_IMAGE=${CCP_OPENSHIFT_SLAVE_IMAGE} -f seed-job/buildtemplate.yaml | oc replace -f -"
seed_job_replaced=$?

if [ $seed_job_replaced -ne 0 ]
then
    mark_failure "Seed job config is not getting updated"
fi

echo "Re-running the seed job with updated index"
seed_job_build_id=$(ssh $sshoptserr $openshift_1_node_ip "oc start-build seed-job -n cccp -o name")
seed_job_build_id=$(echo $seed_job_build_id|tr -d '"'|tr -d '\r')

echo "Wait for seed job to complete"
build_status=$(ssh $sshopts $openshift_1_node_ip "oc get ${seed_job_build_id} -o template --template={{.status.phase}}")
while [[ $build_status != 'Complete' && $build_status != 'Failed' ]]
do
    sleep 30
    build_status=$(ssh $sshopts $openshift_1_node_ip "oc get ${seed_job_build_id} -o template --template={{.status.phase}}")
done

echo "==========================Seed job Re-run logs========================"
ssh $sshoptserr $nfs_node_ip "cat /jenkins/jobs/cccp/jobs/cccp-seed-job/builds/2/log"
echo "======================================================================"

if [ $build_status == 'Failed' ]
then
    mark_failure "Seed job could not complete: FAILURE"
fi

echo "Running CI job for seedjob check"
ssh $sshoptserr $openshift_1_node_ip "cd /opt/ccp-openshift && oc process -p SEEDJOB_BUILD_ID=${seed_job_build_id} -p CCP_OPENSHIFT_SLAVE_IMAGE=${CCP_OPENSHIFT_SLAVE_IMAGE} -f ci/ciseedjobcheck.yaml | oc create -f -"

echo "Start ci pipeline for fpailure job"
build_id=$(ssh $sshoptserr $openshift_1_node_ip "oc start-build ci-seed-job-check -n cccp -o name")

echo "Build started with build id: $build_id"

build_id=$(echo $build_id|tr -d '"'|tr -d '\r')

echo "Trimmed build id is: ===$build_id==="

echo "Waiting for the ci to start"
build_status=$(ssh $sshopts $openshift_1_node_ip "oc get ${build_id} -o template --template={{.status.phase}}")
echo "Current build status: $build_status"

echo "Wait for CI for Seed Job check to complete"
while [[ $build_status != 'Complete' && $build_status != 'Failed' ]]
do
    sleep 30
    build_status=$(ssh $sshopts $openshift_1_node_ip "oc get ${build_id} -o template --template={{.status.phase}}")
done

echo "========================Seed job check logs==========================="
ssh $sshoptserr $nfs_node_ip "cat /jenkins/jobs/cccp/jobs/cccp-ci-seed-job-check/builds/1/log"
echo "========================================================================"

if [ $build_status == 'Failed' ]
then
    mark_failure "CI failed on seed job functionality check: FAILURE"
else
    echo "Seed Job check Passed: SUCCESS"
fi

echo "========================================================================"

if [ $CI_DEBUG -eq 0 ]
then
    echo "Functional CI is complete, releasing the nodes."
    cico node done $cico_node_key
else
    echo "============================================================"
    echo "DEBUG mode is set for CI, keeping nodes for debugging"
    echo "============================================================"
    sleep $DEBUG_PERIOD
    cico node done $cico_node_key
fi
