terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  #  secret_key = ""
  #  access_key = ""
}

resource "aws_instance" "control_node" {
  ami = var.myami
  instance_type = var.controlinstancetype
  key_name = var.mykey
  iam_instance_profile = aws_iam_instance_profile.ec2full.name
  vpc_security_group_ids = [aws_security_group.tf-sec-gr.id]
  tags = {
    Name = "ansible_control"
    stack = "ansible_project"
  }
}

resource "aws_instance" "nodes" {
  ami = var.myami
  instance_type = var.instancetype
  count = var.num
  key_name = var.mykey
  vpc_security_group_ids = [aws_security_group.tf-sec-gr.id]
  tags = {
    Name = "ansible_${element(var.tags, count.index )}"
    stack = "ansible_project"
    environment = "development"
  }
  user_data = file("userdata.sh")
}

resource "aws_iam_role" "ec2full" {
  name = "projectec2full-${var.user}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonEC2FullAccess"]
}

resource "aws_iam_instance_profile" "ec2full" {
  name = "projectec2full-${var.user}"
  role = aws_iam_role.ec2full.name
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "tf-sec-gr" {
  name = "${var.mysecgr}-${var.user}"
  vpc_id = data.aws_vpc.default.id
  tags = {
    Name = var.mysecgr
  }

  ingress {
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 3306
    protocol    = "tcp"
    to_port     = 3306
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    protocol    = -1
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "null_resource" "config" {
  depends_on = [aws_instance.control_node]
  connection {
    host = aws_instance.control_node.public_ip
    type = "ssh"
    user = "ec2-user"
    private_key = file("~/${var.mykey}.pem")
    # Do not forget to define your key file path correctly!
    # null_resource, Terraform içinde sanal bir kaynaktır ve gerçekte altyapıda bir varlık oluşturmaz.
    # Bu kaynak, diğer kaynaklarla ilişkilendirilebilen ve Terraform'ın yaşam döngüsüne katılabilen bir 
    # araçtır. depends_on özelliği sayesinde başka bir kaynağa bağımlılık ekleyebilir ve bu sayede sırasını belirleyebilirsiniz. 
  }

  provisioner "file" {
    source = "./ansible.cfg"
    destination = "/home/ec2-user/.ansible.cfg"
  }

  provisioner "file" {
    source = "./inventory_aws_ec2.yml"
    destination = "/home/ec2-user/inventory_aws_ec2.yml"
  }

  provisioner "file" {
    # Do not forget to define your key file path correctly!
    source = "~/${var.mykey}.pem"
    destination = "/home/ec2-user/${var.mykey}.pem"
  }

  provisioner "file" {
    source = "./bookstore-api.py"
    destination = "/home/ec2-user/bookstore-api.py"
  }

   provisioner "file" {
    source = "./requirements.txt"
    destination = "/home/ec2-user/requirements.txt"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname Control-Node",
      "sudo yum install -y python3",
      "sudo yum install -y python3-pip",
      "pip3 install --user ansible",
      "pip3 install --user boto3",
      "chmod 400 ${var.mykey}.pem"
    ]
  }

}

output "mysql_server" {
  value = aws_instance.nodes[1].private_ip
}

output "controlnodeip" {
  value = aws_instance.control_node.public_ip
}

output "privates" {
  value = aws_instance.control_node.*.private_ip
}