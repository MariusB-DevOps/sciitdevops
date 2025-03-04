provider "aws" {
  region = var.region
}

resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
  tags       = merge(local.common_tags, { Name = var.vpc_name })
}


resource "aws_internet_gateway" "net-igw" {
  vpc_id = aws_vpc.vpc.id
  tags   = merge(local.common_tags, { Name = "net-igw" })
}

resource "aws_instance" "web" {
  ami                    = "ami-02141377eee7defb9" # Ubuntu AMI
  instance_type          = "t3.medium"
  availability_zone      = var.public_subnet_az
  subnet_id              = aws_subnet.public-subnet.id
  vpc_security_group_ids = [aws_security_group.sg.id]

  tags = merge(local.common_tags, { Name = "WebServer" })

  #user_data = file("python_web_server.sh")
   # Use the remote-exec provisioner to run the setup script
  provisioner "file" {
    source      = "python_web_server.sh"
    destination = "/home/ec2-user/python_web_server.sh"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.private_key.private_key_openssh # Path to your private key
      host        = self.public_ip
    }

  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /home/ec2-user/python_web_server.sh",
      "/home/ec2-user/python_web_server.sh"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.private_key.private_key_openssh # Path to your private key
      host        = self.public_ip
    }
  }
}


