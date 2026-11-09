@moduledoc """
kinds: the Kubernetes kinds blue speaks, as records. engenho-kube-codegen writes this file from the OpenAPI v1.34.0 schemas vendored in engenho-types, with the plural and scope from its KIND_CATALOG; edit the generator, never this file.

A record refuses an unknown field and a missing one. A Kubernetes field the schema marks required is a typed field the call must give; every other field is in `unset`, so a call spreads `**unset.<record>` and names only what it sets. A list or map field keeps its type and starts empty; any other optional field starts nil. Field names are snake_case; `wire_names` gives each one's spelling on the wire, and `catalog` the apiVersion, kind, plural and scope of each kind.

    config_map(**unset.config_map, data: {a: "1"}).data #=> {a: "1"}
    catalog.deployment.plural #=> "deployments"
    wire_names.api_group #=> "apiGroup"
"""

@doc """
config_map: the v1 ConfigMap kind. ConfigMap holds configuration data for pods to consume.

    config_map?(config_map(**unset.config_map)) #=> true
"""
record config_map(binary_data: Map, data: Map, immutable, metadata)

@doc """
container_port: the `io.k8s.api.core.v1.ContainerPort` shape. ContainerPort represents a network port in a single container.

    container_port?({}) #=> false
"""
record container_port(container_port: Int, host_ip, host_port, name, protocol)

@doc """
env_var: the `io.k8s.api.core.v1.EnvVar` shape. EnvVar represents an environment variable present in a Container.

    env_var?({}) #=> false
"""
record env_var(name: Str, value, value_from)

@doc """
volume_mount: the `io.k8s.api.core.v1.VolumeMount` shape. VolumeMount describes a mounting of a Volume within a container.

    volume_mount?({}) #=> false
"""
record volume_mount(
  mount_path: Str,
  mount_propagation,
  name: Str,
  read_only,
  recursive_read_only,
  sub_path,
  sub_path_expr
)

@doc """
container: the `io.k8s.api.core.v1.Container` shape. A single application container that you want to run within a pod.

    container?({}) #=> false
"""
record container(
  args: List(Str),
  command: List(Str),
  env: List(env_var),
  env_from: List(Map),
  image,
  image_pull_policy,
  lifecycle,
  liveness_probe,
  name: Str,
  ports: List(container_port),
  readiness_probe,
  resize_policy: List(Map),
  resources,
  restart_policy,
  restart_policy_rules: List(Map),
  security_context,
  startup_probe,
  stdin,
  stdin_once,
  termination_message_path,
  termination_message_policy,
  tty,
  volume_devices: List(Map),
  volume_mounts: List(volume_mount),
  working_dir
)

@doc """
deployment: the apps/v1 Deployment kind. Deployment enables declarative updates for Pods and ReplicaSets.

    deployment?(deployment(**unset.deployment)) #=> true
"""
record deployment(metadata, spec, status)

@doc """
label_selector_requirement: the `io.k8s.apimachinery.pkg.apis.meta.v1.LabelSelectorRequirement` shape. A label selector requirement is a selector that contains values, a key, and an operator that relates the key and values.

    label_selector_requirement?({}) #=> false
"""
record label_selector_requirement(key: Str, operator: Str, values: List(Str))

@doc """
label_selector: the `io.k8s.apimachinery.pkg.apis.meta.v1.LabelSelector` shape. A label selector is a label query over a set of resources. The result of matchLabels and matchExpressions are ANDed. An empty label selector matches all objects. A null label selector matches no objects.

    label_selector?(label_selector(**unset.label_selector)) #=> true
"""
record label_selector(
  match_expressions: List(label_selector_requirement),
  match_labels: Map
)

@doc """
pod_template_spec: the `io.k8s.api.core.v1.PodTemplateSpec` shape. PodTemplateSpec describes the data a pod should have when created from a template

    pod_template_spec?(pod_template_spec(**unset.pod_template_spec)) #=> true
"""
record pod_template_spec(metadata, spec)

@doc """
deployment_spec: the `io.k8s.api.apps.v1.DeploymentSpec` shape. DeploymentSpec is the specification of the desired behavior of the Deployment.

    deployment_spec?({}) #=> false
"""
record deployment_spec(
  min_ready_seconds,
  paused,
  progress_deadline_seconds,
  replicas,
  revision_history_limit,
  selector: label_selector,
  strategy,
  template: pod_template_spec
)

