# ECS Cluster
resource "aws_ecs_cluster" "this" {
  name = var.cluster_name
}

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

# ECS EC2 Launch Template
resource "aws_launch_template" "ecs_instance" {
  name_prefix   = "ecs-instance"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.ssm_instance_type
  
  user_data = base64encode(templatefile("${path.module}/scripts/amazon2_user_data.sh", {
    cluster_name = var.cluster_name
  }))

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [var.security_group_id]
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.ssm_ec2_profile.name
  }

  key_name = var.key_name
}

# ECS Auto Scaling Group
resource "aws_autoscaling_group" "ecs_asg" {
  desired_capacity     = 1
  max_size             = 1
  min_size             = 1
  vpc_zone_identifier  = var.subnet_ids
  launch_template {
    id      = aws_launch_template.ecs_instance.id
    version = "$Latest"
  }
  instance_refresh {
    strategy = "Rolling"
    # triggers = ["launch_template"]
  }

  tag {
    key                 = "Name"
    value               = "ecs-ec2-instance"
    propagate_at_launch = true
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "nginx" {
  family                   = "nginx-task"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  cpu                      = "512"
  memory                   = "768"

  container_definitions = jsonencode([
    {
      name      = "nginx"
      image     = "nginx:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 8080
        }
      ],
      command = [
        "sh", "-c", "echo \"<h1>Hello from $(hostname)</h1>\" > /usr/share/nginx/html/index.html && nginx -g 'daemon off;'"
      ]
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "nginx" {
  name            = "nginx-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.nginx.arn
  launch_type     = "EC2"
  desired_count   = 1

  # network_configuration {
  #   subnets         = var.subnet_ids    
  #   security_groups = [var.security_group_id]
  #   assign_public_ip = true
  # }

  depends_on = [aws_autoscaling_group.ecs_asg]
}

# ===========================================

resource "aws_iam_role" "ssm_ec2_role" {
  name = "ssm_ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# SSM
resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# S3
resource "aws_iam_role_policy_attachment" "s3_attach" {
  role       = aws_iam_role.ssm_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# 
resource "aws_iam_role_policy_attachment" "ecs_instance_policy" {
  role       = aws_iam_role.ssm_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# 
resource "aws_iam_instance_profile" "ssm_ec2_profile" {
  name = "ssm_ec2_profile"
  role = aws_iam_role.ssm_ec2_role.name
}
