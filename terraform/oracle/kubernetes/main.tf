variable "keepass_database_password" {
  sensitive = true
}

terraform {
  required_version = "~> 1.6"
  required_providers {
    oci = {     
      source  = "oracle/oci"
      version = "~> 5"
    }
    keepass = {
      source = "iSchluff/keepass"
      version = "~> 0"
    }
  }
}

provider "keepass" {
  database = "../../Cloud Tokens.kdbx"
  password = var.keepass_database_password
}

module "secrets" {
  source = "../secrets"
  keepass_database_password = var.keepass_database_password
}

provider "oci" {}
provider "local" {}

resource "oci_core_vcn" "oci_core_vcn" {
	cidr_block = "10.0.0.0/16"
	compartment_id = module.secrets.oci_compartment_id
	display_name = "oke"
}

resource "oci_core_internet_gateway" "oci_core_internet_gateway" {
	compartment_id = module.secrets.oci_compartment_id
	display_name = "oke-internet-gateway"
	enabled = "true"
	vcn_id = "${oci_core_vcn.oci_core_vcn.id}"
}

resource "oci_core_nat_gateway" "oci_core_nat_gateway" {
	compartment_id = module.secrets.oci_compartment_id
	display_name = "oke-nat-gateway"
	vcn_id = "${oci_core_vcn.oci_core_vcn.id}"
}

resource "oci_core_service_gateway" "oci_core_service_gateway" {
	compartment_id = module.secrets.oci_compartment_id
	display_name = "oke-service-gateway"
	services {
		service_id = "ocid1.service.oc1.iad.aaaaaaaam4zfmy2rjue6fmglumm3czgisxzrnvrwqeodtztg7hwa272mlfna"
	}
	vcn_id = "${oci_core_vcn.oci_core_vcn.id}"
}

resource "oci_core_route_table" "oci_core_route_table" {
	compartment_id = module.secrets.oci_compartment_id
	display_name = "oke-private-route-table"
	route_rules {
		description = "traffic to the internet"
		destination = "0.0.0.0/0"
		destination_type = "CIDR_BLOCK"
		network_entity_id = "${oci_core_nat_gateway.oci_core_nat_gateway.id}"
	}
	route_rules {
		description = "traffic to OCI services"
		destination = "all-iad-services-in-oracle-services-network"
		destination_type = "SERVICE_CIDR_BLOCK"
		network_entity_id = "${oci_core_service_gateway.oci_core_service_gateway.id}"
	}
	vcn_id = "${oci_core_vcn.oci_core_vcn.id}"
}

resource "oci_core_subnet" "service_load_balancer_subnet" {
	cidr_block = "10.0.20.0/24"
	compartment_id = module.secrets.oci_compartment_id
	display_name = "oke-service-load-balancer"
	prohibit_public_ip_on_vnic = "false"
	route_table_id = "${oci_core_default_route_table.oci_core_default_route_table.id}"
	security_list_ids = ["${oci_core_vcn.oci_core_vcn.default_security_list_id}"]
	vcn_id = "${oci_core_vcn.oci_core_vcn.id}"
}

resource "oci_core_subnet" "node_subnet" {
	cidr_block = "10.0.10.0/24"
	compartment_id = module.secrets.oci_compartment_id
	display_name = "oke-node-subnet"
	prohibit_public_ip_on_vnic = "true"
	route_table_id = "${oci_core_route_table.oci_core_route_table.id}"
	security_list_ids = ["${oci_core_security_list.node_sec_list.id}"]
	vcn_id = "${oci_core_vcn.oci_core_vcn.id}"
}

resource "oci_core_subnet" "kubernetes_api_endpoint_subnet" {
	cidr_block = "10.0.1.0/28"
	compartment_id = module.secrets.oci_compartment_id
	display_name = "oke-k8s-api-endpoint"
	prohibit_public_ip_on_vnic = "false"
	route_table_id = "${oci_core_default_route_table.oci_core_default_route_table.id}"
	security_list_ids = ["${oci_core_security_list.kubernetes_api_endpoint_sec_list.id}"]
	vcn_id = "${oci_core_vcn.oci_core_vcn.id}"
}

resource "oci_core_default_route_table" "oci_core_default_route_table" {
	display_name = "oke-public-route-table"
	route_rules {
		description = "traffic to/from internet"
		destination = "0.0.0.0/0"
		destination_type = "CIDR_BLOCK"
		network_entity_id = "${oci_core_internet_gateway.oci_core_internet_gateway.id}"
	}
	manage_default_resource_id = "${oci_core_vcn.oci_core_vcn.default_route_table_id}"
}

resource "oci_core_security_list" "service_load_balancer_sec_list" {
	compartment_id = module.secrets.oci_compartment_id
	display_name = "oke-service-load-balancer-security-list"
	vcn_id = "${oci_core_vcn.oci_core_vcn.id}"
}

