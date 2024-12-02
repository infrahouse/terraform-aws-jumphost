resource "tls_private_key" "rsa" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_private_key" "ecdsa" {
  algorithm = "ECDSA"
}

resource "tls_private_key" "ed25519" {
  algorithm = "ED25519"
}
