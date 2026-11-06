# 1. ECR Repositories (To store Docker images)
resource "aws_ecr_repository" "web_repo" {
  name                 = "campus-voting-web"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "worker_repo" {
  name                 = "campus-voting-worker"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "result_repo" {
  name                 = "campus-voting-result"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# 2. IAM Roles and Policies for ECS Tasks
resource "aws_iam_role" "ecs_execution_role" {
  name = "campus-voting-ecs-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "campus-voting-ecs-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "campus-voting-ecs-task-policy"
  role = aws_iam_role.ecs_task_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.voting_queue.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.audit_log.arn}/*"
      }
    ]
  })
}

# 3. Application Load Balancer (ALB) & Target Groups & Listeners
resource "aws_lb" "voting_alb" {
  name               = "campus-voting-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

# Web Target Group (Port 80)
resource "aws_lb_target_group" "web_tg" {
  name        = "campus-voting-web-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 10
  }
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.voting_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# Result Target Group (Port 8080)
resource "aws_lb_target_group" "result_tg" {
  name        = "campus-voting-result-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 10
  }
}

resource "aws_lb_listener" "http_result_listener" {
  load_balancer_arn = aws_lb.voting_alb.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.result_tg.arn
  }
}

# 4. CloudWatch Logs
resource "aws_cloudwatch_log_group" "web_logs" {
  name              = "/ecs/campus-voting-web"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "worker_logs" {
  name              = "/ecs/campus-voting-worker"
  retention_in_days = 7
}

# 5. ECS Cluster, Task Definitions, and Services
resource "aws_ecs_cluster" "voting_cluster" {
  name = "campus-voting-cluster"
}

# --- Web Task & Service ---
resource "aws_ecs_task_definition" "web_task" {
  family                   = "campus-voting-web-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "web"
    image     = "${aws_ecr_repository.web_repo.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }]
    environment = [
      { name = "SQS_QUEUE_URL", value = aws_sqs_queue.voting_queue.url },
      { name = "AWS_DEFAULT_REGION", value = "eu-west-2" },
      { name = "OPTION_A", value = "Youssef Adel" },
      { name = "OPTION_B", value = "cristiano Ronaldo" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.web_logs.name
        "awslogs-region"        = "eu-west-2"
        "awslogs-stream-prefix" = "web"
      }
    }
  }])
}

resource "aws_ecs_service" "web_service" {
  name            = "campus-voting-web-service"
  cluster         = aws_ecs_cluster.voting_cluster.id
  task_definition = aws_ecs_task_definition.web_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.vote_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web_tg.arn
    container_name   = "web"
    container_port   = 80
  }
}

# --- Worker Task & Service ---
resource "aws_ecs_task_definition" "worker_task" {
  family                   = "campus-voting-worker-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "worker"
    image     = "${aws_ecr_repository.worker_repo.repository_url}:latest"
    essential = true
    environment = [
      { name = "SQS_QUEUE_URL", value = aws_sqs_queue.voting_queue.url },
      { name = "S3_BUCKET_NAME", value = aws_s3_bucket.audit_log.bucket },
      { name = "AWS_DEFAULT_REGION", value = "eu-west-2" },
      { name = "DB_HOST", value = aws_db_instance.postgres_free_tier.address },
      { name = "DB_USER", value = aws_db_instance.postgres_free_tier.username },
      { name = "DB_PASS", value = random_password.db_password.result },
      { name = "DB_NAME", value = aws_db_instance.postgres_free_tier.db_name }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.worker_logs.name
        "awslogs-region"        = "eu-west-2"
        "awslogs-stream-prefix" = "worker"
      }
    }
  }])
}

resource "aws_ecs_service" "worker_service" {
  name            = "campus-voting-worker-service"
  cluster         = aws_ecs_cluster.voting_cluster.id
  task_definition = aws_ecs_task_definition.worker_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.worker_sg.id]
    assign_public_ip = false
  }
}

# --- Result Task & Service ---
resource "aws_ecs_task_definition" "result_task" {
  family                   = "campus-voting-result-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "result"
    image     = "${aws_ecr_repository.result_repo.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }]
    environment = [
      { name = "DB_HOST", value = aws_db_instance.postgres_free_tier.address },
      { name = "DB_USER", value = aws_db_instance.postgres_free_tier.username },
      { name = "DB_PASS", value = random_password.db_password.result },
      { name = "DB_NAME", value = aws_db_instance.postgres_free_tier.db_name }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.web_logs.name
        "awslogs-region"        = "eu-west-2"
        "awslogs-stream-prefix" = "result"
      }
    }
  }])
}

resource "aws_ecs_service" "result_service" {
  name            = "campus-voting-result-service"
  cluster         = aws_ecs_cluster.voting_cluster.id
  task_definition = aws_ecs_task_definition.result_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.vote_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.result_tg.arn
    container_name   = "result"
    container_port   = 80
  }
}

# 6. Outputs
output "voting_app_url" {
  description = "Access the voting app via this URL"
  value       = "http://${aws_lb.voting_alb.dns_name}"
}

output "result_app_url" {
  description = "Access the results app via this URL"
  value       = "http://${aws_lb.voting_alb.dns_name}:8080"
}