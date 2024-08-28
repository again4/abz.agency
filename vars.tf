variable "public_cidr_block" {
   description = "available cidr blocks for public subnets"
   type = list(string)
   default = [ "10.0.1.0/24" ]
}


variable "private_cidr_blocks" {
    description = "available cidr blocks for private subnets"
    type = list(string)
    default = [ "10.0.101.0/24" , "10.0.102.0/24"]
  
}

variable "db_username" {
  description = "database username"
  type = string
  sensitive = true
}


variable "db_password" {
  description = "database password"
  type = string
  sensitive = true
}