resource "oci_core_security_list" "node_sec_list" {
	compartment_id = module.secrets.oci_compartment_id
	display_name = "oke-node-security-list"
	egress_security_rules {
		description = "Allow pods on one worker node to communicate with pods on other worker nodes"
		destination = "10.0.10.0/24"
		destination_type = "CIDR_BLOCK"
		protocol = "all"
		stateless = "false"
	}
	egress_security_rules {
		description = "Access to Kubernetes API Endpoint"
		destination = "10.0.1.0/28"
		destination_type = "CIDR_BLOCK"
		protocol = "6"
		stateless = "false"
	}
	egress_security_rules {
		description = "Kubernetes worker to control plane communication"
		destination = "10.0.1.0/28"
		destination_type = "CIDR_BLOCK"
		protocol = "6"
		stateless = "false"
	}
	egress_security_rules {
		description = "Path discovery"
		destination = "10.0.1.0/28"
		destination_type = "CIDR_BLOCK"
		icmp_options {
			code = "4"
			type = "3"
		}
		protocol = "1"
		stateless = "false"
	}
	egress_security_rules {
		description = "Allow nodes to communicate with OKE to ensure correct start-up and continued functioning"
		destination = "all-iad-services-in-oracle-services-network"
		destination_type = "SERVICE_CIDR_BLOCK"
		protocol = "6"
		stateless = "false"
	}
	egress_security_rules {
		description = "ICMP Access from Kubernetes Control Plane"
		destination = "0.0.0.0/0"
		destination_type = "CIDR_BLOCK"
		icmp_options {
			code = "4"
			type = "3"
		}
		protocol = "1"
		stateless = "false"
	}
	egress_security_rules {
		description = "Worker Nodes access to Internet"
		destination = "0.0.0.0/0"
		destination_type = "CIDR_BLOCK"
		protocol = "all"
		stateless = "false"
	}
	ingress_security_rules {
		description = "Allow pods on one worker node to communicate with pods on other worker nodes"
		protocol = "all"
		source = "10.0.10.0/24"
		stateless = "false"
	}
	ingress_security_rules {
		description = "Path discovery"
		icmp_options {
			code = "4"
			type = "3"
		}
		protocol = "1"
		source = "10.0.1.0/28"
		stateless = "false"
	}
	ingress_security_rules {
		description = "TCP access from Kubernetes Control Plane"
		protocol = "6"
		source = "10.0.1.0/28"
		stateless = "false"
	}
	ingress_security_rules {
		description = "Inbound SSH traffic to worker nodes"
		protocol = "6"
		source = "0.0.0.0/0"
		stateless = "false"
	}
	vcn_id = "${oci_core_vcn.oci_core_vcn.id}"
}

resource "oci_core_security_list" "kubernetes_api_endpoint_sec_list" {
	compartment_id = module.secrets.oci_compartment_id
	display_name = "oke-k8s-api-endpoint-security-list"
	egress_security_rules {
		description = "Allow Kubernetes Control Plane to communicate with OKE"
		destination = "all-iad-services-in-oracle-services-network"
		destination_type = "SERVICE_CIDR_BLOCK"
		protocol = "6"
		stateless = "false"
	}
	egress_security_rules {
		description = "All traffic to worker nodes"
		destination = "10.0.10.0/24"
		destination_type = "CIDR_BLOCK"
		protocol = "6"
		stateless = "false"
	}
	egress_security_rules {
		description = "Path discovery"
		destination = "10.0.10.0/24"
		destination_type = "CIDR_BLOCK"
		icmp_options {
			code = "4"
			type = "3"
		}
		protocol = "1"
		stateless = "false"
	}
	ingress_security_rules {
		description = "External access to Kubernetes API endpoint"
		protocol = "6"
		source = "0.0.0.0/0"
		stateless = "false"
	}
	ingress_security_rules {
		description = "Kubernetes worker to Kubernetes API endpoint communication"
		protocol = "6"
		source = "10.0.10.0/24"
		stateless = "false"
	}
	ingress_security_rules {
		description = "Kubernetes worker to control plane communication"
		protocol = "6"
		source = "10.0.10.0/24"
		stateless = "false"
	}
	ingress_security_rules {
		description = "Path discovery"
		icmp_options {
			code = "4"
			type = "3"
		}
		protocol = "1"
		source = "10.0.10.0/24"
		stateless = "false"
	}
	vcn_id = "${oci_core_vcn.oci_core_vcn.id}"
}

resource "oci_containerengine_cluster" "oci_containerengine_cluster" {
	# cluster_pod_network_options {
	# 	cni_type = "OCI_VCN_IP_NATIVE"
	# }
	compartment_id = module.secrets.oci_compartment_id
	endpoint_config {
		is_public_ip_enabled = "false"
		subnet_id = "${oci_core_subnet.kubernetes_api_endpoint_subnet.id}"
	}
	freeform_tags = {
		"OKEclusterName" = "oke"
	}
	kubernetes_version = "v1.28.2"
	name = "oke"
	options {
		admission_controller_options {
			is_pod_security_policy_enabled = "false"
		}
		persistent_volume_config {
			freeform_tags = {
				"OKEclusterName" = "oke"
			}
		}
		service_lb_config {
			freeform_tags = {
				"OKEclusterName" = "oke"
			}
		}
		service_lb_subnet_ids = ["${oci_core_subnet.service_load_balancer_subnet.id}"]
	}
	type = "BASIC_CLUSTER"
	vcn_id = "${oci_core_vcn.oci_core_vcn.id}"
}

