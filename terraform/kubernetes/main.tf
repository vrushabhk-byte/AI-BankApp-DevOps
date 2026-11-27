resource "kubernetes_namespace_v1" "bankapp" {
  metadata {
    name = "bankapp"

    labels = {
      app = "bankapp"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_deployment_v1" "bankapp" {
  metadata {
    name      = "bankapp"
    namespace = kubernetes_namespace_v1.bankapp.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "bankapp"
      }
    }

    strategy {
      type = "RollingUpdate"

      rolling_update {
        max_surge       = "25%"
        max_unavailable = "25%"
      }
    }

    template {
      metadata {
        labels = {
          app = "bankapp"
        }
      }

      spec {
        automount_service_account_token = false
        enable_service_links            = false

        container {
          name              = "bankapp"
          image             = "ai-bankapp:ci-14"
          image_pull_policy = "Never"

          port {
            container_port = 8080
            protocol       = "TCP"
          }

          env {
            name  = "MYSQL_HOST"
            value = "mysql"
          }

          env {
            name  = "MYSQL_PORT"
            value = "3306"
          }

          env {
            name  = "MYSQL_DATABASE"
            value = "bankappdb"
          }

          env {
            name  = "MYSQL_USER"
            value = "root"
          }

          env {
            name = "MYSQL_PASSWORD"

            value_from {
              secret_key_ref {
                name = "bankapp-secrets"
                key  = "MYSQL_ROOT_PASSWORD"
              }
            }
          }

          env {
            name  = "OLLAMA_URL"
            value = "http://ollama:11434"
          }

          liveness_probe {
            http_get {
              path   = "/actuator/health"
              port   = 8080
              scheme = "HTTP"
            }

            initial_delay_seconds = 90
            period_seconds        = 20
            timeout_seconds       = 5
            failure_threshold     = 5
          }

          readiness_probe {
            http_get {
              path   = "/actuator/health"
              port   = 8080
              scheme = "HTTP"
            }

            initial_delay_seconds = 60
            period_seconds        = 15
            timeout_seconds       = 5
            failure_threshold     = 6
          }
        }
      }
    }
  }

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      wait_for_rollout,
      spec[0].template[0].spec[0].container[0].image
    ]
  }

  depends_on = [
    kubernetes_namespace_v1.bankapp
  ]
}

resource "kubernetes_service_v1" "bankapp" {
  metadata {
    name      = "bankapp"
    namespace = kubernetes_namespace_v1.bankapp.metadata[0].name
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "bankapp"
    }

    port {
      name        = "http"
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }
  }

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      wait_for_load_balancer
    ]
  }

  depends_on = [
    kubernetes_namespace_v1.bankapp
  ]
}
