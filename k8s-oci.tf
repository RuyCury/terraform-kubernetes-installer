locals {
  master_lb_ip = var.master_oci_lb_enabled == "true" ? element(
    concat(flatten(module.k8smaster-public-lb.ip_addresses), [""]),
    0,
  ) : "127.0.0.1"
  master_lb_address = format(
    "https://%s:%s",
    local.master_lb_ip,
    var.master_oci_lb_enabled == "true" ? "443" : "6443",
  )

  reverse_proxy_clount_init = var.master_oci_lb_enabled == "true" ? "" : module.reverse-proxy.clount_init
  reverse_proxy_setup       = var.master_oci_lb_enabled == "true" ? "" : module.reverse-proxy.setup

  etcd_endpoints = var.etcd_lb_enabled == "true" ? join(
    ",",
    formatlist("http://%s:2379", flatten(module.etcd-lb.ip_addresses)),
    ) : join(
    ",",
    formatlist(
      "http://%s:2379",
      compact(
        concat(
          module.instances-etcd-ad1.private_ips,
          module.instances-etcd-ad2.private_ips,
          module.instances-etcd-ad3.private_ips,
        ),
      ),
    ),
  )
}

### CA and Cluster Certificates

module "k8s-tls" {
  source                 = "./tls/"
  api_server_private_key = var.api_server_private_key
  api_server_cert        = var.api_server_cert
  ca_cert                = var.ca_cert
  ca_key                 = var.ca_key
  api_server_admin_token = var.api_server_admin_token
  master_lb_public_ip    = local.master_lb_ip
  ssh_private_key        = var.ssh_private_key
  ssh_public_key_openssh = var.ssh_public_key_openssh
}

### Virtual Cloud Network

module "vcn" {
  source                                  = "./network/vcn"
  compartment_ocid                        = var.compartment_ocid
  label_prefix                            = var.label_prefix
  tenancy_ocid                            = var.tenancy_ocid
  vcn_dns_name                            = var.vcn_dns_name
  additional_etcd_security_lists_ids      = var.additional_etcd_security_lists_ids
  additional_k8smaster_security_lists_ids = var.additional_k8s_master_security_lists_ids
  additional_k8sworker_security_lists_ids = var.additional_k8s_worker_security_lists_ids
  additional_public_security_lists_ids    = var.additional_public_security_lists_ids
  control_plane_subnet_access             = var.control_plane_subnet_access
  etcd_ssh_ingress                        = var.etcd_ssh_ingress
  etcd_cluster_ingress                    = var.etcd_cluster_ingress
  master_ssh_ingress                      = var.master_ssh_ingress
  master_https_ingress                    = var.master_https_ingress
  network_cidrs                           = var.network_cidrs
  public_subnet_ssh_ingress               = var.public_subnet_ssh_ingress
  public_subnet_http_ingress              = var.public_subnet_http_ingress
  public_subnet_https_ingress             = var.public_subnet_https_ingress
  nat_instance_oracle_linux_image_name    = var.nat_ol_image_name
  nat_instance_shape                      = var.natInstanceShape
  nat_instance_ad1_enabled                = var.nat_instance_ad1_enabled
  nat_instance_ad2_enabled                = var.nat_instance_ad2_enabled
  nat_instance_ad3_enabled                = var.nat_instance_ad3_enabled
  nat_instance_ssh_public_key_openssh     = module.k8s-tls.ssh_public_key_openssh
  dedicated_nat_subnets                   = var.dedicated_nat_subnets
  worker_ssh_ingress                      = var.worker_ssh_ingress
  worker_nodeport_ingress                 = var.worker_nodeport_ingress
  master_nodeport_ingress                 = var.master_nodeport_ingress
  external_icmp_ingress                   = var.external_icmp_ingress
  internal_icmp_ingress                   = var.internal_icmp_ingress
  network_subnet_dns                      = var.network_subnet_dns
}

