provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "cupa" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "cupa-test-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id = aws_vpc.cupa.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"
  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id = aws_vpc.cupa.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "private-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "cupa" {
  vpc_id = aws_vpc.cupa.id
  tags = {
    Name = "cupa-igw"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.cupa.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cupa.id
  }
  tags = {
    Name = "public-route-table"
  }
}

# Associate Route Table with Subnet
resource "aws_route_table_association" "public" {
  subnet_id = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "ec2" {
  vpc_id = aws_vpc.cupa.id
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "cupa-ec2-security-group"
  }
}

# EC2 instance
resource "aws_instance" "web" {
  ami = "ami-0c02fb55956c7d316" # Replace with a valid AMI ID for your region
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public.id
  security_groups = [
    aws_security_group.ec2.name
  ]
  tags = {
    Name = "web-cupa-instance"
  }
}

# RDS instance
resource "aws_db_instance" "database" {
  allocated_storage = 20
  storage_type = "gp2"
  engine = "mysql"
  engine_version = "8.0"
  instance_class = "db.t2.micro"
  username = "admin"
  password = "password123"
  publicly_accessible = false
  skip_final_snapshot = true
  vpc_security_group_ids = [
    aws_security_group.ec2.id
  ]
  db_subnet_group_name = aws_db_subnet_group.cupa.name
  tags = {
    Name = "cupa-database"
  }
}

# Subnet Group for RDS
resource "aws_db_subnet_group" "cupa" {
  name = "cupa-db-subnet-group"
  subnet_ids = [aws_subnet.private.id]

  tags = {
    Name = "cupa-db-subnet-group"
  }
}

# Load Balancer
resource "aws_lb" "cupa" {
  name = "cupa-lb"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.ec2.id]
  subnets = [aws_subnet.public.id]

  tags = {
    Name = "cupa-load-balancer"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.cupa.arn
  port = 80
  protocol = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.cupa.arn
  }
}

resource "aws_lb_target_group" "cupa" {
  name = "cupa-target-group"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.cupa.id
  target_type = "instance"
}

resource "aws_lb_target_group_attachment" "cupa" {
  target_group_arn = aws_lb_target_group.cupa.arn
  target_id = aws_instance.web.id
  port = 80
}

# CloudFront
resource "aws_cloudfront_distribution" "cupa" {
  origin {
    domain_name = aws_lb.cupa.dns_name
    origin_id = "cupa-lb"
  }

  enabled = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = "cupa-lb"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "cupa-cloudfront"
  }
}
