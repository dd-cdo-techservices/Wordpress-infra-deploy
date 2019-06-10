# AWS infrastructure provisioning
# Project: CICD Pipeline Setup
# Use Case# : 1
# CreatedBy : Sumanth

##################################

provider "aws" {
	region = "${var.aws_region}"
	profile = "wordpress-app"
}

#Find the latest available AMI with Wordpress based on Name Tag
data "aws_ami" "wordpressappami" {
  owners = ["self"]
  most_recent = true
  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "tag:Name"
    values = ["wordpress-app-AMI"]
  }
}

#Find the latest MYSQL AMI using Name Tag
data "aws_ami" "ubmysqlami" {
  owners = ["self"]
  most_recent = true

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
	  name   = "tag:Name"
    values = "[wordpress-mysql-ami]"
  }
}

# Create a VPC for setting up CICD pipeline infrastructure
# with necessary components.

#VPC creation
resource "aws_vpc" "uconenetwork" {
	cidr_block       = "${var.aws_vpc_cidr}"
	enable_dns_support = "true"
	enable_dns_hostnames = "true"  

	tags = {
	  Name = "uconenetwork"
	  CreatedBy = "cdo_devops"
	  Purpose = "uconedemopipeline"
  	}
}

#Internet Gateway creation
resource "aws_internet_gateway" "cicdgw" {
	vpc_id = "${aws_vpc.uconenetwork.id}"

	tags = {
	  Name = "ucone-igw"
	  CreatedBy = "cdo_devops"
          Purpose = "uconedemopipeline"
	}
}

#Public subnet creation
resource "aws_subnet" "uconenetworkpublicsubnet" {
	vpc_id = "${aws_vpc.uconenetwork.id}"
	cidr_block = "${var.aws_publicsubnet01}"
	availability_zone = "${var.aws_az1}"

	tags = {
	  Name = "cicdpublicsubnet"
          CreatedBy = "cdo_devops"
          Purpose = "uconedemopipeline"
	}
}

#Private subnet creation
resource "aws_subnet" "uconenetworkprivatesubnet" {
        vpc_id = "${aws_vpc.uconenetwork.id}"
        cidr_block = "${var.aws_privatesubnet01}"
        availability_zone = "${var.aws_az2}"

        tags = {
          Name = "cicdprivatesubnet"
          CreatedBy = "cdo_devops"
          Purpose = "uconedemopipeline"
        }
}

#Provision Route Table for Public Subnet
resource "aws_route_table" "uconepublicrt" {
	vpc_id = "${aws_vpc.uconenetwork.id}"
	
	route {
	  cidr_block = "0.0.0.0/0"
    	  gateway_id = "${aws_internet_gateway.cicdgw.id}"
	}

	tags = {
          Name = "cicdpublicsubnetrt"
          CreatedBy = "cdo_devops"
          Purpose = "uconedemopipeline"
        }
}

#Associate Routing Table with Public Subnet
resource "aws_route_table_association" "cicdrtassociate" {
	subnet_id = "${aws_subnet.uconenetworkpublicsubnet.id}"
	route_table_id = "${aws_route_table.uconepublicrt.id}"
}

#Security group creation
resource "aws_security_group" "cicd_sg" {
	name        	= "wordpressapp_sg"
	description 	= "Allow HTTP inbound traffic"
	vpc_id      	= "${aws_vpc.uconenetwork.id}"

	ingress {
	  from_port   = 80
    	  to_port     = 80
    	  protocol    = "tcp"
    	  cidr_blocks = ["0.0.0.0/0"]
  	}

        ingress {
	  from_port   = 8080
	  to_port     = 8080
	  protocol    = "tcp"
	  cidr_blocks = ["0.0.0.0/0"]
	}
	
	ingress {
	  from_port   = 22
    	  to_port     = 22
    	  protocol    = "tcp"
    	  cidr_blocks = ["18.213.75.241/32"]
  	}

  	egress {
    	  from_port     = 0
    	  to_port       = 0
    	  protocol      = "-1"
    	  cidr_blocks   = ["0.0.0.0/0"]
 	}

	tags = {
   	  Name		= "cicdsg"
          CreatedBy 	= "cdo_devops"
          Purpose 	= "uconedemopipeline"
        }
}


#Security group for mysql instance
resource "aws_security_group" "cicd_db_sg" {
	name		= "uconemysql_sg"
	description	= "Allow DB inbound traffic"
	vpc_id		= "${aws_vpc.uconenetwork.id}"

	ingress {
	  from_port		= 3306
	  to_port		= 3306
	  protocol		= "tcp"
	  security_groups	= ["${aws_security_group.cicd_sg.id}"]
	}

	egress {
 	  from_port	= 0
	  to_port	= 0
	  protocol	= "-1"
	  cidr_blocks	= ["0.0.0.0/0"]
	}

	tags = {
	  Name		= "cicddbsg"
	  CreatedBy	= "cdo_devops"
	  Purpose	= "uconedemopipeline"
	}
}


#Provision an EC2 instance for hosting wordpress app server
resource "aws_instance" "wordpress_app_server" {
	ami				= "${data.aws_ami.wordpressappami.id}"
	instance_type			= "t2.micro"
	subnet_id 			= "${aws_subnet.uconenetworkpublicsubnet.id}"
	depends_on			= ["aws_internet_gateway.cicdgw"]
	vpc_security_group_ids 		= ["${aws_security_group.cicd_sg.id}"]
	private_ip			= "${var.wordpress_app_server_privateip}"
	key_name                        = "devopsTestKP"
	tags = {
    	  Name		= "wordpress_app_server"
    	  CreatedBy	= "cdo_devops"
    	  Purpose	= "uconedemopipeline"
	}
}

#Associate Elastic IP to the App server
resource "aws_eip_association" "eip_assoc_app" {
	instance_id	= "${aws_instance.wordpress_app_server.id}"
	allocation_id	= "${var.appserver_ip}"
}


#Provision an EC2 instance for hosting mysql db
resource "aws_instance" "wordpress_mysql_server" {
	ami				= "${data.aws_ami.ubmysqlami.id}"
	instance_type			= "t2.micro"
	subnet_id			= "${aws_subnet.uconenetworkprivatesubnet.id}"
	vpc_security_group_ids		= ["${aws_security_group.cicd_db_sg.id}"]
	private_ip			= "${var.wordpress_db_server_privateip}"
	key_name                        = "devopsTestKP"
	tags = {
	  Name		= "wordpress_mysql"
	  CreatedBy	= "cdo_devops"
	  Purpose	= "uconedemopipeline"
	}
}


# Provision Classic Load Balancer
resource "aws_elb" "cicdclassicelb" {
  name		= "cicdpipelineelb"
  subnets	= ["${aws_subnet.uconenetworkpublicsubnet.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "TCP:80"
    interval            = 30
  }

  security_groups		= ["${aws_security_group.cicd_sg.id}"]
  instances                   	= ["${aws_instance.wordpress_app_server.id}"]
  cross_zone_load_balancing   	= true
  idle_timeout                	= 400
  connection_draining         	= true
  connection_draining_timeout 	= 400

  tags = {
    Name	= "cicdclassicelb"
    CreatedBy	= "cdo_devops"
    Purpose	= "uconedemopipeline"
  }
}

#Display the output of public dns of ELB
output "aws_elb_dns_name" {
	value = "${aws_elb.cicdclassicelb.dns_name}"
}
