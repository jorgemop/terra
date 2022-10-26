data "aws_caller_identity" "current" {}
variable "company_name" {
default = "acme"
}
variable "environment" {
default = "dev"
}
locals {
resource_prefix = {
value =
"${data.aws_caller_identity.current.account_id}-${var.company_name}-${var.environment}"
}
}
variable "profile" {
default = "default"
}
variable "region" {
default = "us-west-2"
}
resource "aws_iam_user" "dev" {
name = "${local.resource_prefix.value}-user"
force_destroy = true
}
resource "aws_iam_access_key" "dev" {
user = aws_iam_user.dev.name
}
resource "aws_iam_user_policy" "devpolicy" {
name = "excess_policy"
user = "${aws_iam_user.dev.name}"
policy = <<EOF
{
"Version": "2012-10-17",
"Statement": [
{
"Action": [
"ssm:*:",
"cloudformation:*",
"api:*",
"iam:*",
"kms:*",
"ec2:*",
"s3:*",
"lambda:*"
],
"Effect": "Allow",
"Resource": "*"
}
]
}
EOF
}
output "username" {
value = aws_iam_user.dev.name
}
output "secret" {
value = aws_iam_access_key.dev.encrypted_secret
}
resource "aws_instance" "web_1" {
ami = "${var.ami}"
instance_type = "t2.nano"
vpc_security_group_ids = [
"${aws_security_group.web-node.id}"]
subnet_id = "${aws_subnet.web_subnet.id}"
user_data = <<EOF
#! /bin/bash
sudo apt-get update
sudo apt-get install -y apache2
sudo systemctl start apache2
sudo systemctl enable apache2
export AWS_ACCESS_KEY_ID=AKIAIOSFOD13N7EXAMAAA
export AWS_SECRET_ACCESS_KEY=wJalrXUt134EMI/K7MDENG/bPxRfiCYEXAMAAAKEY
export AWS_DEFAULT_REGION=us-west-2
echo "<h1>Deployed via Terraform</h1>" | sudo tee /var/www/html/index.html
EOF
}
resource "aws_ebs_volume" "web_1_storage" {
availability_zone = "${var.region}a"
encrypted = false
size = 1
}
resource "aws_ebs_snapshot" "first_snapshot" {
volume_id = "${aws_ebs_volume.web_1_storage.id}"
description = "${local.resource_prefix.value}-ebs-snapshot"
}
resource "aws_snapshot_create_volume_permission" "cross_account" {
snapshot_id = aws_ebs_snapshot.first_snapshot.id
account_id = "12345678"
}
resource "aws_volume_attachment" "ebs_attachement" {
device_name = "/dev/sdh"
volume_id = "${aws_ebs_volume.web_1_storage.id}"
instance_id = "${aws_instance.web_1.id}"
}
resource "aws_security_group" "web-node" {
name = "${local.resource_prefix.value}-sg"
description = "${local.resource_prefix.value} Security Group"
vpc_id = aws_vpc.web_vpc.id
ingress {
from_port = 80
to_port = 80
protocol = "tcp"
cidr_blocks = [
"0.0.0.0/0"]
}
ingress {
from_port = 22
to_port = 22
protocol = "tcp"
cidr_blocks = [
"0.0.0.0/0"]
}
egress {
from_port = 0
to_port = 0
protocol = "-1"
cidr_blocks = [
"0.0.0.0/0"]
}
depends_on = [aws_vpc.web_vpc]
}
resource "aws_vpc" "web_vpc" {
cidr_block = "172.16.0.0/16"
enable_dns_hostnames = true
enable_dns_support = true
}
resource "aws_subnet" "web_subnet" {
vpc_id = aws_vpc.web_vpc.id
cidr_block = "172.16.10.0/24"
availability_zone = "${var.region}a"
map_public_ip_on_launch = true
}
resource "aws_subnet" "web_subnet2" {
vpc_id = aws_vpc.web_vpc.id
cidr_block = "172.16.11.0/24"
availability_zone = "${var.region}b"
map_public_ip_on_launch = true
}
resource "aws_internet_gateway" "web_igw" {
vpc_id = aws_vpc.web_vpc.id
}
resource "aws_route_table" "web_rtb" {
vpc_id = aws_vpc.web_vpc.id
}
resource "aws_route_table_association" "rtbassoc" {
subnet_id = aws_subnet.web_subnet.id
route_table_id = aws_route_table.web_rtb.id
}
resource "aws_route_table_association" "rtbassoc2" {
subnet_id = aws_subnet.web_subnet2.id
route_table_id = aws_route_table.web_rtb.id
}
resource "aws_route" "public_internet_gateway" {
route_table_id = aws_route_table.web_rtb.id
destination_cidr_block = "0.0.0.0/0"
gateway_id = aws_internet_gateway.web_igw.id
timeouts {
create = "5m"
}
}
resource "aws_network_interface" "web-eni" {
subnet_id = aws_subnet.web_subnet.id
private_ips = ["172.16.10.100"]
}
output "ec2_public_dns" {
description = "Web Host Public DNS name"
value = aws_instance.web_1.public_dns
}
output "vpc_id" {
description = "The ID of the VPC"
value = aws_vpc.web_vpc.id
}
output "public_subnet" {
description = "The ID of the Public subnet"
value = aws_subnet.web_subnet.id
}
output "public_subnet2" {
description = "The ID of the Public subnet"
value = aws_subnet.web_subnet2.id
}