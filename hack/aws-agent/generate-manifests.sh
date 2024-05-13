#!/bin/bash

INSTALL_YAML="pkg/controllers/localbuild/resources/aws-agent/k8s/aws-agent.yaml"
AWS_AGENT_DIR="./hack/aws-agent"


echo "# AWS_AGENT INSTALL RESOURCES" > ${INSTALL_YAML}
echo "# This file is auto-generated with 'hack/aws-agent/generate-manifests.sh'" >> ${INSTALL_YAML}
kustomize build ${AWS_AGENT_DIR} >> ${INSTALL_YAML}
