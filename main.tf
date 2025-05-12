
provider "aws" {
  access_key = var.aws_access_key_id
  secret_key = var.aws_secret_access_key
  region     = var.aws_region
}


resource "aws_ecs_cluster" "my_cluster" {
  name = "my-cluster"
}


resource "aws_ecs_task_definition" "my_task" {
  family                   = "my-task-definition"
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  cpu                      = "256"
  memory                   = "512"
  requires_compatibilities = ["FARGATE"]

  container_definitions = jsonencode([{
    name      = "my-container"
    image     = "nginx:latest" # Replace with your container image
    cpu       = 256
    memory    = 512
    essential = true
    portMappings = [
      {
        containerPort = 80
        hostPort      = 80
        protocol      = "tcp"
      }
    ]
  }])
}


resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs_task_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_security_group" "ecs_sg" {
  name        = "ecs-security-group"
  description = "Allow all inbound traffic to ECS containers"
  vpc_id      = "vpc-0b5a0b67b5bd9332b"  # Replace with your VPC ID

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_service" "my_service" {
  name            = "my-ecs-service"
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.my_task.arn
  desired_count   = 1
  launch_type     = "EC2"  # Changed to EC2
  network_configuration {
    subnets          = ["subnet-03ec181f1ae0fcdfd"] # Replace with your subnet IDs
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.my_target_group.arn
    container_name   = "my-container"
    container_port   = 80
  }

  depends_on = [
    aws_lb_target_group.my_target_group,
    aws_lb_listener.my_listener
  ]


}

resource "aws_instance" "ecs_instance" {
  ami           = "ami-0f88e80871fd81e91"  # Replace with your ECS-optimized AMI ID
  instance_type = "t2.micro"
  
  iam_instance_profile = aws_iam_instance_profile.test_profile_2.name

  security_groups = [aws_security_group.ecs_sg.name]

  tags = {
    Name = "ECS Instance"
  }

  # Attach the instance to the ECS cluster
  user_data = <<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${aws_ecs_cluster.my_cluster.name} >> /etc/ecs/ecs.config
              EOF
}


# Create an Application Load Balancer
resource "aws_lb" "my_alb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_sg.id]
  subnets            = ["subnet-03ec181f1ae0fcdfd","subnet-0d1283b7c81041b04"]  # Replace with your subnet IDs
  enable_deletion_protection = false

  enable_cross_zone_load_balancing = true

  tags = {
    Name = "My-ALB"
  }
}

# Create a Target Group for ECS
resource "aws_lb_target_group" "my_target_group" {
  name     = "my-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "vpc-0b5a0b67b5bd9332b"  # Replace with your VPC ID

  target_type = "ip"


  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "My-Target-Group"
  }
}

# Create a listener for the ALB
resource "aws_lb_listener" "my_listener" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    target_group_arn = aws_lb_target_group.my_target_group.arn
    fixed_response {
      status_code = 200
      content_type = "text/plain"
      message_body = "OK"
    }
  }
}



resource "aws_iam_role" "example" {
  name               = "ec2_ssm_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.example.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"
}


resource "aws_iam_instance_profile" "test_profile_2" {
  name = "test_profile_2"
  role = aws_iam_role.example.name
}