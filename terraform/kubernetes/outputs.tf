output "bankapp_namespace" {
  description = "Managed BankApp Kubernetes namespace"
  value       = kubernetes_namespace_v1.bankapp.metadata[0].name
}

output "bankapp_deployment" {
  description = "Managed BankApp Kubernetes deployment"
  value       = kubernetes_deployment_v1.bankapp.metadata[0].name
}

output "bankapp_service" {
  description = "Managed BankApp Kubernetes service"
  value       = kubernetes_service_v1.bankapp.metadata[0].name
}

output "kubernetes_context" {
  description = "Kubernetes context used by Terraform"
  value       = "kind-aws-devops-local"
}
