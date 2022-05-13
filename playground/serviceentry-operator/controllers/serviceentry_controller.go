/*
Copyright 2022.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controllers

import (
	"context"
	"fmt"

	networkingv1 "github.com/aspenmesh/random/playground/serviceentry-operator/api/v1"
	istioapiv1beta1 "istio.io/api/networking/v1beta1"
	istiov1beta1 "istio.io/client-go/pkg/apis/networking/v1beta1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

var (
	jobOwnerKey = ".metadata.annotations.controller"
	apiGVStr    = networkingv1.GroupVersion.String()
)

// ServiceEntryReconciler reconciles a ServiceEntry object
type ServiceEntryReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

//+kubebuilder:rbac:groups=networking.aspenmesh.io,resources=serviceentries,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=networking.aspenmesh.io,resources=serviceentries/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=networking.aspenmesh.io,resources=serviceentries/finalizers,verbs=update
//+kubebuilder:rbac:groups=networking.istio.io,resources=serviceentries,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=networking.istio.io,resources=serviceentries/status,verbs=get

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the ServiceEntry object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.11.2/pkg/reconcile
func (r *ServiceEntryReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := log.FromContext(ctx)
	log.Info(fmt.Sprintf("%+v\n", req))

	var serviceEntry networkingv1.ServiceEntry
	if err := r.Get(ctx, req.NamespacedName, &serviceEntry); err != nil {
		log.Error(err, "unable to fetch ServiceEntry")
		// we'll ignore not-found errors, since they can't be fixed by an immediate
		// requeue (we'll need to wait for a new notification), and we can get them
		// on deleted requests.
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	var istioSE istiov1beta1.ServiceEntry
	if err := r.Get(ctx, req.NamespacedName, &istioSE); err != nil {
		log.Info("unable to find istio SE, must create...")
		se := istiov1beta1.ServiceEntry{
			ObjectMeta: metav1.ObjectMeta{
				Name:      serviceEntry.Name,
				Namespace: serviceEntry.Namespace,
			},
			Spec: istioapiv1beta1.ServiceEntry{
				Hosts:      serviceEntry.Spec.Hosts,
				Addresses:  serviceEntry.Spec.Addresses,
				Ports:      []*istioapiv1beta1.Port{},
				Resolution: istioapiv1beta1.ServiceEntry_Resolution(2),
			},
		}
		if err := ctrl.SetControllerReference(&serviceEntry, &se, r.Scheme); err != nil {
			log.Error(err, "could not add owner ref")
		}

		log.Info(fmt.Sprintf("%+v\n", &se))

		if err := r.Create(ctx, &se); err != nil {
			log.Error(err, "could not create new se")
			return ctrl.Result{}, err
		}
		return ctrl.Result{}, nil
	} else {
		log.Info("found istio SE, need to update...")
		return ctrl.Result{}, nil
	}

	// var istioSE istiov1beta1.ServiceEntryList
	// if err := r.List(ctx, &istioSE, client.InNamespace(req.Namespace), client.MatchingFields{jobOwnerKey: req.Name}); err != nil {
	// 	log.Error(err, "unable to list child Jobs")
	// 	return ctrl.Result{}, err
	// }

	// TODO(user): your logic here

	// return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *ServiceEntryReconciler) SetupWithManager(mgr ctrl.Manager) error {
	if err := mgr.GetFieldIndexer().IndexField(context.Background(), &istiov1beta1.ServiceEntry{}, jobOwnerKey, func(rawObj client.Object) []string {
		// grab the job object, extract the owner...
		job := rawObj.(*istiov1beta1.ServiceEntry)
		owner := metav1.GetControllerOf(job)
		if owner == nil {
			return nil
		}
		// ...make sure it's a ServiceEntry...
		if owner.APIVersion != apiGVStr || owner.Kind != "ServiceEntry" {
			return nil
		}

		// ...and if so, return it
		return []string{owner.Name}
	}); err != nil {
		return err
	}

	return ctrl.NewControllerManagedBy(mgr).
		For(&networkingv1.ServiceEntry{}).
		Owns(&istiov1beta1.ServiceEntry{}).
		Complete(r)
}
