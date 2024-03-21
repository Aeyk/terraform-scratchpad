# https://www.terraform.io/docs/providers/oci/r/containerengine_cluster.html
resource "oci_containerengine_cluster" "k8s_cluster" {
  #Required
  compartment_id     = module.secrets.oci_compartment_id
  kubernetes_version = var.oke["version"]
  name               = var.oke["name"]
  vcn_id             = module.oke_vcn.vcn_id
  type               = "BASIC_CLUSTER"
  options {
    add_ons {
      is_kubernetes_dashboard_enabled = true
      is_tiller_enabled               = false
    }
    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
    service_lb_subnet_ids = [oci_core_subnet.public.id]
  }
  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.public.id
  }
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = module.secrets.oci_compartment_id
}

# https://www.terraform.io/docs/providers/oci/r/containerengine_node_pool.html
resource "oci_containerengine_node_pool" "k8s_node_pool" {
  cluster_id         = oci_containerengine_cluster.k8s_cluster.id
  compartment_id     = module.secrets.oci_compartment_id
  kubernetes_version = var.oke["version"]
  name               = var.oke["name"]
  node_shape         = var.oke["shape"]
  node_shape_config {
    memory_in_gbs = "6"
    ocpus         = "1"
  }
  # quantity_per_subnet = var.oke["nodes_per_subnet"]
  node_config_details {
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = module.network.arm_public_subnet
      # subnet_id           = oci_core_subnet.private.id
    }
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[1].name
      subnet_id           = module.network.arm_public_subnet
      # subnet_id           = oci_core_subnet.private.id
    }
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[2].name
      subnet_id           = module.network.arm_public_subnet
      # subnet_id           = oci_core_subnet.private.id
    }
    size = 3
  }
  node_source_details {
    source_type = "IMAGE"
    image_id    = var.image_id
  }
  # subnet_ids = [
  #   "${oci_core_subnet.private.id}",
  #   "${oci_core_subnet.public.id}"
  # ]
  ssh_public_key = module.secrets.ssh_authorized_keys
}

# TODO finish
# resource "oci_bastion_bastion" "demo_bastionsrv" {
#   bastion_type     = "STANDARD"
#   compartment_id   = var.compartment_ocid
#   target_subnet_id           = oci_core_subnet.private.id
#   client_cidr_block_allow_list = [
#     var.local_laptop_id
#   ]
#   defined_tags = var.network_defined_tags
#   name = "oke-bastion"
# }

# resource "oci_bastion_session" "demo_bastionsession" {
#   bastion_id = oci_bastion_bastion.demo_bastionsrv.id
#   defined_tags = var.network_defined_tags
#   key_details {
#     public_key_content = var.ssh_bastion_key
#   }
#   target_resource_details {
#     session_type       = "MANAGED_SSH"
#     target_resource_id = data.terraform_remote_state.compute_state.outputs.private_instance_id
#     target_resource_operating_system_user_name = "opc"
#     target_resource_port                       = "22"
#   }
#   session_ttl_in_seconds = 3600
#   display_name = "bastionsession-private-host"
# }

# output "node_public_ips" {
#   value = oci_containerengine_node_pool.k8s_node_pool.nodes[*].public_ip
# }

# https://www.terraform.io/docs/providers/oci/d/containerengine_cluster_kube_config.html
data "oci_containerengine_cluster_kube_config" "cluster_kube_config" {
  cluster_id    = oci_containerengine_cluster.k8s_cluster.id
  expiration    = 2592000
  token_version = "2.0.0"
}

# https://www.terraform.io/docs/providers/local/r/file.html
resource "local_file" "kubeconfig" {
  content  = data.oci_containerengine_cluster_kube_config.cluster_kube_config.content
  filename = pathexpand("~/.kube/ociconfig")
}

resource "digitalocean_record" "main" {
  count  = var.oke["nodes_per_subnet"]
  name   = "*"
  domain = "mksybr.com"
  type   = "A"
  value  = oci_containerengine_cluster.k8s_cluster.endpoints[index.count]public_endpoint
  ttl    = "30"
}
