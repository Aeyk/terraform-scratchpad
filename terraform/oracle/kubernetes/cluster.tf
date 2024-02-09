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
      subnet_id           = oci_core_subnet.private.id
    }
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[1].name
      subnet_id           = oci_core_subnet.private.id
    }
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[2].name
      subnet_id           = oci_core_subnet.private.id
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

output "node_public_ips" {
  value = oci_containerengine_node_pool.k8s_node_pool.nodes[*].public_ip
}

# https://www.terraform.io/docs/providers/oci/d/containerengine_cluster_kube_config.html
data "oci_containerengine_cluster_kube_config" "cluster_kube_config" {
  cluster_id    = oci_containerengine_cluster.k8s_cluster.id
  expiration    = 2592000
  token_version = "2.0.0"
}

# https://www.terraform.io/docs/providers/local/r/file.html
resource "local_file" "kubeconfig" {
  content  = data.oci_containerengine_cluster_kube_config.cluster_kube_config.content
  filename = pathexpand("$HOME/.kube/ociconfig")
}

resource "digitalocean_record" "main" {
  count  = var.oke["nodes_per_subnet"]
  name   = "*"
  domain = "mksybr.com"
  type   = "A"
  value  = oci_containerengine_node_pool.k8s_node_pool.nodes[count.index].public_ip
  ttl    = "30"
}
