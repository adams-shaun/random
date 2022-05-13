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

package v1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

type Port struct {
	// A valid non-negative integer port number.
	Number uint32 `protobuf:"varint,1,opt,name=number,proto3" json:"number,omitempty"`
	// The protocol exposed on the port.
	// MUST BE one of HTTP|HTTPS|GRPC|HTTP2|MONGO|TCP|TLS.
	// TLS implies the connection will be routed based on the SNI header to
	// the destination without terminating the TLS connection.
	Protocol string `protobuf:"bytes,2,opt,name=protocol,proto3" json:"protocol,omitempty"`
	// Label assigned to the port.
	Name string `protobuf:"bytes,3,opt,name=name,proto3" json:"name,omitempty"`
	// The port number on the endpoint where the traffic will be
	// received. Applicable only when used with ServiceEntries.
	TargetPort uint32 `protobuf:"varint,4,opt,name=target_port,json=targetPort,proto3" json:"target_port,omitempty"`
}

type WorkloadEntry struct {
	// Address associated with the network endpoint without the
	// port.  Domain names can be used if and only if the resolution is set
	// to DNS, and must be fully-qualified without wildcards. Use the form
	// unix:///absolute/path/to/socket for Unix domain socket endpoints.
	Address string `protobuf:"bytes,1,opt,name=address,proto3" json:"address,omitempty"`
	// Set of ports associated with the endpoint. If the port map is
	// specified, it must be a map of servicePortName to this endpoint's
	// port, such that traffic to the service port will be forwarded to
	// the endpoint port that maps to the service's portName. If
	// omitted, and the targetPort is specified as part of the service's
	// port specification, traffic to the service port will be forwarded
	// to one of the endpoints on the specified `targetPort`. If both
	// the targetPort and endpoint's port map are not specified, traffic
	// to a service port will be forwarded to one of the endpoints on
	// the same port.
	//
	// **NOTE 1:** Do not use for `unix://` addresses.
	//
	// **NOTE 2:** endpoint port map takes precedence over targetPort.
	Ports map[string]uint32 `protobuf:"bytes,2,rep,name=ports,proto3" json:"ports,omitempty" protobuf_key:"bytes,1,opt,name=key,proto3" protobuf_val:"varint,2,opt,name=value,proto3"`
	// One or more labels associated with the endpoint.
	Labels map[string]string `protobuf:"bytes,3,rep,name=labels,proto3" json:"labels,omitempty" protobuf_key:"bytes,1,opt,name=key,proto3" protobuf_val:"bytes,2,opt,name=value,proto3"`
	// Network enables Istio to group endpoints resident in the same L3
	// domain/network. All endpoints in the same network are assumed to be
	// directly reachable from one another. When endpoints in different
	// networks cannot reach each other directly, an Istio Gateway can be
	// used to establish connectivity (usually using the
	// `AUTO_PASSTHROUGH` mode in a Gateway Server). This is
	// an advanced configuration used typically for spanning an Istio mesh
	// over multiple clusters.
	Network string `protobuf:"bytes,4,opt,name=network,proto3" json:"network,omitempty"`
	// The locality associated with the endpoint. A locality corresponds
	// to a failure domain (e.g., country/region/zone). Arbitrary failure
	// domain hierarchies can be represented by separating each
	// encapsulating failure domain by /. For example, the locality of an
	// an endpoint in US, in US-East-1 region, within availability zone
	// az-1, in data center rack r11 can be represented as
	// us/us-east-1/az-1/r11. Istio will configure the sidecar to route to
	// endpoints within the same locality as the sidecar. If none of the
	// endpoints in the locality are available, endpoints parent locality
	// (but within the same network ID) will be chosen. For example, if
	// there are two endpoints in same network (networkID "n1"), say e1
	// with locality us/us-east-1/az-1/r11 and e2 with locality
	// us/us-east-1/az-2/r12, a sidecar from us/us-east-1/az-1/r11 locality
	// will prefer e1 from the same locality over e2 from a different
	// locality. Endpoint e2 could be the IP associated with a gateway
	// (that bridges networks n1 and n2), or the IP associated with a
	// standard service endpoint.
	Locality string `protobuf:"bytes,5,opt,name=locality,proto3" json:"locality,omitempty"`
	// The load balancing weight associated with the endpoint. Endpoints
	// with higher weights will receive proportionally higher traffic.
	Weight uint32 `protobuf:"varint,6,opt,name=weight,proto3" json:"weight,omitempty"`
	// The service account associated with the workload if a sidecar
	// is present in the workload. The service account must be present
	// in the same namespace as the configuration ( WorkloadEntry or a
	// ServiceEntry)
	ServiceAccount string `protobuf:"bytes,7,opt,name=service_account,json=serviceAccount,proto3" json:"service_account,omitempty"`
}