module "oci-cloud-controller" {
  source                                 = "./kubernetes/oci-cloud-controller"
  label_prefix                           = var.label_prefix
  compartment_ocid                       = var.compartment_ocid
  tenancy                                = var.tenancy_ocid
  region                                 = var.region
  cloud_controller_user_ocid             = var.cloud_controller_user_ocid == "" ? var.user_ocid : var.cloud_controller_user_ocid
  cloud_controller_user_fingerprint      = var.cloud_controller_user_fingerprint == "" ? var.fingerprint : var.cloud_controller_user_fingerprint
  cloud_controller_user_private_key_path = var.cloud_controller_user_private_key_path == "" ? var.private_key_path : var.cloud_controller_user_private_key_path

  // So we are using the private_key_path to see if it is set as we don't want to fall back to the var.private_key_password if the
  // var.cloud_controller_user_private_key_path has been provided but has an empty password
  cloud_controller_user_private_key_password = var.cloud_controller_user_private_key_path == "" ? var.private_key_password : var.cloud_controller_user_private_key_password

  subnet1 = element(module.vcn.ccmlb_subnet_ad1_id, 0)
  subnet2 = element(module.vcn.ccmlb_subnet_ad2_id, 0)
}

module "oci-flexvolume-driver" {
  source  = "./kubernetes/oci-flexvolume-driver"
  tenancy = var.tenancy_ocid
  vcn     = module.vcn.id

  flexvolume_driver_user_ocid             = var.flexvolume_driver_user_ocid == "" ? var.user_ocid : var.flexvolume_driver_user_ocid
  flexvolume_driver_user_fingerprint      = var.flexvolume_driver_user_fingerprint == "" ? var.fingerprint : var.flexvolume_driver_user_fingerprint
  flexvolume_driver_user_private_key_path = var.flexvolume_driver_user_private_key_path == "" ? var.private_key_path : var.flexvolume_driver_user_private_key_path

  // See comment for oci-cloud-controller
  flexvolume_driver_user_private_key_password = var.flexvolume_driver_user_private_key_path == "" ? var.private_key_password : var.flexvolume_driver_user_private_key_password
}

module "oci-volume-provisioner" {
  source  = "./kubernetes/oci-volume-provisioner"
  tenancy = var.tenancy_ocid
  region  = var.region

  compartment                              = var.compartment_ocid
  volume_provisioner_user_ocid             = var.volume_provisioner_user_ocid == "" ? var.user_ocid : var.volume_provisioner_user_ocid
  volume_provisioner_user_fingerprint      = var.volume_provisioner_user_fingerprint == "" ? var.fingerprint : var.volume_provisioner_user_fingerprint
  volume_provisioner_user_private_key_path = var.volume_provisioner_user_private_key_path == "" ? var.private_key_path : var.volume_provisioner_user_private_key_path

  // See comment for oci-cloud-controller
  volume_provisioner_user_private_key_password = var.volume_provisioner_user_private_key_path == "" ? var.private_key_password : var.volume_provisioner_user_private_key_password
}

### Compute Instance(s)

module "instances-etcd-ad1" {
  source                      = "./instances/etcd"
  instances_count             = var.etcdAd1Count
  availability_domain         = data.oci_identity_availability_domains.ADs.availability_domains[0]["name"]
  compartment_ocid            = var.compartment_ocid
  control_plane_subnet_access = var.control_plane_subnet_access
  display_name_prefix         = "etcd-ad1"
  domain_name                 = var.domain_name
  etcd_discovery_url          = null_resource.etcd_discovery_url.id
  etcd_ver                    = var.etcd_ver
  hostname_label_prefix       = "etcd-ad1"
  oracle_linux_image_name     = var.etcd_ol_image_name
  label_prefix                = var.label_prefix
  shape                       = var.etcdShape
  ssh_public_key_openssh      = module.k8s-tls.ssh_public_key_openssh
  network_cidrs               = var.network_cidrs
  subnet_id                   = module.vcn.etcd_subnet_ad1_id
  subnet_name                 = "etcdSubnetAD1"
  tenancy_ocid                = var.compartment_ocid
  etcd_docker_max_log_size    = var.etcd_docker_max_log_size
  etcd_docker_max_log_files   = var.etcd_docker_max_log_files
  etcd_iscsi_volume_create    = var.etcd_iscsi_volume_create
  etcd_iscsi_volume_size      = var.etcd_iscsi_volume_size
  assign_private_ip           = var.etcd_maintain_private_ip == "true" ? "true" : "false"
}

