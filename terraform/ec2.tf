# Provider Configuration
provider "aws" {
  region = var.aws_region
}
# Create Security group for ALB
resource "aws_security_group" "alb-shield-sg" {
  name        = "alb-shield-secgroup"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.shield-vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create an App Security group to allow traffic from ALB only
resource "aws_security_group" "app-shield-sg" {
  name        = "app-shield-secgroup"
  description = "Security group for Application servers"
  vpc_id      = aws_vpc.shield-vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb-shield-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM for SSM
resource "aws_iam_role" "shield_ec2_ssm_role" {
  name = "shield-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "shield_ec2_role_attachment" {
  role       = aws_iam_role.shield_ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "shield_ec2_instance_profile" {
  name = "shield-ec2-instance-profile"
  role = aws_iam_role.shield_ec2_ssm_role.name
}

# Create a Launch Template using Amazon Linux 2023 AMI and install NGINX
resource "aws_launch_template" "app-shield-lt" {
  name_prefix   = "app-shield-lt-"
  image_id      = "ami-0bdd88bd06d16ba03" # Amazon Linux 2023 AMI in us-east-1
  instance_type = "t3.micro"
  vpc_security_group_ids = [aws_security_group.app-shield-sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.shield_ec2_instance_profile.name
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install nginx1 -y
              systemctl start nginx
              systemctl enable nginx
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "app-shield-instance"
    }
  }
}

# Create an ASG (2-4 instances) in Private Subnets
resource "aws_autoscaling_group" "app-shield-asg" {
  desired_capacity     = 2
  max_size             = 4
  min_size             = 2
  health_check_type   = "EC2"
  health_check_grace_period = 60

  launch_template {
    id      = aws_launch_template.app-shield-lt.id
    version = "$Latest"
  }
   
  vpc_zone_identifier = [
    aws_subnet.private-subnet-1.id,
    aws_subnet.private-subnet-2.id
  ]

  tag {
    key                 = "Name"
    value               = "app-shield-asg-instance"
    propagate_at_launch = true
  }
}

# ALB in Public Subnets
resource "aws_lb" "app-shield-alb" {
  name               = "app-shield-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb-shield-sg.id]
  subnets            = [
    aws_subnet.public-subnet-1.id,
    aws_subnet.public-subnet-2.id
  ]

  tags = {
    Name = "app-shield-alb"
  }
}

resource "aws_lb_target_group" "app-shield-tg" {
  name     = "app-shield-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.shield-vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "app-shield-tg"
  }
}

resource "aws_lb_listener" "app-shield-listener" {
  load_balancer_arn = aws_lb.app-shield-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app-shield-tg.arn
  }
}
# Attach ASG to Target Group
resource "aws_autoscaling_attachment" "app-shield-asg-attachment" {
  autoscaling_group_name = aws_autoscaling_group.app-shield-asg.name
  lb_target_group_arn    = aws_lb_target_group.app-shield-tg.arn
}

# Logging and Monitoring by Cloudwatch to enable VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flow-logs/shield-vpc-flow-logs"
  retention_in_days = 14
}
resource "aws_flow_log" "shield_vpc_flow_log" {
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  log_destination_type = "cloud-watch-logs"
  iam_role_arn        = aws_iam_role.vpc_flow_logs_role.arn
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.shield-vpc.id
}
resource "aws_iam_role" "vpc_flow_logs_role" {
  name = "shield-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "vpc_flow_logs_role_attachment" {
  role       = aws_iam_role.vpc_flow_logs_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonVPCCFlowLogsRole"
}

data "aws_iam_policy_document" "vpc_flow_logs_role_policy" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = [
      aws_cloudwatch_log_group.vpc_flow_logs.arn
    ]
  }
}


# Create simple ALB 5XX alarm
resource "aws_cloudwatch_metric_alarm" "alb_5xx_alarm" {
  alarm_name          = "app-shield-alb-5xx-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5

  dimensions = {
    LoadBalancer = aws_lb.app-shield-alb.name
  }

  alarm_description = "Alarm when ALB returns 5XX errors"
}

# verify access via ALB DNS + SSM 
resource "aws_ssm_document" "alb_access" {
  name          = "app-shield-alb-access"
  document_type = "Session"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Session document to verify access to ALB"
    mainSteps     = [
      {
        action = "aws:runCommand"
        name   = "verifyALBAccess"
        inputs = {
          DocumentName = "AWS-RunShellScript"
          Parameters = {
            commands = [
              "curl -I ${aws_lb.app-shield-alb.dns_name}"
            ]
          }
        }
      }
    ]
  })
}
