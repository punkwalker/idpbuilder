package localbuild

import (
	"context"
	"embed"

	"github.com/cnoe-io/idpbuilder/api/v1alpha1"
	"github.com/cnoe-io/idpbuilder/pkg/k8s"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	ctrl "sigs.k8s.io/controller-runtime"
)

const (
	awsAgentNamespace    string = "kube-system"
	awsAgentManifestPath string = "resources/aws-agent/k8s"
)

//go:embed resources/aws-agent/k8s/*
var installAWSAgentFS embed.FS

func RawAWSInstaceProfileInstallResources(templateData any, config v1alpha1.PackageCustomization, scheme *runtime.Scheme) ([][]byte, error) {
	return k8s.BuildCustomizedManifests(config.FilePath, awsAgentManifestPath, installAWSAgentFS, scheme, templateData)
}

func (r *LocalbuildReconciler) ReconcileAWSAgent(ctx context.Context, req ctrl.Request, resource *v1alpha1.Localbuild) (ctrl.Result, error) {
	awsAgent := EmbeddedInstallation{
		name:         "AWS Instance Profile Agent",
		resourcePath: awsAgentManifestPath,
		resourceFS:   installAWSAgentFS,
		namespace:    awsAgentNamespace,
		monitoredResources: map[string]schema.GroupVersionKind{
			"aws-agent": {
				Group:   "apps",
				Version: "v1",
				Kind:    "DaemonSet",
			},
		},
	}

	if result, err := awsAgent.Install(ctx, req, resource, r.Client, r.Scheme, r.Config); err != nil {
		return result, err
	}

	resource.Status.AWSAgent.Available = true
	return ctrl.Result{}, nil
}