@doc """
deployment_strategy: the `io.k8s.api.apps.v1.DeploymentStrategy` shape. DeploymentStrategy describes how to replace existing pods with new ones.

    deployment_strategy?(deployment_strategy(**unset.deployment_strategy)) #=> true
"""
record deployment_strategy(rolling_update, type)

@doc """
ip_block: the `io.k8s.api.networking.v1.IPBlock` shape. IPBlock describes a particular CIDR (Ex. "192.168.1.0/24","2001:db8::/64") that is allowed to the pods matched by a NetworkPolicySpec's podSelector. The except entry describes CIDRs that should not be included within this rule.

    ip_block?({}) #=> false
"""
record ip_block(cidr: Str, except: List(Str))

@doc """
local_object_reference: the `io.k8s.api.core.v1.LocalObjectReference` shape. LocalObjectReference contains enough information to let you locate the referenced object inside the same namespace.

    local_object_reference?(local_object_reference(**unset.local_object_reference)) #=> true
"""
record local_object_reference(name)

@doc """
network_policy: the networking.k8s.io/v1 NetworkPolicy kind. NetworkPolicy describes what network traffic is allowed for a set of Pods

    network_policy?(network_policy(**unset.network_policy)) #=> true
"""
record network_policy(metadata, spec)

@doc """
network_policy_peer: the `io.k8s.api.networking.v1.NetworkPolicyPeer` shape. NetworkPolicyPeer describes a peer to allow traffic to/from. Only certain combinations of fields are allowed

    network_policy_peer?(network_policy_peer(**unset.network_policy_peer)) #=> true
"""
record network_policy_peer(ip_block, namespace_selector, pod_selector)

@doc """
network_policy_port: the `io.k8s.api.networking.v1.NetworkPolicyPort` shape. NetworkPolicyPort describes a port to allow traffic on

    network_policy_port?(network_policy_port(**unset.network_policy_port)) #=> true
"""
record network_policy_port(end_port, port, protocol)

@doc """
network_policy_egress_rule: the `io.k8s.api.networking.v1.NetworkPolicyEgressRule` shape. NetworkPolicyEgressRule describes a particular set of traffic that is allowed out of pods matched by a NetworkPolicySpec's podSelector. The traffic must match both ports and to. This type is beta-level in 1.8

    network_policy_egress_rule?(network_policy_egress_rule(**unset.network_policy_egress_rule)) #=> true
"""
record network_policy_egress_rule(
  ports: List(network_policy_port),
  to: List(network_policy_peer)
)

@doc """
network_policy_ingress_rule: the `io.k8s.api.networking.v1.NetworkPolicyIngressRule` shape. NetworkPolicyIngressRule describes a particular set of traffic that is allowed to the pods matched by a NetworkPolicySpec's podSelector. The traffic must match both ports and from.

    network_policy_ingress_rule?(network_policy_ingress_rule(**unset.network_policy_ingress_rule)) #=> true
"""
record network_policy_ingress_rule(
  from: List(network_policy_peer),
  ports: List(network_policy_port)
)

@doc """
network_policy_spec: the `io.k8s.api.networking.v1.NetworkPolicySpec` shape. NetworkPolicySpec provides the specification of a NetworkPolicy

    network_policy_spec?(network_policy_spec(**unset.network_policy_spec)) #=> true
"""
record network_policy_spec(
  egress: List(network_policy_egress_rule),
  ingress: List(network_policy_ingress_rule),
  pod_selector,
  policy_types: List(Str)
)

@doc """
owner_reference: the `io.k8s.apimachinery.pkg.apis.meta.v1.OwnerReference` shape. OwnerReference contains enough information to let you identify an owning object. An owning object must be in the same namespace as the dependent, or be cluster-scoped, so there is no namespace field.

    owner_reference?({}) #=> false
"""
record owner_reference(
  api_version: Str,
  block_owner_deletion,
  controller,
  kind: Str,
  name: Str,
  uid: Str
)

@doc """
object_meta: the `io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta` shape. ObjectMeta is metadata that all persisted resources must have, which includes all objects users must create.

    object_meta?(object_meta(**unset.object_meta)) #=> true
"""
record object_meta(
  annotations: Map,
  creation_timestamp,
  deletion_grace_period_seconds,
  deletion_timestamp,
  finalizers: List(Str),
  generate_name,
  generation,
  labels: Map,
  managed_fields: List(Map),
  name,
  namespace,
  owner_references: List(owner_reference),
  resource_version,
  self_link,
  uid
)

