# shellcheck shell=sh
# imds.sh — EC2 Instance Metadata Service (IMDSv2) helpers.

get_imds_token() {
  curl -s -X PUT \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 3600" \
    "http://169.254.169.254/latest/api/token"
}

get_imds_metadata() {
  path="${1}"
  token="$(get_imds_token)"
  curl -s -H "X-aws-ec2-metadata-token: ${token}" \
    "http://169.254.169.254/latest/meta-data/${path}"
}

get_private_ip() {
  get_imds_metadata "local-ipv4"
}

get_instance_id() {
  get_imds_metadata "instance-id"
}

get_availability_zone() {
  get_imds_metadata "placement/availability-zone"
}