module "instances-etcd-ad2" {
  source                      = "./instances/etcd"
  instances_count             = var.etcdAd2Count
  availability_domain         = data.oci_identity_availability_domains.ADs.availability_domains[1]["name"]
  compartment_ocid            = var.compartment_ocid
  control_plane_subnet_access = var.control_plane_subnet_access
  display_name_prefix         = "etcd-ad2"
  domain_name                 = var.domain_name
  etcd_discovery_url          = null_resource.etcd_discovery_url.id
  etcd_ver                    = var.etcd_ver
  hostname_label_prefix       = "etcd-ad2"
  oracle_linux_image_name     = var.etcd_ol_image_name
  label_prefix                = var.label_prefix
  shape                       = var.etcdShape
  ssh_public_key_openssh      = module.k8s-tls.ssh_public_key_openssh
  network_cidrs               = var.network_cidrs
  subnet_id                   = module.vcn.etcd_subnet_ad2_id
  subnet_name                 = "etcdSubnetAD2"
  tenancy_ocid                = var.compartment_ocid
  etcd_docker_max_log_size    = var.etcd_docker_max_log_size
  etcd_docker_max_log_files   = var.etcd_docker_max_log_files
  etcd_iscsi_volume_create    = var.etcd_iscsi_volume_create
  etcd_iscsi_volume_size      = var.etcd_iscsi_volume_size
  assign_private_ip           = var.etcd_maintain_private_ip == "true" ? "true" : "false"
}

module "instances-etcd-ad3" {
  source                      = "./instances/etcd"
  instances_count             = var.etcdAd3Count
  availability_domain         = data.oci_identity_availability_domains.ADs.availability_domains[2]["name"]
  compartment_ocid            = var.compartment_ocid
  control_plane_subnet_access = var.control_plane_subnet_access
  display_name_prefix         = "etcd-ad3"
  docker_ver                  = var.docker_ver
  domain_name                 = var.domain_name
  etcd_discovery_url          = null_resource.etcd_discovery_url.id
  etcd_ver                    = var.etcd_ver
  hostname_label_prefix       = "etcd-ad3"
  oracle_linux_image_name     = var.etcd_ol_image_name
  label_prefix                = var.label_prefix
  shape                       = var.etcdShape
  ssh_public_key_openssh      = module.k8s-tls.ssh_public_key_openssh
  network_cidrs               = var.network_cidrs
  subnet_id                   = module.vcn.etcd_subnet_ad3_id
  subnet_name                 = "etcdSubnetAD3"
  tenancy_ocid                = var.compartment_ocid
  etcd_docker_max_log_size    = var.etcd_docker_max_log_size
  etcd_docker_max_log_files   = var.etcd_docker_max_log_files
  etcd_iscsi_volume_create    = var.etcd_iscsi_volume_create
  etcd_iscsi_volume_size      = var.etcd_iscsi_volume_size
  assign_private_ip           = var.etcd_maintain_private_ip == "true" ? "true" : "false"
}

