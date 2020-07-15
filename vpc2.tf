#AWS
provider "aws" {
  region = "ap-south-1"
}

#VARIABLES
variable "vpc_cidr" {
  description = "CIDR for the whole VPC"
  default = "192.10.0.0/16"
}


#MAIN VPC
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
  tags = {
    Name = "MyVPC"
  }
}

#PUBLIC SUBNET
resource "aws_subnet" "subnet_public" {
  vpc_id = aws_vpc.main.id
  cidr_block = "192.10.0.0/24"
  map_public_ip_on_launch = true
  availability_zone = "ap-south-1a"

  tags = {
    Name = "Public Subnet"
  }
}

resource "aws_route_table" "public_subnet_route" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.rt_gateway.id
  }

  tags = {
    Name = "public_ig"
  }
}

resource "aws_route_table_association" "public_route" {
  subnet_id = aws_subnet.subnet_public.id
  route_table_id = aws_route_table.public_subnet_route.id
}


#PRIVATE SUBNET
resource "aws_subnet" "subnet_private" {
  vpc_id = aws_vpc.main.id
  availability_zone = "ap-south-1b"
  cidr_block = "192.10.1.0/24"
  map_public_ip_on_launch = false

  tags = {
   Name = "Private Subnet"
  }
}

#BASTION HOST SECURITY GROUP
resource "aws_security_group" "bastion_sec" {
  name = "bastion-sec"
  description = "Allow Bastion Host traffic outbound via SSH protocol"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "TCP"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "TCP"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
   }
  
  tags = {
    Name = "Bastion Security"
  }
}


#WORDPRESS SERVER SECURITY GROUP
resource "aws_security_group" "wordpress_sec" {
  name = "wordpress-sec"
  description = "Allow all traffic inbound"

  ingress {
    description = "TCP"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "TCP"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
  ingress {
    description = "ICMP"
    from_port = -1
    to_port = -1
    protocol = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #MYSQL
  egress { 
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.main.id
}


#MYSQL SERVER BASTION SECURITY GROUP
resource "aws_security_group" "mariadb_private_bastion_sec" {
  name = "mariadb-private-bastion-sec"
  description = "Allow only Bastion Host traffic inbound via SSH protocol"
  vpc_id = aws_vpc.main.id 
  tags = {
    Name = "Bastion"
  }

  ingress {
    description = "Allow Bastion Hosts"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    security_groups = [aws_security_group.bastion_sec.id]
  }

  egress {
    description = "Allow Bastion Host outbound"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    security_groups = [aws_security_group.bastion_sec.id]
  }
}

#MARIADB SERVER SECURITY GROUP 
resource "aws_security_group" "mariadb_sec" {
  name = "mariadb-sec"
  description = "Allow only Apache Webserver traffic inbound"
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "MariaDB DB"
  }

  ingress {
    description = "MySQL Server"
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = [aws_security_group.wordpress_sec.id]
  }

  ingress {
    description = "Allow Bastion Host traffic"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    security_groups =[aws_security_group.mariadb_private_bastion_sec.id]
  }

  ingress {
    description = "Allow Bastion Host traffic"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    security_groups = [aws_security_group.bastion_sec.id]
  }

  egress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    
  egress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#INTERNET GATEWAY
resource "aws_internet_gateway" "rt_gateway" {
  vpc_id = aws_vpc.main.id
}

#ELASTIC IP
resource "aws_eip" "nat" {
  vpc = true
}

#NAT GATEWAY
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.subnet_private.id
  depends_on = [aws_internet_gateway.rt_gateway]

  tags = {
    Name = "NAT Gateway"
  }
}
 
#MYSQL INSTANCE
resource "aws_instance" "mariadb" {
  ami = "ami-0a535e86e53aae5f1"
  availability_zone = "ap-south-1b"
  instance_type = "t2.micro"
  key_name = "mykey"
  vpc_security_group_ids = [aws_security_group.mysql_sec.id]
  subnet_id = aws_subnet.subnet_private.id
  associate_public_ip_address = false

  tags = {
    Name = "DB Server"
  }
}

#WORDPRESS INSTANCE
resource "aws_instance" "wordpress" {
  ami = "ami-048d9e7052b09fe92"
  availability_zone = "ap-south-1a"
  instance_type = "t2.micro"
  key_name = "mykey"
  vpc_security_group_ids = [aws_security_group.wordpress_sec.id]
  subnet_id = aws_subnet.subnet_public.id
  associate_public_ip_address = true  

  tags = {
    Name = "WP Server"
  }
}

#BASTION INSTANCE
resource "aws_instance" "bastion" {
  ami = "ami-00b494a3f139ba61f"
  availability_zone = "ap-south-1a"
  instance_type = "t2.micro"
  key_name = "mykey"
  vpc_security_group_ids = [aws_security_group.bastion_sec.id]
  subnet_id = aws_subnet.subnet_public.id
  associate_public_ip_address = true

  tags = {
    Name = "Bastion"
  }
}