@doc """
object_reference: the `io.k8s.api.core.v1.ObjectReference` shape. ObjectReference contains enough information to let you inspect or modify the referred object.

    object_reference?(object_reference(**unset.object_reference)) #=> true
"""
record object_reference(
  api_version,
  field_path,
  kind,
  name,
  namespace,
  resource_version,
  uid
)

@doc """
pod_spec: the `io.k8s.api.core.v1.PodSpec` shape. PodSpec is a description of a pod.

    pod_spec?({}) #=> false
"""
record pod_spec(
  active_deadline_seconds,
  affinity,
  automount_service_account_token,
  containers: List(container),
  dns_config,
  dns_policy,
  enable_service_links,
  ephemeral_containers: List(Map),
  host_aliases: List(Map),
  host_ipc,
  host_network,
  host_pid,
  host_users,
  hostname,
  hostname_override,
  image_pull_secrets: List(local_object_reference),
  init_containers: List(container),
  node_name,
  node_selector: Map,
  os,
  overhead: Map,
  preemption_policy,
  priority,
  priority_class_name,
  readiness_gates: List(Map),
  resource_claims: List(Map),
  resources,
  restart_policy,
  runtime_class_name,
  scheduler_name,
  scheduling_gates: List(Map),
  security_context,
  service_account,
  service_account_name,
  set_hostname_as_fqdn,
  share_process_namespace,
  subdomain,
  termination_grace_period_seconds,
  tolerations: List(Map),
  topology_spread_constraints: List(Map),
  volumes: List(Map)
)

@doc """
policy_rule: the `io.k8s.api.rbac.v1.PolicyRule` shape. PolicyRule holds information that describes a policy rule, but does not contain information about who the rule applies to or which namespace the rule applies to.

    policy_rule?({}) #=> false
"""
record policy_rule(
  api_groups: List(Str),
  non_resource_urls: List(Str),
  resource_names: List(Str),
  resources: List(Str),
  verbs: List(Str)
)

@doc """
resource_requirements: the `io.k8s.api.core.v1.ResourceRequirements` shape. ResourceRequirements describes the compute resource requirements.

    resource_requirements?(resource_requirements(**unset.resource_requirements)) #=> true
"""
record resource_requirements(claims: List(Map), limits: Map, requests: Map)

@doc """
role: the rbac.authorization.k8s.io/v1 Role kind. Role is a namespaced, logical grouping of PolicyRules that can be referenced as a unit by a RoleBinding.

    role?(role(**unset.role)) #=> true
"""
record role(metadata, rules: List(policy_rule))

@doc """
role_ref: the `io.k8s.api.rbac.v1.RoleRef` shape. RoleRef contains information that points to the role being used

    role_ref?({}) #=> false
"""
record role_ref(api_group: Str, kind: Str, name: Str)

@doc """
subject: the `io.k8s.api.rbac.v1.Subject` shape. Subject contains a reference to the object or user identities a role binding applies to.  This can either hold a direct API object reference, or a value for non-objects such as user and group names.

    subject?({}) #=> false
"""
record subject(api_group, kind: Str, name: Str, namespace)

@doc """
role_binding: the rbac.authorization.k8s.io/v1 RoleBinding kind. RoleBinding references a role, but does not contain it.  It can reference a Role in the same namespace or a ClusterRole in the global namespace. It adds who information via Subjects and namespace information by which namespace it exists in.  RoleBindings in a given namespace only have effect in that namespace.

    role_binding?({}) #=> false
"""
record role_binding(metadata, role_ref: role_ref, subjects: List(subject))

@doc """
rolling_update_deployment: the `io.k8s.api.apps.v1.RollingUpdateDeployment` shape. Spec to control the desired behavior of rolling update.

    rolling_update_deployment?(rolling_update_deployment(**unset.rolling_update_deployment)) #=> true
"""
record rolling_update_deployment(max_surge, max_unavailable)

@doc """
secret: the v1 Secret kind. Secret holds secret data of a certain type. The total bytes of the values in the Data field must be less than MaxSecretSize bytes.

    secret?(secret(**unset.secret)) #=> true
"""
record secret(data: Map, immutable, metadata, string_data: Map, type)

@doc """
service: the v1 Service kind. Service is a named abstraction of software service (for example, mysql) consisting of local port (for example 3306) that the proxy listens on, and the selector that determines which pods will answer requests sent through the proxy.

    service?(service(**unset.service)) #=> true
"""
record service(metadata, spec, status)