module "instances-k8smaster-ad1" {
  source                      = "./instances/k8smaster"
  instances_count             = var.k8sMasterAd1Count
  api_server_cert_pem         = module.k8s-tls.api_server_cert_pem
  api_server_count            = var.k8sMasterAd1Count + var.k8sMasterAd2Count + var.k8sMasterAd3Count
  api_server_private_key_pem  = module.k8s-tls.api_server_private_key_pem
  availability_domain         = data.oci_identity_availability_domains.ADs.availability_domains[0]["name"]
  k8s_apiserver_token_admin   = module.k8s-tls.api_server_admin_token
  compartment_ocid            = var.compartment_ocid
  control_plane_subnet_access = var.control_plane_subnet_access
  display_name_prefix         = "k8s-master-ad1"
  docker_ver                  = var.docker_ver
  master_docker_max_log_size  = var.master_docker_max_log_size
  master_docker_max_log_files = var.master_docker_max_log_files
  domain_name                 = var.domain_name
  etcd_discovery_url          = null_resource.etcd_discovery_url.id
  etcd_ver                    = var.etcd_ver
  flannel_ver                 = var.flannel_ver
  hostname_label_prefix       = "k8s-master-ad1"
  oracle_linux_image_name     = var.master_ol_image_name
  k8s_dashboard_ver           = var.k8s_dashboard_ver
  k8s_dns_ver                 = var.k8s_dns_ver
  k8s_ver                     = var.k8s_ver
  label_prefix                = var.label_prefix
  root_ca_pem                 = module.k8s-tls.root_ca_pem
  root_ca_key                 = module.k8s-tls.root_ca_key
  shape                       = var.k8sMasterShape
  ssh_private_key             = module.k8s-tls.ssh_private_key
  ssh_public_key_openssh      = module.k8s-tls.ssh_public_key_openssh
  network_cidrs               = var.network_cidrs
  subnet_id                   = module.vcn.k8smaster_subnet_ad1_id
  subnet_name                 = "masterSubnetAD1"
  tenancy_ocid                = var.compartment_ocid
  cloud_controller_version    = var.cloud_controller_version
  cloud_controller_secret     = module.oci-cloud-controller.cloud-provider-json
  flexvolume_driver_version   = var.flexvolume_driver_version
  flexvolume_driver_secret    = module.oci-flexvolume-driver.flex-volume-driver-yaml
  volume_provisioner_version  = var.volume_provisioner_version
  volume_provisioner_secret   = module.oci-volume-provisioner.volume-provisioner-yaml
  assign_private_ip           = var.master_maintain_private_ip
  etcd_endpoints              = local.etcd_endpoints
  flannel_backend             = var.flannel_backend
  flannel_network_cidr        = var.flannel_network_cidr
  kubernetes_network_plugin   = var.kubernetes_network_plugin
}

module "instances-k8smaster-ad2" {
  source                      = "./instances/k8smaster"
  instances_count             = var.k8sMasterAd2Count
  api_server_cert_pem         = module.k8s-tls.api_server_cert_pem
  api_server_count            = var.k8sMasterAd1Count + var.k8sMasterAd2Count + var.k8sMasterAd3Count
  api_server_private_key_pem  = module.k8s-tls.api_server_private_key_pem
  availability_domain         = data.oci_identity_availability_domains.ADs.availability_domains[1]["name"]
  k8s_apiserver_token_admin   = module.k8s-tls.api_server_admin_token
  compartment_ocid            = var.compartment_ocid
  control_plane_subnet_access = var.control_plane_subnet_access
  display_name_prefix         = "k8s-master-ad2"
  docker_ver                  = var.docker_ver
  master_docker_max_log_size  = var.master_docker_max_log_size
  master_docker_max_log_files = var.master_docker_max_log_files
  domain_name                 = var.domain_name
  etcd_discovery_url          = null_resource.etcd_discovery_url.id
  etcd_ver                    = var.etcd_ver
  flannel_ver                 = var.flannel_ver
  hostname_label_prefix       = "k8s-master-ad2"
  oracle_linux_image_name     = var.master_ol_image_name
  k8s_dashboard_ver           = var.k8s_dashboard_ver
  k8s_dns_ver                 = var.k8s_dns_ver
  k8s_ver                     = var.k8s_ver
  label_prefix                = var.label_prefix
  root_ca_pem                 = module.k8s-tls.root_ca_pem
  root_ca_key                 = module.k8s-tls.root_ca_key
  shape                       = var.k8sMasterShape
  ssh_private_key             = module.k8s-tls.ssh_private_key
  ssh_public_key_openssh      = module.k8s-tls.ssh_public_key_openssh
  network_cidrs               = var.network_cidrs
  subnet_id                   = module.vcn.k8smaster_subnet_ad2_id
  subnet_name                 = "masterSubnetAD2"
  tenancy_ocid                = var.compartment_ocid
  cloud_controller_version    = var.cloud_controller_version
  cloud_controller_secret     = module.oci-cloud-controller.cloud-provider-json
  flexvolume_driver_version   = var.flexvolume_driver_version
  flexvolume_driver_secret    = module.oci-flexvolume-driver.flex-volume-driver-yaml
  volume_provisioner_version  = var.volume_provisioner_version
  volume_provisioner_secret   = module.oci-volume-provisioner.volume-provisioner-yaml
  assign_private_ip           = var.master_maintain_private_ip
  etcd_endpoints              = local.etcd_endpoints
  flannel_backend             = var.flannel_backend
  flannel_network_cidr        = var.flannel_network_cidr
  kubernetes_network_plugin   = var.kubernetes_network_plugin
}

