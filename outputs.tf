
output "public_ip" {
  description = "The public IP address of the web server"

  value       = aws_eip.ec2_eip[0].public_ip


  depends_on = [aws_eip.ec2_eip]
}


output "domain" {
  description = "The public DNS address of the web server"

  value       = aws_eip.ec2_eip[0].public_dns

  depends_on = [aws_eip.ec2_eip]
}


output "database_endpoint" {
  description = "The endpoint of the database"
  value       = aws_db_instance.database.address
}


output "database_port" {
  description = "The port of the database"
  value       = aws_db_instance.database.port
}



output "redis_host" {
  value = "${aws_elasticache_replication_group.redis.primary_endpoint_address}"
}
