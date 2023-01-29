### Provider definition

provider "aws" {
  region = var.aws_region
}

### Module Main
module "discovery" {
  source     = "github.com/Lowess/terraform-aws-discovery"
  aws_region = var.aws_region
  vpc_name   = var.vpc_name
  ec2_ami_names       = ["restaurant-v2"]
  ec2_ami_owners      = "954598331238"
}

output "disco" {
  value = module.discovery
}


### SECURITY GROUPS ###
resource "aws_security_group" "alb_security_group" {
  name        = "ALB security group"
  description = "Allow port 80"
  vpc_id      = module.discovery.vpc_id

  tags = {
    Name = "${var.app_name}-alb"
  }
}

resource "aws_security_group" "app_security_group" {
  name        = "App security group"
  description = "Allow port 8080"
  vpc_id      = module.discovery.vpc_id

  tags = {
    Name = "secu_group_app"
  }
}

### SECURITY RULES ###
resource "aws_security_group_rule" "alb_rule_ingress_80" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb_security_group.id
}

resource "aws_security_group_rule" "alb_rule_ingress_19999" {
  type              = "ingress"
  from_port         = 19999
  to_port           = 19999
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb_security_group.id
}

resource "aws_security_group_rule" "alb_rule_egress_all" {
  type              = "egress"
  from_port         = -1
  to_port           = -1
  protocol          = -1
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb_security_group.id
}


resource "aws_security_group_rule" "app_rule_ingress_all" {
  type                            = "ingress"
  from_port                       = -1
  to_port                         = -1
  protocol                        = -1
  source_security_group_id = aws_security_group.alb_security_group.id
  security_group_id               = aws_security_group.app_security_group.id
}

resource "aws_security_group_rule" "app_rule_egress_all" {
  type                            = "egress"
  from_port                       = -1
  to_port                         = -1
  protocol                        = -1
  source_security_group_id = aws_security_group.alb_security_group.id
  security_group_id               = aws_security_group.app_security_group.id
}

### LOAD BALANCER ###
resource "aws_lb" "alb" {
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_security_group.id]
  subnets            = [for subnet in module.discovery.public_subnets : subnet]

  tags = {
    Name = "${var.app_name}-alb-public"
  }
}

### TARGET GROUP ALB
resource "aws_lb_target_group" "alb_target_group_web" {
  name     = "targetWeb"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = module.discovery.vpc_id

  tags = {
    "Name" = "${var.app_name}-alb-http"
  }
}

resource "aws_lb_target_group" "alb_target_group_netdata" {
  name     = "target"
  port     = 19999
  protocol = "HTTP"
  vpc_id   = module.discovery.vpc_id

  tags = {
    "Name" = "${var.app_name}-alb-http"
  }
}

### LOAD BALANCER LISTENER
resource "aws_lb_listener" "alb_listener_web" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group_web.arn
  }
}

resource "aws_lb_listener" "alb_listener_netdata" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "19999"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group_netdata.arn
  }
}

### LAUNCH TEMPLATE FOR APP
resource "aws_launch_template" "launch_app" {
  instance_type = "t2.micro"
  key_name = "deployer-key"
  image_id = module.discovery.images_id[0]

  vpc_security_group_ids = [aws_security_group.app_security_group.id]

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "test"
    }
  }
}

### AUTOSCALING GROUP
resource "aws_autoscaling_group" "bar" {
  name = "auto_scaling_${var.app_name}"
  vpc_zone_identifier = module.discovery.private_subnets
  max_size           = 2
  min_size           = 1
  target_group_arns = ["${aws_lb_target_group.alb_target_group_web.arn}", "${aws_lb_target_group.alb_target_group_netdata.arn}"]

  launch_template {
    id      = aws_launch_template.launch_app.id
    version = "$Latest"
  }  
}

### AUTOSCALING POLICIES
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "aws_autoscaling_policy_down"
  autoscaling_group_name = aws_autoscaling_group.bar.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 120
}

resource "aws_cloudwatch_metric_alarm" "scale_down" {
  alarm_description   = "monitoring CPU"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
  alarm_name          = "alarm_scale_down"
  comparison_operator = "LessThanOrEqualToThreshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  threshold           = "4"
  evaluation_periods  = "1"
  period              = "60"
  statistic           = "Average"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.bar.name
  }
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "aws_autoscaling_policy_up"
  autoscaling_group_name = aws_autoscaling_group.bar.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 120
}

resource "aws_cloudwatch_metric_alarm" "scale_up" {
  alarm_description   = "monitoring CPU"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
  alarm_name          = "alarm_scale_up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  threshold           = "7"
  evaluation_periods  = "1"
  period              = "60"
  statistic           = "Average"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.bar.name
  }
}
