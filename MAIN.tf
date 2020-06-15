provider "aws" {

	region = "ap-south-1"
	profile = "anunay"
}

resource "tls_private_key" "key-pair" {

	algorithm = "RSA"
	rsa_bits = 4096
}

resource "local_file" "private-key" {
    
    content = tls_private_key.key-pair.private_key_pem
    filename = 	"${var.ssh_key_name}.pem"
    file_permission = "0400"
}

resource "aws_key_pair" "deployer" {
  
  key_name   = var.ssh_key_name
  public_key = tls_private_key.key-pair.public_key_openssh
}

resource "aws_security_group" "firewall" {

	name = var.firewall_name
	description = "Allow HTTP and SSH inbound traffic"
	
	ingress	{
		
		from_port = 80
      		to_port = 80
      		protocol = "tcp"
      		cidr_blocks = ["0.0.0.0/0"]
      		ipv6_cidr_blocks = ["::/0"]
      	}
      	
      	ingress {
      		
      		from_port = 22
      		to_port = 22
      		protocol = "tcp"
      		cidr_blocks = ["0.0.0.0/0"]
      		ipv6_cidr_blocks = ["::/0"]
      	}
      	
      	ingress {
      		
      		from_port = -1
      		to_port = -1
      		protocol = "icmp"
      		cidr_blocks = ["0.0.0.0/0"]
      		ipv6_cidr_blocks = ["::/0"]
      	}
      	
      	egress {
      	
      		from_port = 0
      		to_port = 0
      		protocol = "-1"
      		cidr_blocks = ["0.0.0.0/0"]
      	}
}

resource "aws_instance" "MyServer" {
	
	ami = var.ami_id
	instance_type = "t2.micro"
	key_name = var.ssh_key_name
	security_groups = [ aws_security_group.firewall.name ]
	
	tags = {
		Name = var.instance_name
	}
	
	connection {
    		type     = "ssh"
    		user     = "ec2-user"
    		private_key = file("${var.ssh_key_name}.pem")
    		host = aws_instance.MyServer.public_ip
  	}
	
	provisioner "local-exec" {
		command = "echo ${aws_instance.MyServer.public_ip} > public-ip.txt"
	}
	
	provisioner "file" {
		
		source = "configure_os.sh"
		destination = "/tmp/configure_os.sh"
	}
	
	provisioner "remote-exec" {
		
		inline = [
			"chmod +x /tmp/configure_os.sh",
			"/tmp/configure_os.sh args",
		]
	}
}

resource "aws_ebs_volume" "hard-disk" {
  availability_zone = aws_instance.MyServer.availability_zone
  size              = 1

  tags = {
    Name = "DetachableVolume"
  }
}

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.hard-disk.id
  instance_id = aws_instance.MyWebServer.id
  force_detach = true
}

resource "null_resource" "attach-vol" {

	depends_on = [
		aws_volume_attachment.ebs_att,
	]
	
	connection {
    		type     = "ssh"
    		user     = "ec2-user"
    		private_key = file("${var.ssh_key_name}.pem")
    		host = aws_instance.MyServer.public_ip
  	}
  	
  	provisioner "file" {
		
		source = "attach_vol.sh"
		destination = "/tmp/attach_vol.sh"
	}
	
	provisioner "remote-exec" {
		
		inline = [
			"chmod +x /tmp/attach_vol.sh",
			"/tmp/attach_vol.sh args",
		]
	}
}

resource "aws_s3_bucket" "image-bucket" {

	depends_on = [
		null_resource.attach-vol,
	]
	
	bucket = var.bucket_name
	acl = "public-read"
	
	provisioner "local-exec" {
	
		command = "git clone https://github.com/sanchitg18/WebServer-Image.git web-server-image"
	}
	
	provisioner "local-exec" {
	
		when = destroy
		command = "rm -rf web-server-image"
	}
	
}

resource "aws_s3_bucket_object" "bucket-object" {
  
  key = var.object_name
  bucket = aws_s3_bucket.image-bucket.bucket
  acl    = "public-read"
  
  source = "web-server-image/IMG_20200118_210757.jpg"
}

locals {
	s3_origin_id = "S3-${aws_s3_bucket.image-bucket.bucket}"
}

resource "aws_cloudfront_distribution" "cloudfront" {

	enabled = true
	is_ipv6_enabled = true
	
	origin {
		domain_name = aws_s3_bucket.image-bucket.bucket_domain_name
		origin_id = local.s3_origin_id
	}
	
	default_cache_behavior {
    		allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    		cached_methods   = ["GET", "HEAD"]
    		target_origin_id = local.s3_origin_id

    		forwarded_values {
      			query_string = false

      			cookies {
        			forward = "none"
      			}
    		}
    		
    		viewer_protocol_policy = "allow-all"
    	}
    	
    	restrictions {
    		geo_restriction {
    			restriction_type = "none"
    		}
    	}
    	
    	viewer_certificate {
    
    		cloudfront_default_certificate = true
  	}
  	
  	connection {
    		type     = "ssh"
    		user     = "ec2-user"
    		private_key = file("${var.ssh_key_name}.pem")
    		host = aws_instance.MyWebServer.public_ip
  	}
  	
  	provisioner "remote-exec" {
  		
  		inline = [
  			
  			"sudo su << EOF",
            		"echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.bucket-object.key}' width='300' height='380'>\" >> /var/www/html/index.php",
            		"EOF",	
  		]
  	}
}

output "Instance-Public-IP" {
	value = aws_instance.MyWebServer.public_ip
}
