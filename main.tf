terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"    
    }
  }
}

provider "aws" {
    region = "eu-west-3"
    profile = "admin2"
    shared_credentials_files = ["./aws/credentials"]

}

module myip {
  source  = "4ops/myip/http"
  version = "1.0.0"
}

data "aws_availability_zones" "available"{
    state = "available"
}


resource "aws_vpc" "myvpc" {
    cidr_block = "10.0.0.0/16"
    enable_dns_hostnames = true

    tags = {
        Name = "MyVpc"
    }
  
}


resource "aws_internet_gateway" "mygw" {
  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "MyIG"
  }
  depends_on = [aws_vpc.myvpc]
}



resource "aws_subnet" "public_subnet" {
  count = 1
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = var.public_cidr_block[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]


  tags = {
    Name = "public_subnet_${count.index}"
  }
}



resource "aws_subnet" "private_subnets" {
  count = 2
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = var.private_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index + 1]

  tags = {
    Name = "private_subnets_${count.index}"
  }
}


resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.myvpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mygw.id
  }
}


resource "aws_route_table_association" "public" {

  count = 1
  route_table_id = aws_route_table.public_rt.id
  subnet_id = aws_subnet.public_subnet[count.index].id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.myvpc.id

}


resource "aws_route_table_association" "private" {
  count = 2
  route_table_id = aws_route_table.private_rt.id
  subnet_id = aws_subnet.private_subnets[count.index].id
  
}

resource "aws_security_group" "SG_for_EC2" {
  name        = "SG_for_EC2"
  description = "Allow 80, 443, 22 port inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "TLS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${module.myip.address}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "SG_for_RDS" {
  name        = "SG_for_RDS"
  description = "Allow MySQL inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description     = "RDS from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.SG_for_EC2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  depends_on = [aws_security_group.SG_for_EC2]
}



resource "aws_security_group" "SG_for_Redis" {
  name        = "SG_for_Redis"
  description = "Allow Redis inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description     = "Redis from EC2"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.SG_for_EC2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  depends_on = [aws_security_group.SG_for_EC2]
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name = "db_subnet_group"
  description = "DB subnet group "
  subnet_ids  = [
    aws_subnet.private_subnets[0].id,  # eu-west-3b
    aws_subnet.private_subnets[1].id   # eu-west-3c
  ]

}


resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "redis-subnet-group"  # Use hyphens instead of underscores
  subnet_ids = [
    aws_subnet.private_subnets[0].id,
    aws_subnet.private_subnets[1].id
  ]

  tags = {
    Name = "RedisSubnetGroup"
  }
}




resource "aws_db_instance" "database" {
  allocated_storage    = 10
  db_name              = "mydb"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  username             = var.db_username
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.id
  vpc_security_group_ids = [aws_security_group.SG_for_RDS.id]
  skip_final_snapshot = true
}





resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "redis"
  description          = "redis with authentication"
  node_type            = "cache.t2.micro"
  num_cache_clusters   = 1
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids   = [aws_security_group.SG_for_Redis.id]
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"

  transit_encryption_enabled = true
  auth_token                 = "thistokenfortestTASK777"
  auth_token_update_strategy = "ROTATE"
}

resource "aws_key_pair" "test_kp" {
  key_name   = "test_kp"
  public_key = file("test_kp.pub")  
}


resource "aws_instance" "ec2" {
  count = 1
  ami           = "ami-04a92520784b93e73"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public_subnet[count.index].id
  key_name = aws_key_pair.test_kp.key_name
  vpc_security_group_ids = [aws_security_group.SG_for_EC2.id]


  tags = {
    Name = "ubuntu_instance"
  }
}
 
resource "aws_eip" "ec2_eip" {
  count = 1
  instance = aws_instance.ec2[count.index].id
  domain = "vpc"
  tags = {
    Name = "ec2_eip"
  }
}