module "instances-k8smaster-ad3" {
  source                      = "./instances/k8smaster"
  instances_count             = var.k8sMasterAd3Count
  api_server_cert_pem         = module.k8s-tls.api_server_cert_pem
  api_server_count            = var.k8sMasterAd1Count + var.k8sMasterAd2Count + var.k8sMasterAd3Count
  api_server_private_key_pem  = module.k8s-tls.api_server_private_key_pem
  availability_domain         = data.oci_identity_availability_domains.ADs.availability_domains[2]["name"]
  k8s_apiserver_token_admin   = module.k8s-tls.api_server_admin_token
  compartment_ocid            = var.compartment_ocid
  control_plane_subnet_access = var.control_plane_subnet_access
  display_name_prefix         = "k8s-master-ad3"
  docker_ver                  = var.docker_ver
  master_docker_max_log_size  = var.master_docker_max_log_size
  master_docker_max_log_files = var.master_docker_max_log_files
  domain_name                 = var.domain_name
  etcd_discovery_url          = null_resource.etcd_discovery_url.id
  etcd_ver                    = var.etcd_ver
  flannel_ver                 = var.flannel_ver
  hostname_label_prefix       = "k8s-master-ad3"
  oracle_linux_image_name     = var.master_ol_image_name
  k8s_dashboard_ver           = var.k8s_dashboard_ver
  k8s_dns_ver                 = var.k8s_dns_ver
  k8s_ver                     = var.k8s_ver
  label_prefix                = var.label_prefix
  root_ca_pem                 = module.k8s-tls.root_ca_pem
  root_ca_key                 = module.k8s-tls.root_ca_key
  shape                       = var.k8sMasterShape
  ssh_private_key             = module.k8s-tls.ssh_private_key
  ssh_public_key_openssh      = module.k8s-tls.ssh_public_key_openssh
  network_cidrs               = var.network_cidrs
  subnet_id                   = module.vcn.k8smaster_subnet_ad3_id
  subnet_name                 = "masterSubnetAD3"
  tenancy_ocid                = var.compartment_ocid
  cloud_controller_version    = var.cloud_controller_version
  cloud_controller_secret     = module.oci-cloud-controller.cloud-provider-json
  flexvolume_driver_version   = var.flexvolume_driver_version
  flexvolume_driver_secret    = module.oci-flexvolume-driver.flex-volume-driver-yaml
  volume_provisioner_version  = var.volume_provisioner_version
  volume_provisioner_secret   = module.oci-volume-provisioner.volume-provisioner-yaml
  assign_private_ip           = var.master_maintain_private_ip
  etcd_endpoints              = local.etcd_endpoints
  flannel_backend             = var.flannel_backend
  flannel_network_cidr        = var.flannel_network_cidr
  kubernetes_network_plugin   = var.kubernetes_network_plugin
}

module "instances-k8sworker-ad1" {
  source                      = "./instances/k8sworker"
  instances_count             = var.k8sWorkerAd1Count
  api_server_cert_pem         = module.k8s-tls.api_server_cert_pem
  api_server_private_key_pem  = module.k8s-tls.api_server_private_key_pem
  availability_domain         = data.oci_identity_availability_domains.ADs.availability_domains[0]["name"]
  compartment_ocid            = var.compartment_ocid
  display_name_prefix         = "k8s-worker-ad1"
  docker_ver                  = var.docker_ver
  worker_docker_max_log_size  = var.worker_docker_max_log_size
  worker_docker_max_log_files = var.worker_docker_max_log_files
  domain_name                 = var.domain_name
  hostname_label_prefix       = "k8s-worker-ad1"
  oracle_linux_image_name     = var.worker_ol_image_name
  k8s_ver                     = var.k8s_ver
  label_prefix                = var.label_prefix
  master_lb                   = local.master_lb_address
  reverse_proxy_clount_init   = local.reverse_proxy_clount_init
  reverse_proxy_setup         = local.reverse_proxy_setup
  region                      = var.region
  root_ca_key                 = module.k8s-tls.root_ca_key
  root_ca_pem                 = module.k8s-tls.root_ca_pem
  shape                       = var.k8sWorkerShape
  ssh_private_key             = module.k8s-tls.ssh_private_key
  ssh_public_key_openssh      = module.k8s-tls.ssh_public_key_openssh
  subnet_id                   = module.vcn.k8worker_subnet_ad1_id
  tenancy_ocid                = var.compartment_ocid
  flexvolume_driver_version   = var.flexvolume_driver_version
  worker_iscsi_volume_create  = var.worker_iscsi_volume_create
  worker_iscsi_volume_size    = var.worker_iscsi_volume_size
  worker_iscsi_volume_mount   = var.worker_iscsi_volume_mount
  flannel_network_cidr        = var.flannel_network_cidr
}