resource "oci_containerengine_node_pool" "create_node_pool_details0" {
	cluster_id = "${oci_containerengine_cluster.oci_containerengine_cluster.id}"
	compartment_id = module.secrets.oci_compartment_id
	freeform_tags = {
		"OKEnodePoolName" = "oke-pool"
	}
	initial_node_labels {
		key = "name"
		value = "oke"
	}
	kubernetes_version = "v1.28.2"
	name = "oke-pool"
	node_config_details {
		freeform_tags = {
			"OKEnodePoolName" = "pool1"
		}
		# node_pool_pod_network_option_details {
		# 	cni_type = "OCI_VCN_IP_NATIVE"
		# }
		placement_configs {
			availability_domain = "onUG:US-ASHBURN-AD-1"
			subnet_id = "${oci_core_subnet.node_subnet.id}"
		}
		placement_configs {
			availability_domain = "onUG:US-ASHBURN-AD-2"
			subnet_id = "${oci_core_subnet.node_subnet.id}"
		}
		placement_configs {
			availability_domain = "onUG:US-ASHBURN-AD-3"
			subnet_id = "${oci_core_subnet.node_subnet.id}"
		}
		size = "3"
	}
	node_eviction_node_pool_settings {
		eviction_grace_duration = "PT60M"
	}
  node_shape = "VM.Standard.A1.Flex"
	node_shape_config {
		memory_in_gbs = "6"
		ocpus = "1"
	}
	node_source_details {
		image_id = "ocid1.image.oc1.iad.aaaaaaaao2zpwcb2osmbtliiuzlphc3y2fqaqmcpp5ttlcf573sidkabml7a"
		source_type = "IMAGE"
	}
  ssh_public_key = module.secrets.ssh_authorized_keys
}

data "oci_containerengine_cluster_kube_config" "cluster_kube_config" {
  cluster_id    = oci_containerengine_cluster.oci_containerengine_cluster.id
  expiration    = 2592000
  token_version = "2.0.0"
}

# https://www.terraform.io/docs/providers/local/r/file.html
resource "local_file" "kubeconfig" {
  content  = data.oci_containerengine_cluster_kube_config.cluster_kube_config.content
  filename = pathexpand("~/.kube/ociconfig")
}

resource "oci_core_vnic_attachment" "bastion_k8s_api_server" {
	create_vnic_details {
    subnet_id = oci_core_subnet.kubernetes_api_endpoint_subnet.id
	}
	instance_id = "ocid1.instance.oc1.iad.anuwcljr6r7p7lycyr2a6yo2cs4xzjpd5ypodeqlbfysqmbbrpoh3t373imq" # arm-1vcpu-6gb-us-qas-000
	display_name = "bastion-api-server" 

  ## TODO: compute
  # download vnic script
  # https://blogs.oracle.com/cloud-infrastructure/post/how-to-add-a-secondary-vnic-to-linux-compute-in-three-steps
  # curl https://docs.oracle.com/en-us/iaas/Content/Resources/Assets/secondary_vnic_all_configure.sh | sudo tee /usr/local/bin/vnic
  ## /etc/systemd/system/vnic.service
  # [Unit]
  # Description=Setting the secondary vnic
  # After=default.target
  # [Service]
  # Type=oneshot
  # RemainAfterExit=yes
  # ExecStart=/usr/local/sbin/vnic -c
  # [Install]
  # WantedBy=multi-user.target
  # sudo systemctl enable vnic.service

  ## TODO: bastion-dependencies
  # install_kubectl
  # install_oci

  ## TODO: proxy-script
  # API_SERVER=10.0.1.2
  # COMPARTMENT_ID=$(oci iam compartment list  | jq '.data[] | select(.name | contains("cloud")) .id')
  # CLUSTER_ID=$(oci ce cluster list --compartment-id $COMPARTMENT_ID | jq '.data[] | select(."lifecycle-state" | contains("ACTIVE")) | .id')
  # ssh -fNt -L6443:$API_SERVER:6443 0.mksybr.com
  # oci ce cluster create-kubeconfig --cluster-id $CLUSTER_ID --file $HOME/.kube/config --region us-ashburn-1 --token-version 2.0.0  --kube-endpoint PRIVATE_ENDPOINT
  # perl -pi -e "s/$API_SERVER/127.0.0.1/g" ~/.kube/config
  
  # TODO: oci-csi driver fails if failure-domain.beta.kubernetes.io/zone not set
  # TODO: nodes initialize but still had to be untainted: kubectl taint nodes --all node.cloudprovider.kubernetes.io/uninitialized:NoSchedule-

}
