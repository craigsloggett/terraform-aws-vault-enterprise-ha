resource "aws_route53_record" "vault" {
  zone_id = data.aws_route53_zone.vault.zone_id
  name    = local.vault_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.vault.dns_name
    zone_id                = aws_lb.vault.zone_id
    evaluate_target_health = true
  }
}