module "instances-k8sworker-ad2" {
  source                      = "./instances/k8sworker"
  instances_count             = var.k8sWorkerAd2Count
  api_server_cert_pem         = module.k8s-tls.api_server_cert_pem
  api_server_private_key_pem  = module.k8s-tls.api_server_private_key_pem
  availability_domain         = data.oci_identity_availability_domains.ADs.availability_domains[1]["name"]
  compartment_ocid            = var.compartment_ocid
  display_name_prefix         = "k8s-worker-ad2"
  docker_ver                  = var.docker_ver
  worker_docker_max_log_size  = var.worker_docker_max_log_size
  worker_docker_max_log_files = var.worker_docker_max_log_files
  domain_name                 = var.domain_name
  hostname_label_prefix       = "k8s-worker-ad2"
  oracle_linux_image_name     = var.worker_ol_image_name
  k8s_ver                     = var.k8s_ver
  label_prefix                = var.label_prefix
  master_lb                   = local.master_lb_address
  reverse_proxy_clount_init   = local.reverse_proxy_clount_init
  reverse_proxy_setup         = local.reverse_proxy_setup
  region                      = var.region
  root_ca_key                 = module.k8s-tls.root_ca_key
  root_ca_pem                 = module.k8s-tls.root_ca_pem
  shape                       = var.k8sWorkerShape
  ssh_private_key             = module.k8s-tls.ssh_private_key
  ssh_public_key_openssh      = module.k8s-tls.ssh_public_key_openssh
  subnet_id                   = module.vcn.k8worker_subnet_ad2_id
  tenancy_ocid                = var.compartment_ocid
  flexvolume_driver_version   = var.flexvolume_driver_version
  worker_iscsi_volume_create  = var.worker_iscsi_volume_create
  worker_iscsi_volume_size    = var.worker_iscsi_volume_size
  worker_iscsi_volume_mount   = var.worker_iscsi_volume_mount
  flannel_network_cidr        = var.flannel_network_cidr
}

module "instances-k8sworker-ad3" {
  source                      = "./instances/k8sworker"
  instances_count             = var.k8sWorkerAd3Count
  api_server_cert_pem         = module.k8s-tls.api_server_cert_pem
  api_server_private_key_pem  = module.k8s-tls.api_server_private_key_pem
  availability_domain         = data.oci_identity_availability_domains.ADs.availability_domains[2]["name"]
  compartment_ocid            = var.compartment_ocid
  display_name_prefix         = "k8s-worker-ad3"
  docker_ver                  = var.docker_ver
  worker_docker_max_log_size  = var.worker_docker_max_log_size
  worker_docker_max_log_files = var.worker_docker_max_log_files
  domain_name                 = var.domain_name
  hostname_label_prefix       = "k8s-worker-ad3"
  oracle_linux_image_name     = var.worker_ol_image_name
  k8s_ver                     = var.k8s_ver
  label_prefix                = var.label_prefix
  master_lb                   = local.master_lb_address
  reverse_proxy_clount_init   = local.reverse_proxy_clount_init
  reverse_proxy_setup         = local.reverse_proxy_setup
  region                      = var.region
  root_ca_key                 = module.k8s-tls.root_ca_key
  root_ca_pem                 = module.k8s-tls.root_ca_pem
  shape                       = var.k8sWorkerShape
  ssh_private_key             = module.k8s-tls.ssh_private_key
  ssh_public_key_openssh      = module.k8s-tls.ssh_public_key_openssh
  subnet_id                   = module.vcn.k8worker_subnet_ad3_id
  tenancy_ocid                = var.compartment_ocid
  flexvolume_driver_version   = var.flexvolume_driver_version
  worker_iscsi_volume_create  = var.worker_iscsi_volume_create
  worker_iscsi_volume_size    = var.worker_iscsi_volume_size
  worker_iscsi_volume_mount   = var.worker_iscsi_volume_mount
  flannel_network_cidr        = var.flannel_network_cidr
}

