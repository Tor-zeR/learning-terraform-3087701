data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = [element(var.ami_filter.name, 0)] # Select the first element of the name list
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [element(var.ami_filter.owner, 0)] # Select the first element of the owner list
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.environment.name}-blog-vpc"
  cidr = "${var.environment.network_prefix}.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  
  public_subnets  = ["${var.environment.network_prefix}.101.0/24", "${var.environment.network_prefix}.102.0/24", "${var.environment.network_prefix}.103.0/24"]

  enable_nat_gateway = false

  tags = {
    Terraform = "true"
    Environment = var.environment.name
  }
}


module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "6.10.0"
  
  name     = "${var.environment.name}-blog-asc"
  min_size = var.asg_min_size
  max_size = var.asg_max_size

  vpc_zone_identifier = module.vpc.public_subnets
  target_group_arns = module.blog_alb.target_group_arns
  security_groups = [module.blog_sg.security_group_id]

  image_id      = data.aws_ami.app_ami.id
  instance_type = var.instance_type
}

module "blog_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name = "${var.environment.name}-blog-alb"

  load_balancer_type = "application"

  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
  security_groups    = [module.blog_sg.security_group_id]  # Use module.blog_sg here

  target_groups = [
    {
      name_prefix      = "${var.environment.name}-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"

    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    Environment = var.environment.name
  }
}

module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"
  name = "${var.environment.name}-blog-sg"

  vpc_id              = module.vpc.vpc_id  # Use module.vpc.vpc_id here

  ingress_rules       = ["http-80-tcp" , "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules        = [ "all-all" ]
  egress_cidr_blocks  = ["0.0.0.0/0"]
}