@doc """
service_account: the v1 ServiceAccount kind. ServiceAccount binds together: * a name, understood by users, and perhaps by peripheral systems, for an identity * a principal that can be authenticated and authorized * a set of secrets

    service_account?(service_account(**unset.service_account)) #=> true
"""
record service_account(
  automount_service_account_token,
  image_pull_secrets: List(local_object_reference),
  metadata,
  secrets: List(object_reference)
)

@doc """
service_port: the `io.k8s.api.core.v1.ServicePort` shape. ServicePort contains information on service's port.

    service_port?({}) #=> false
"""
record service_port(
  app_protocol,
  name,
  node_port,
  port: Int,
  protocol,
  target_port
)

@doc """
service_spec: the `io.k8s.api.core.v1.ServiceSpec` shape. ServiceSpec describes the attributes that a user creates on a service.

    service_spec?(service_spec(**unset.service_spec)) #=> true
"""
record service_spec(
  allocate_load_balancer_node_ports,
  cluster_ip,
  cluster_ips: List(Str),
  external_ips: List(Str),
  external_name,
  external_traffic_policy,
  health_check_node_port,
  internal_traffic_policy,
  ip_families: List(Str),
  ip_family_policy,
  load_balancer_class,
  load_balancer_ip,
  load_balancer_source_ranges: List(Str),
  ports: List(service_port),
  publish_not_ready_addresses,
  selector: Map,
  session_affinity,
  session_affinity_config,
  traffic_distribution,
  type
)

@doc """
catalog: each kind's apiVersion, kind, plural and scope, keyed by its record.

    catalog.role_binding.api_version #=> "rbac.authorization.k8s.io/v1"
    catalog.config_map.scope #=> :namespaced
"""
def catalog()
  {
    config_map: {
      api_version: "v1",
      kind: "ConfigMap",
      plural: "configmaps",
      scope: :namespaced
    },
    deployment: {
      api_version: "apps/v1",
      kind: "Deployment",
      plural: "deployments",
      scope: :namespaced
    },
    network_policy: {
      api_version: "networking.k8s.io/v1",
      kind: "NetworkPolicy",
      plural: "networkpolicies",
      scope: :namespaced
    },
    role: {
      api_version: "rbac.authorization.k8s.io/v1",
      kind: "Role",
      plural: "roles",
      scope: :namespaced
    },
    role_binding: {
      api_version: "rbac.authorization.k8s.io/v1",
      kind: "RoleBinding",
      plural: "rolebindings",
      scope: :namespaced
    },
    secret: {
      api_version: "v1",
      kind: "Secret",
      plural: "secrets",
      scope: :namespaced
    },
    service: {
      api_version: "v1",
      kind: "Service",
      plural: "services",
      scope: :namespaced
    },
    service_account: {
      api_version: "v1",
      kind: "ServiceAccount",
      plural: "serviceaccounts",
      scope: :namespaced
    }
  }
end