### Load Balancers

module "etcd-lb" {
  source           = "./network/loadbalancers/etcd"
  etcd_lb_enabled  = var.etcd_lb_enabled
  compartment_ocid = var.compartment_ocid
  is_private       = var.etcd_lb_access == "private" ? "true" : "false"

  # Handle case where var.etcd_lb_access=public, but var.control_plane_subnet_access=private
  etcd_subnet_0_id = var.etcd_lb_access == "private" ? module.vcn.etcd_subnet_ad1_id : coalesce(
    join(" ", module.vcn.public_subnet_ad1_id),
    join(" ", [module.vcn.etcd_subnet_ad1_id]),
  )
  etcd_subnet_1_id = var.etcd_lb_access == "private" ? "" : coalesce(
    join(" ", module.vcn.public_subnet_ad2_id),
    join(" ", [module.vcn.etcd_subnet_ad2_id]),
  )
  etcd_ad1_private_ips = flatten(module.instances-etcd-ad1.private_ips)
  etcd_ad2_private_ips = flatten(module.instances-etcd-ad2.private_ips)
  etcd_ad3_private_ips = flatten(module.instances-etcd-ad3.private_ips)
  etcdAd1Count         = var.etcdAd1Count
  etcdAd2Count         = var.etcdAd2Count
  etcdAd3Count         = var.etcdAd3Count
  label_prefix         = var.label_prefix
  shape                = var.etcdLBShape
}

module "k8smaster-public-lb" {
  source                = "./network/loadbalancers/k8smaster"
  master_oci_lb_enabled = var.master_oci_lb_enabled
  compartment_ocid      = var.compartment_ocid
  is_private            = var.k8s_master_lb_access == "private" ? "true" : "false"

  # Handle case where var.k8s_master_lb_access=public, but var.control_plane_subnet_access=private
  k8smaster_subnet_0_id = var.k8s_master_lb_access == "private" ? module.vcn.k8smaster_subnet_ad1_id : coalesce(
    join(" ", module.vcn.public_subnet_ad1_id),
    join(" ", [module.vcn.k8smaster_subnet_ad1_id]),
  )
  k8smaster_subnet_1_id = var.k8s_master_lb_access == "private" ? "" : coalesce(
    join(" ", module.vcn.public_subnet_ad2_id),
    join(" ", [module.vcn.k8smaster_subnet_ad2_id]),
  )
  k8smaster_ad1_private_ips = flatten(module.instances-k8smaster-ad1.private_ips)
  k8smaster_ad2_private_ips = flatten(module.instances-k8smaster-ad2.private_ips)
  k8smaster_ad3_private_ips = flatten(module.instances-k8smaster-ad3.private_ips)
  k8sMasterAd1Count         = var.k8sMasterAd1Count
  k8sMasterAd2Count         = var.k8sMasterAd2Count
  k8sMasterAd3Count         = var.k8sMasterAd3Count
  label_prefix              = var.label_prefix
  shape                     = var.k8sMasterLBShape
}

module "reverse-proxy" {
  source = "./network/loadbalancers/reverse-proxy"
  hosts = concat(
    flatten(module.instances-k8smaster-ad1.private_ips),
    flatten(module.instances-k8smaster-ad2.private_ips),
    flatten(module.instances-k8smaster-ad3.private_ips),
  )
}

module "kubeconfig" {
  source                     = "./kubernetes/kubeconfig"
  api_server_private_key_pem = module.k8s-tls.api_server_private_key_pem
  api_server_cert_pem        = module.k8s-tls.api_server_cert_pem
  k8s_master = var.master_oci_lb_enabled == "true" ? local.master_lb_address : format(
    "https://%s:%s",
    element(
      coalescelist(
        module.instances-k8smaster-ad1.public_ips,
        module.instances-k8smaster-ad2.public_ips,
        module.instances-k8smaster-ad3.public_ips,
      ),
      0,
    ),
    "443",
  )
}

