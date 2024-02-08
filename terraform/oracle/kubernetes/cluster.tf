# https://www.terraform.io/docs/providers/oci/r/containerengine_cluster.html
resource "oci_containerengine_cluster" "k8s_cluster" {
  #Required
  compartment_id     = module.secrets.oci_compartment_id
  kubernetes_version = var.oke["version"]
  name               = var.oke["name"]
  vcn_id             = oci_core_vcn.oke_vcn.id

  type = "BASIC_CLUSTER"
  # #Optional
  # options {
  #   service_lb_subnet_ids = ["${oci_core_subnet.loadbalancer_subnet1.id}", "${oci_core_subnet.loadbalancer_subnet2.id}"]
  # }
}

# https://www.terraform.io/docs/providers/oci/r/containerengine_node_pool.html
resource "oci_containerengine_node_pool" "k8s_node_pool" {
  #Required
  cluster_id         = oci_containerengine_cluster.k8s_cluster.id
  compartment_id     = module.secrets.oci_compartment_id
  kubernetes_version = var.oke["version"]
  name               = var.oke["name"]
  node_shape         = var.oke["shape"]
  node_shape_config {
    memory_in_gbs = "6"
    ocpus         = "1"
  }
  node_source_details {
    source_type = "IMAGE"
    image_id    = var.image_id
  }
  subnet_ids          = ["${oci_core_subnet.worker_subnet1.id}", "${oci_core_subnet.worker_subnet2.id}", "${oci_core_subnet.worker_subnet3.id}"]
  quantity_per_subnet = var.oke["nodes_per_subnet"]
  ssh_public_key      = module.secrets.ssh_authorized_keys
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
  filename = "$HOME/.kube/ociconfig"
}

resource "digitalocean_record" "main" {
  count  = var.oke["nodes_per_subnet"]
  name   = "x"
  domain = "mksybr.com"
  type   = "A"
  value  = oci_containerengine_node_pool.k8s_node_pool.nodes[count.index].public_ip
  ttl    = "30"
}