@doc """
unset: each record's optional fields at their empty value, keyed by the record: an empty list, an empty map, or nil.

    unset.container.ports #=> []
    unset.object_meta.name #=> nil
"""
def unset()
  {
    config_map: {binary_data: {}, data: {}, immutable: nil, metadata: nil},
    container_port: {host_ip: nil, host_port: nil, name: nil, protocol: nil},
    env_var: {value: nil, value_from: nil},
    volume_mount: {
      mount_propagation: nil,
      read_only: nil,
      recursive_read_only: nil,
      sub_path: nil,
      sub_path_expr: nil
    },
    container: {
      args: [],
      command: [],
      env: [],
      env_from: [],
      image: nil,
      image_pull_policy: nil,
      lifecycle: nil,
      liveness_probe: nil,
      ports: [],
      readiness_probe: nil,
      resize_policy: [],
      resources: nil,
      restart_policy: nil,
      restart_policy_rules: [],
      security_context: nil,
      startup_probe: nil,
      stdin: nil,
      stdin_once: nil,
      termination_message_path: nil,
      termination_message_policy: nil,
      tty: nil,
      volume_devices: [],
      volume_mounts: [],
      working_dir: nil
    },
    deployment: {metadata: nil, spec: nil, status: nil},
    label_selector_requirement: {values: []},
    label_selector: {match_expressions: [], match_labels: {}},
    pod_template_spec: {metadata: nil, spec: nil},
    deployment_spec: {
      min_ready_seconds: nil,
      paused: nil,
      progress_deadline_seconds: nil,
      replicas: nil,
      revision_history_limit: nil,
      strategy: nil
    },
    deployment_strategy: {rolling_update: nil, type: nil},
    ip_block: {except: []},
    local_object_reference: {name: nil},
    network_policy: {metadata: nil, spec: nil},
    network_policy_peer: {
      ip_block: nil,
      namespace_selector: nil,
      pod_selector: nil
    },
    network_policy_port: {end_port: nil, port: nil, protocol: nil},
    network_policy_egress_rule: {ports: [], to: []},
    network_policy_ingress_rule: {from: [], ports: []},
    network_policy_spec: {
      egress: [],
      ingress: [],
      pod_selector: nil,
      policy_types: []
    },
    owner_reference: {block_owner_deletion: nil, controller: nil},
    object_meta: {
      annotations: {},
      creation_timestamp: nil,
      deletion_grace_period_seconds: nil,
      deletion_timestamp: nil,
      finalizers: [],
      generate_name: nil,
      generation: nil,
      labels: {},
      managed_fields: [],
      name: nil,
      namespace: nil,
      owner_references: [],
      resource_version: nil,
      self_link: nil,
      uid: nil
    },
    object_reference: {
      api_version: nil,
      field_path: nil,
      kind: nil,
      name: nil,
      namespace: nil,
      resource_version: nil,
      uid: nil
    },
    pod_spec: {
      active_deadline_seconds: nil,
      affinity: nil,
      automount_service_account_token: nil,
      dns_config: nil,
      dns_policy: nil,
      enable_service_links: nil,
      ephemeral_containers: [],
      host_aliases: [],
      host_ipc: nil,
      host_network: nil,
      host_pid: nil,
      host_users: nil,
      hostname: nil,
      hostname_override: nil,
      image_pull_secrets: [],
      init_containers: [],
      node_name: nil,
      node_selector: {},
      os: nil,
      overhead: {},
      preemption_policy: nil,
      priority: nil,
      priority_class_name: nil,
      readiness_gates: [],
      resource_claims: [],
      resources: nil,
      restart_policy: nil,
      runtime_class_name: nil,
      scheduler_name: nil,
      scheduling_gates: [],
      security_context: nil,
      service_account: nil,
      service_account_name: nil,
      set_hostname_as_fqdn: nil,
      share_process_namespace: nil,
      subdomain: nil,
      termination_grace_period_seconds: nil,
      tolerations: [],
      topology_spread_constraints: [],
      volumes: []
    },
    policy_rule: {
      api_groups: [],
      non_resource_urls: [],
      resource_names: [],
      resources: []
    },
    resource_requirements: {claims: [], limits: {}, requests: {}},
    role: {metadata: nil, rules: []},
    role_ref: {},
    subject: {api_group: nil, namespace: nil},
    role_binding: {metadata: nil, subjects: []},
    rolling_update_deployment: {max_surge: nil, max_unavailable: nil},
    secret: {
      data: {},
      immutable: nil,
      metadata: nil,
      string_data: {},
      type: nil
    },
    service: {metadata: nil, spec: nil, status: nil},
    service_account: {
      automount_service_account_token: nil,
      image_pull_secrets: [],
      metadata: nil,
      secrets: []
    },
    service_port: {
      app_protocol: nil,
      name: nil,
      node_port: nil,
      protocol: nil,
      target_port: nil
    },
    service_spec: {
      allocate_load_balancer_node_ports: nil,
      cluster_ip: nil,
      cluster_ips: [],
      external_ips: [],
      external_name: nil,
      external_traffic_policy: nil,
      health_check_node_port: nil,
      internal_traffic_policy: nil,
      ip_families: [],
      ip_family_policy: nil,
      load_balancer_class: nil,
      load_balancer_ip: nil,
      load_balancer_source_ranges: [],
      ports: [],
      publish_not_ready_addresses: nil,
      selector: {},
      session_affinity: nil,
      session_affinity_config: nil,
      traffic_distribution: nil,
      type: nil
    }
  }
end

