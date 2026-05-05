resource "aws_route53_record" "vault_enterprise" {
  zone_id = var.route53_zone.zone_id
  name    = "${var.route53_record.subdomain}.${var.route53_zone.name}"
  type    = "A"

  alias {
    name                   = aws_lb.vault_enterprise.dns_name
    zone_id                = aws_lb.vault_enterprise.zone_id
    evaluate_target_health = true
  }
}