type WorkloadSelector struct {
	// One or more labels that indicate a specific set of pods/VMs
	// on which the configuration should be applied. The scope of
	// label search is restricted to the configuration namespace in which the
	// the resource is present.
	Labels map[string]string `protobuf:"bytes,1,rep,name=labels,proto3" json:"labels,omitempty" protobuf_key:"bytes,1,opt,name=key,proto3" protobuf_val:"bytes,2,opt,name=value,proto3"`
}

// ServiceEntrySpec defines the desired state of ServiceEntry
type ServiceEntrySpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	Hosts []string `protobuf:"bytes,1,rep,name=hosts,proto3" json:"hosts,omitempty"`
	// The virtual IP addresses associated with the service. Could be CIDR
	// prefix. For HTTP traffic, generated route configurations will include http route
	// domains for both the `addresses` and `hosts` field values and the destination will
	// be identified based on the HTTP Host/Authority header.
	// If one or more IP addresses are specified,
	// the incoming traffic will be identified as belonging to this service
	// if the destination IP matches the IP/CIDRs specified in the addresses
	// field. If the Addresses field is empty, traffic will be identified
	// solely based on the destination port. In such scenarios, the port on
	// which the service is being accessed must not be shared by any other
	// service in the mesh. In other words, the sidecar will behave as a
	// simple TCP proxy, forwarding incoming traffic on a specified port to
	// the specified destination endpoint IP/host. Unix domain socket
	// addresses are not supported in this field.
	Addresses []string `protobuf:"bytes,2,rep,name=addresses,proto3" json:"addresses,omitempty"`
	// The ports associated with the external service. If the
	// Endpoints are Unix domain socket addresses, there must be exactly one
	// port.
	Ports []*Port `protobuf:"bytes,3,rep,name=ports,proto3" json:"ports,omitempty"`
	// Specify whether the service should be considered external to the mesh
	// or part of the mesh.
	Location int32 `protobuf:"varint,4,opt,name=location,proto3" json:"location,omitempty"`
	// Service discovery mode for the hosts. Care must be taken
	// when setting the resolution mode to NONE for a TCP port without
	// accompanying IP addresses. In such cases, traffic to any IP on
	// said port will be allowed (i.e. `0.0.0.0:<port>`).
	Resolution int32 `protobuf:"varint,5,opt,name=resolution,proto3" json:"resolution,omitempty"`
	// One or more endpoints associated with the service. Only one of
	// `endpoints` or `workloadSelector` can be specified.
	Endpoints []*WorkloadEntry `protobuf:"bytes,6,rep,name=endpoints,proto3" json:"endpoints,omitempty"`
	// Applicable only for MESH_INTERNAL services. Only one of
	// `endpoints` or `workloadSelector` can be specified. Selects one
	// or more Kubernetes pods or VM workloads (specified using
	// `WorkloadEntry`) based on their labels. The `WorkloadEntry` object
	// representing the VMs should be defined in the same namespace as
	// the ServiceEntry.
	WorkloadSelector *WorkloadSelector `protobuf:"bytes,9,opt,name=workload_selector,json=workloadSelector,proto3" json:"workload_selector,omitempty"`
	// A list of namespaces to which this service is exported. Exporting a service
	// allows it to be used by sidecars, gateways and virtual services defined in
	// other namespaces. This feature provides a mechanism for service owners
	// and mesh administrators to control the visibility of services across
	// namespace boundaries.
	//
	// If no namespaces are specified then the service is exported to all
	// namespaces by default.
	//
	// The value "." is reserved and defines an export to the same namespace that
	// the service is declared in. Similarly the value "*" is reserved and
	// defines an export to all namespaces.
	//
	// For a Kubernetes Service, the equivalent effect can be achieved by setting
	// the annotation "networking.istio.io/exportTo" to a comma-separated list
	// of namespace names.
	ExportTo []string `protobuf:"bytes,7,rep,name=export_to,json=exportTo,proto3" json:"export_to,omitempty"`
	// If specified, the proxy will verify that the server certificate's
	// subject alternate name matches one of the specified values.
	//
	// NOTE: When using the workloadEntry with workloadSelectors, the
	// service account specified in the workloadEntry will also be used
	// to derive the additional subject alternate names that should be
	// verified.
	SubjectAltNames []string `protobuf:"bytes,8,rep,name=subject_alt_names,json=subjectAltNames,proto3" json:"subject_alt_names,omitempty"`
}

// ServiceEntryStatus defines the observed state of ServiceEntry
type ServiceEntryStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status

// ServiceEntry is the Schema for the serviceentries API
type ServiceEntry struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ServiceEntrySpec   `json:"spec,omitempty"`
	Status ServiceEntryStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// ServiceEntryList contains a list of ServiceEntry
type ServiceEntryList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ServiceEntry `json:"items"`
}

func init() {
	SchemeBuilder.Register(&ServiceEntry{}, &ServiceEntryList{})
}
