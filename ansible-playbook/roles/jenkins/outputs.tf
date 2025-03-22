output "jenkins_alb_dns" {
  value = aws_lb.jenkins_alb.dns_name
}

output "jenkins_sg_id" {
  value = aws_security_group.jenkins_sg.id
}