@doc """
wire_names: the Kubernetes spelling of every field whose blue name differs from it.

    wire_names.container_port #=> "containerPort"
    wire_names.match_labels #=> "matchLabels"
"""
def wire_names()
  {
    active_deadline_seconds: "activeDeadlineSeconds",
    allocate_load_balancer_node_ports: "allocateLoadBalancerNodePorts",
    api_group: "apiGroup",
    api_groups: "apiGroups",
    api_version: "apiVersion",
    app_protocol: "appProtocol",
    automount_service_account_token: "automountServiceAccountToken",
    binary_data: "binaryData",
    block_owner_deletion: "blockOwnerDeletion",
    cluster_ip: "clusterIP",
    cluster_ips: "clusterIPs",
    container_port: "containerPort",
    creation_timestamp: "creationTimestamp",
    deletion_grace_period_seconds: "deletionGracePeriodSeconds",
    deletion_timestamp: "deletionTimestamp",
    dns_config: "dnsConfig",
    dns_policy: "dnsPolicy",
    enable_service_links: "enableServiceLinks",
    end_port: "endPort",
    env_from: "envFrom",
    ephemeral_containers: "ephemeralContainers",
    external_ips: "externalIPs",
    external_name: "externalName",
    external_traffic_policy: "externalTrafficPolicy",
    field_path: "fieldPath",
    generate_name: "generateName",
    health_check_node_port: "healthCheckNodePort",
    host_aliases: "hostAliases",
    host_ip: "hostIP",
    host_ipc: "hostIPC",
    host_network: "hostNetwork",
    host_pid: "hostPID",
    host_port: "hostPort",
    host_users: "hostUsers",
    hostname_override: "hostnameOverride",
    image_pull_policy: "imagePullPolicy",
    image_pull_secrets: "imagePullSecrets",
    init_containers: "initContainers",
    internal_traffic_policy: "internalTrafficPolicy",
    ip_block: "ipBlock",
    ip_families: "ipFamilies",
    ip_family_policy: "ipFamilyPolicy",
    liveness_probe: "livenessProbe",
    load_balancer_class: "loadBalancerClass",
    load_balancer_ip: "loadBalancerIP",
    load_balancer_source_ranges: "loadBalancerSourceRanges",
    managed_fields: "managedFields",
    match_expressions: "matchExpressions",
    match_labels: "matchLabels",
    max_surge: "maxSurge",
    max_unavailable: "maxUnavailable",
    min_ready_seconds: "minReadySeconds",
    mount_path: "mountPath",
    mount_propagation: "mountPropagation",
    namespace_selector: "namespaceSelector",
    node_name: "nodeName",
    node_port: "nodePort",
    node_selector: "nodeSelector",
    non_resource_urls: "nonResourceURLs",
    owner_references: "ownerReferences",
    pod_selector: "podSelector",
    policy_types: "policyTypes",
    preemption_policy: "preemptionPolicy",
    priority_class_name: "priorityClassName",
    progress_deadline_seconds: "progressDeadlineSeconds",
    publish_not_ready_addresses: "publishNotReadyAddresses",
    read_only: "readOnly",
    readiness_gates: "readinessGates",
    readiness_probe: "readinessProbe",
    recursive_read_only: "recursiveReadOnly",
    resize_policy: "resizePolicy",
    resource_claims: "resourceClaims",
    resource_names: "resourceNames",
    resource_version: "resourceVersion",
    restart_policy: "restartPolicy",
    restart_policy_rules: "restartPolicyRules",
    revision_history_limit: "revisionHistoryLimit",
    role_ref: "roleRef",
    rolling_update: "rollingUpdate",
    runtime_class_name: "runtimeClassName",
    scheduler_name: "schedulerName",
    scheduling_gates: "schedulingGates",
    security_context: "securityContext",
    self_link: "selfLink",
    service_account: "serviceAccount",
    service_account_name: "serviceAccountName",
    session_affinity: "sessionAffinity",
    session_affinity_config: "sessionAffinityConfig",
    set_hostname_as_fqdn: "setHostnameAsFQDN",
    share_process_namespace: "shareProcessNamespace",
    startup_probe: "startupProbe",
    stdin_once: "stdinOnce",
    string_data: "stringData",
    sub_path: "subPath",
    sub_path_expr: "subPathExpr",
    target_port: "targetPort",
    termination_grace_period_seconds: "terminationGracePeriodSeconds",
    termination_message_path: "terminationMessagePath",
    termination_message_policy: "terminationMessagePolicy",
    topology_spread_constraints: "topologySpreadConstraints",
    traffic_distribution: "trafficDistribution",
    value_from: "valueFrom",
    volume_devices: "volumeDevices",
    volume_mounts: "volumeMounts",
    working_dir: "workingDir"
  }
