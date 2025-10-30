output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.app-shield-alb.dns_name
}
output "alb_url" {
  description = "The URL of the Application Load Balancer"
  value       = "http://${aws_lb.app-shield-alb.dns_name}"
}
