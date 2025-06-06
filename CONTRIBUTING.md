# Contributing guide

Welcome to the project, and thanks for considering contributing to this project. 

If you have any questions or need clarifications on topics covered here, please feel free to reach out to us on the [#cnoe-interest](https://cloud-native.slack.com/archives/C05TN9WFN5S) channel on CNCF Slack.

## Setting up a development environment

To get started with the project on your machine, you need to install the following tools:
1. Go 1.21+. See [this official guide](https://go.dev/doc/install) from Go authors.
2. Make. You can install it through a package manager on your system. E.g. Install `build-essential` for Ubuntu systems.
3. Docker. Similar to Make, you can install it through your package manager or [Docker Desktop](https://www.docker.com/products/docker-desktop/).

Once required tools are installed, clone this repository. `git clone https://github.com/cnoe-io/idpbuilder.git`.

Then change your current working directory to the repository root. e.g. `cd idpbuilder`.

All subsequent commands described in this document assumes they are executed from the repository root.
Ensure your docker daemon is running and available. e.g. `docker images` command should not error out.

## Building from the main branch

1. Checkout the main branch. `git checkout main`
2. Build the binary. `make build`. This compiles the project. It will take several minutes for the first time. Example output shown below:
    ```
    ~/idpbuilder$ make build
    test -s /home/ubuntu/idpbuilder/bin/controller-gen && /home/ubuntu/idpbuilder/bin/controller-gen --version | grep -q v0.12.0 || \
    GOBIN=/home/ubuntu/idpbuilder/bin go install sigs.k8s.io/controller-tools/cmd/controller-gen@v0.12.0
    /home/ubuntu/idpbuilder/bin/controller-gen rbac:roleName=manager-role crd webhook paths="./api/..." output:crd:artifacts:config=pkg/controllers/resources
    /home/ubuntu/idpbuilder/bin/controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
    go fmt ./...
    go vet ./...
    go build -o idpbuilder main.go  
    ```
3. Once build finishes, you should have an executable file called `idpbuilder` in the root of the repository.
4. The file is ready to use. Execute this command to confirm: `./idpbuilder --help`


### Testing basic functionalities

To test the very basic functionality of idpbuilder, Run the following command: `./idpbuilder create`

This command creates a kind cluster, expose associated endpoints to your local machine using an ingress controller and deploy the following packages:

1. [Kind](https://kind.sigs.k8s.io/) cluster.
2. [ArgoCD](https://argo-cd.readthedocs.io/en/stable/) resources.
3. [Gitea](https://about.gitea.com/) resources.
4. [Backstage](https://backstage.io/) resources.

They are deployed as ArgoCD Applications with the Gitea repositories set as their sources. 

UIs for Backstage, Gitea, and ArgoCD are accessible on the machine:
* Gitea: https://gitea.cnoe.localtest.me:8443/explore/repos
* Backstage: https://backstage.cnoe.localtest.me:8443/
* ArgoCD: https://argocd.cnoe.localtest.me:8443/applications

#### Getting credentials for packages

Credentials for core packages can be obtained with: 
```bash
idpbuilder get secrets
```

As described in the main readme file, the above command is equivalent to running:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret
kubectl get secrets -n gitea gitea-admin-secret
kubectl get secrets -A -l cnoe.io/cli-secret=true
```

All ArgoCD applications should be synced and healthy. You can check them in the UI or 

```
kubectl get application -n argocd
```

### Upgrading a core component

The process to upgrade a core component: Argo CD, Gitea, Ingress is not so complex but requires to take care about the following points:

- Select the core component to be upgraded and get its current version. See the kustomization file under the `hack/<core-component>` folder and the resource YAML file of the resources to be installed
- Create a ticket describing the new sibling version of the core component to be bumped
- Bump the version part of the kustomization file. Example for argocd: https://github.com/cnoe-io/idpbuilder/blob/main/hack/argo-cd/kustomization.yaml#L4
- Review the patched files to see if changes are needed (new file(s), files to be deleted or files to be changed). Example for argocd: https://github.com/cnoe-io/idpbuilder/blob/main/hack/argo-cd/kustomization.yaml#L7-L16
- Generate the new resources YAML files using the bash script: `generate-manifests.sh`
- Build a new idpbuilder binary
- Test it locally like also using the e2e integration test: `make e2e`
- Review the test cases if changes are needed too
- Update the documentation to detail which version of the core component has been bumped like also for which version (or range of versions) of idpbuilder the new version of the component apply for.

**NOTES**: 
- For some components, it could be possible that you also have to upgrade the version of the go library within the `go.mod` file. Example for gitea: `code.gitea.io/sdk/gitea v0.16.0` 
- For Argo CD, we use a separate GitHub project (till a better solution is implemented) packaging a subset of the Argo CD API. Review carefully this file please: https://github.com/cnoe-io/argocd-api?tab=readme-ov-file#read-this-first

## Preparing a Pull Request

This repository requires a [Developer Certificate of Origin (DCO)](https://developercertificate.org/) signature. 
When preparing to send in a pull request, please make sure your commit is signed. You can achieve this by doing a `git commit --sign` or `git commit -s` when making the commit.

## Project Information

### Default manifests installed by idpbuilder

The default manifests for the core packages are available [here](pkg/controllers/localbuild/resources).
These are generated by scripts. If you want to make changes to them, see below.

#### ArgoCD

ArgoCD manifests are generated using a bash script available [here](./hack/argo-cd/generate-manifests.sh).
This script runs kustomize to modify the basic installation manifests provided by ArgoCD. Modifications include:

1. Prevent notification and dex pods from running. This is done to keep the number of pods running low by default.
2. Use the annotation tracking instead of the default label tracking. Annotation tracking allows you to avoid [problems caused by the label tracking method](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_tracking/). In addition, this configuration is required when using Crossplane.
3. Support for path based routing.

#### Gitea

Gitea manifests are generated using a bash script available [here](./hack/gitea/generate-manifests.sh).
This script runs helm template to generate most files. See the values file for more information.

#### Ingress-nginx

ingress-nginx manifests are generated using a bash script available [here](./hack/ingress-nginx/generate-manifests.sh).
This script runs kustomize to modify the basic installation manifests provided by ingress-nginx.

## Architecture

idpbuilder is made of two phases: CLI and Kubernetes controllers.

![idpbuilder.png](docs/images/idpbuilder.png)

### CLI

When the idpbuilder binary is executed, it starts with the CLI phase.

1. This is the phase where command flags are parsed and translated into relevant Go structs' fields. Most notably the [`LocalBuild`](https://github.com/cnoe-io/idpbuilder/blob/main/api/v1alpha1/localbuild_types.go) struct.
2. Create a Kind cluster, then update the kubeconfig file.
3. Once the kind cluster is started and relevant fields are populated, Kubernetes controllers are started:
*  `LocalbuildReconciler` responsible for bootstrapping the cluster with absolute necessary packages. Creates Custom Resources (CRs) and installs embedded manifests.
*  `RepositoryReconciler` responsible for creating and managing Gitea repository and repository contents.
*  `CustomPackageReconciler` responsible for managing custom packages.
4. They are all managed by a single Kubernetes controller manager.
5. Once controllers are started, CRs corresponding to these controllers are created. For example for Backstage, it creates a GitRepository CR and ArgoCD Application.
6. CLI then waits for these CRs to be ready.

### Controllers

During this phase, controllers act on CRs created by the CLI phase. Resources such as Gitea repositories and ArgoCD applications are created.

#### LocalbuildReconciler

`LocalbuildReconciler` bootstraps the cluster using embedded manifests. Embedded manifests are yaml files that are baked into the binary at compile time.
1. Install core packages. They are essential services that are needed for the user experiences we want to enable:
* Gitea. This is the in-cluster Git server that hosts Git repositories.
* Ingress-nginx. This is necessary to expose services inside the cluster to the users.
* ArgoCD. This is used as the packaging mechanism. Its primary purpose is to deploy manifests from gitea repositories.
2. Once they are installed, it creates `GitRepository` CRs for core packages. This CR represents the git repository on the Gitea server.
3. Create ArgoCD applications for the apps. Point them to the Gitea repositories. From here on, ArgoCD manages the core packages.

Once core packages are installed, it creates the other embedded applications: Backstage and Crossplane.
1. Create `GitRepository` CRs for the apps.
2. Create ArgoCD applications for the apps. Point them to the Gitea repositories.


#### RepositoryReconciler

`RepositoryReconciler` creates Gitea repositories.
The content of the repositories can either be sourced from Embedded file system or local file system.

#### CustomPackageReconciler

`CustomPackageReconciler` parses the specified ArgoCD application files. If they specify repository URL with the scheme `cnoe://`,
it creates `GitRepository` CR with source specified as local, then creates ArgoCD application with the repository URL replaced.

For example, if an ArgoCD application is specified as the following.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    repoURL: cnoe://busybox
```

Then, the actual object created is this.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    repoURL: http://my-gitea-http.gitea.svc.cluster.local:3000/giteaAdmin/idpbuilder-localdev-my-app-busybox.git
```
