data "external" "intermediate_csr" {
  program = ["${path.module}/files/wait-for-csr.sh"]

  query = {
    parameter_name = local.intermediate_csr_ssm_name
    timeout_sec    = tostring(var.csr_emission_timeout_seconds)
    region         = data.aws_region.current.region
  }

  depends_on = [aws_autoscaling_group.vault]
}