end

test "config_map builds from unset"
  assert config_map?(config_map(**unset.config_map))
end

test "container_port builds from unset and its required fields"
  assert container_port?(
    container_port(**unset.container_port, container_port: 1)
  )
end

test "env_var builds from unset and its required fields"
  assert env_var?(env_var(**unset.env_var, name: "x"))
end

test "volume_mount builds from unset and its required fields"
  assert volume_mount?(
    volume_mount(**unset.volume_mount, mount_path: "x", name: "x")
  )
end

test "container builds from unset and its required fields"
  assert container?(container(**unset.container, name: "x"))
end

test "deployment builds from unset"
  assert deployment?(deployment(**unset.deployment))
end

test "label_selector_requirement builds from unset and its required fields"
  assert label_selector_requirement?(
    label_selector_requirement(
      **unset.label_selector_requirement,
      key: "x",
      operator: "x"
    )
  )
end

test "label_selector builds from unset"
  assert label_selector?(label_selector(**unset.label_selector))
end

test "pod_template_spec builds from unset"
  assert pod_template_spec?(pod_template_spec(**unset.pod_template_spec))
end

test "deployment_spec is not an empty map"
  assert not deployment_spec?({})
end

test "deployment_strategy builds from unset"
  assert deployment_strategy?(deployment_strategy(**unset.deployment_strategy))
end

test "ip_block builds from unset and its required fields"
  assert ip_block?(ip_block(**unset.ip_block, cidr: "x"))
end

test "local_object_reference builds from unset"
  assert local_object_reference?(
    local_object_reference(**unset.local_object_reference)
  )
end

test "network_policy builds from unset"
  assert network_policy?(network_policy(**unset.network_policy))
end

test "network_policy_peer builds from unset"
  assert network_policy_peer?(network_policy_peer(**unset.network_policy_peer))
end

test "network_policy_port builds from unset"
  assert network_policy_port?(network_policy_port(**unset.network_policy_port))
end

test "network_policy_egress_rule builds from unset"
  assert network_policy_egress_rule?(
    network_policy_egress_rule(**unset.network_policy_egress_rule)
  )
end

test "network_policy_ingress_rule builds from unset"
  assert network_policy_ingress_rule?(
    network_policy_ingress_rule(**unset.network_policy_ingress_rule)
  )
end

test "network_policy_spec builds from unset"
  assert network_policy_spec?(network_policy_spec(**unset.network_policy_spec))
end

test "owner_reference builds from unset and its required fields"
  assert owner_reference?(
    owner_reference(
      **unset.owner_reference,
      api_version: "x",
      kind: "x",
      name: "x",
      uid: "x"
    )
  )
end

test "object_meta builds from unset"
  assert object_meta?(object_meta(**unset.object_meta))
end

test "object_reference builds from unset"
  assert object_reference?(object_reference(**unset.object_reference))
end

test "pod_spec builds from unset and its required fields"
  assert pod_spec?(pod_spec(**unset.pod_spec, containers: []))
end

test "policy_rule builds from unset and its required fields"
  assert policy_rule?(policy_rule(**unset.policy_rule, verbs: []))
end

test "resource_requirements builds from unset"
  assert resource_requirements?(
    resource_requirements(**unset.resource_requirements)
  )
end

test "role builds from unset"
  assert role?(role(**unset.role))
end

test "role_ref builds from unset and its required fields"
  assert role_ref?(
    role_ref(**unset.role_ref, api_group: "x", kind: "x", name: "x")
  )
end

test "subject builds from unset and its required fields"
  assert subject?(subject(**unset.subject, kind: "x", name: "x"))
end

test "role_binding is not an empty map"
  assert not role_binding?({})
end

test "rolling_update_deployment builds from unset"
  assert rolling_update_deployment?(
    rolling_update_deployment(**unset.rolling_update_deployment)
  )
end

test "secret builds from unset"
  assert secret?(secret(**unset.secret))
end

test "service builds from unset"
  assert service?(service(**unset.service))
end

test "service_account builds from unset"
  assert service_account?(service_account(**unset.service_account))
end

test "service_port builds from unset and its required fields"
  assert service_port?(service_port(**unset.service_port, port: 1))
end

test "service_spec builds from unset"
  assert service_spec?(service_spec(**unset.service_spec))
end
