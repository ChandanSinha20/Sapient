locals {
  project_id = "internal-interview-candidates"
  ssh_user         = "ansible"
  private_key_path = "/home/chandansinha20/.ssh/ansible_ed25519"
}

provider "google" {
  project = local.project_id
  region  = "us-central1"
  zone    = "us-central1-b"
}

# VPC Network

resource "google_compute_network" "vpc_network" {
  name                    = "chandan-vpc-network"
  auto_create_subnetworks = false
  delete_default_routes_on_create = true

}

# Subnet

resource "google_compute_subnetwork" "private_network" {
  name          = "chandan-private-network"
  ip_cidr_range = "10.2.0.0/16"
  network       = google_compute_network.vpc_network.self_link
}

resource "google_compute_router" "router" {
  name    = "chandan-router"
  network = google_compute_network.vpc_network.self_link
}

resource "google_compute_router_nat" "nat" {
  name                               = "chandan-router-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_route" "private_network_internet_route" {
  name             = "chandan-network-internet"
  dest_range       = "0.0.0.0/0"
  network          = google_compute_network.vpc_network.self_link
  next_hop_gateway = "default-internet-gateway"
  priority    = 100
}

resource "google_compute_instance" "vm_instance_1" {
  name         = "chandan-nginx-instance-1"
  machine_type = "f1-micro"

  tags = ["chandan-nginx-instance"]

  boot_disk {
    initialize_params {
      image = "centos-7-v20210420"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.self_link
    subnetwork = google_compute_subnetwork.private_network.self_link    
    access_config {
    network_tier = "STANDARD"
     }
  }
    provisioner "remote-exec" {
    inline = ["echo 'Wait until SSH is ready'"]
    }
    connection {
      type        = "ssh"
      user        = local.ssh_user
      private_key = file(local.private_key_path)
      host        = google_compute_instance.vm_instance_1.network_interface.0.access_config.0.nat_ip
    }
    provisioner "local-exec" {
    command = "ansible-playbook  -i ${google_compute_instance.vm_instance_1.network_interface.0.access_config.0.nat_ip}, --private-key ${local.private_key_path} nginx.yaml"
  }
  
}

resource "google_compute_instance" "vm_instance_2" {
  name         = "chandan-nginx-instance-2"
  machine_type = "f1-micro"

  tags = ["chandan-nginx-instance"]

  boot_disk {
    initialize_params {
      image = "centos-7-v20210420"
    }
  }

    network_interface {
    network = google_compute_network.vpc_network.self_link
    subnetwork = google_compute_subnetwork.private_network.self_link    
    access_config {
      network_tier = "STANDARD"
     }
  }
  provisioner "remote-exec" {
    inline = ["echo 'Wait until SSH is ready'"]
    }
    connection {
      type        = "ssh"
      user        = local.ssh_user
      private_key = file(local.private_key_path)
      host        = google_compute_instance.vm_instance_2.network_interface.0.access_config.0.nat_ip
    }
    provisioner "local-exec" {
    command = "ansible-playbook  -i ${google_compute_instance.vm_instance_2.network_interface.0.access_config.0.nat_ip}, --private-key ${local.private_key_path} nginx.yaml"
  }
}

resource "google_compute_firewall" "public_ssh" {
   name    = "public-ssh"
   network = google_compute_network.vpc_network.self_link

   allow {
     protocol = "tcp"
     ports    = ["22","80"]
   }

   direction = "INGRESS"
   source_ranges = ["0.0.0.0/0"]
   target_tags = ["chandan-nginx-instance"]
 }


resource "google_compute_instance_group" "webservers" {
  name        = "chandan-webservers"
  description = "Terraform test instance group"

  instances = [
    google_compute_instance.vm_instance_1.self_link,
    google_compute_instance.vm_instance_2.self_link
  ]

  named_port {
    name = "http"
    port = "8080"
  }
}

# Global health check
resource "google_compute_health_check" "webservers-health-check" {
  name        = "chandan-webservers-health-check"
  description = "Health check via tcp"

  timeout_sec         = 5
  check_interval_sec  = 10
  healthy_threshold   = 3
  unhealthy_threshold = 2

  tcp_health_check {
    port_name          = "http"
  }  
}

# Global backend service
resource "google_compute_backend_service" "webservers-backend-service" {

  name                            = "chandan-webservers-backend-service"
  timeout_sec                     = 30
  connection_draining_timeout_sec = 10
  load_balancing_scheme = "EXTERNAL"
  protocol = "HTTP"
  port_name = "http"
  health_checks = [google_compute_health_check.webservers-health-check.self_link]

  backend {
    group = google_compute_instance_group.webservers.self_link
    balancing_mode = "UTILIZATION"
  }
}

resource "google_compute_url_map" "default" {

  name            = "chandan-website-map"
  default_service = google_compute_backend_service.webservers-backend-service.self_link
}

# Global http proxy
resource "google_compute_target_http_proxy" "default" {

  name    = "chandan-website-proxy"
  url_map = google_compute_url_map.default.id
}

# Regional forwarding rule
resource "google_compute_forwarding_rule" "webservers-loadbalancer" {
  name                  = "chandan-website-forwarding-rule"
  ip_protocol           = "TCP"
  port_range            = 80
  load_balancing_scheme = "EXTERNAL"
  network_tier          = "STANDARD"
  target                = google_compute_target_http_proxy.default.id
}

resource "google_compute_firewall" "load_balancer_inbound" {
  name    = "chandan-nginx-load-balancer"
  network = google_compute_network.vpc_network.self_link

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  direction = "INGRESS"
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags = ["nginx-instance"]
}


resource "google_project_iam_custom_role" "chandan-custom-role" {
  role_id     = "myCustomRole"
  title       = "chandan Webserver restart"
  description = "A description"
  permissions = ["compute.instances.reset", "compute.instances.start"]
}
