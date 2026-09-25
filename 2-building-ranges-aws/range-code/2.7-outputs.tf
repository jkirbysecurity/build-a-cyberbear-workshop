##########################################################################################
# OUTPUTS
##########################################################################################
output "ssh_private_key" {
  description = "The SSH private key used to access linux based systems"
  value       = module.ssh_key_pair.private_key
  sensitive   = true
}

output "ssh_public_key" {
  description = "The SSH public key that belongs to the private key"
  value       = module.ssh_key_pair.public_key
}

locals {
  ssh_prefix = "ssh -i ${module.ssh_key_pair.private_key_filename}"

  output_connect_cheat_sheet = <<CONFIG
      big_bear: ${local.ssh_prefix} ec2-user@${aws_instance.big_bear.public_ip}
 CONFIG

}

output "zdetails" {
  description = "Helpful details about the range"
  value       = <<EOF
The range has been built successfully, below are useful details for using the range.

Connection Cheat Sheet
--------------------------------------------------------------------------------------
${local.output_connect_cheat_sheet}

==============================================
===   Build-A-CyberBear Heart Ceremony     ===
==============================================

Rub your heart with your hands so your cloud has a warm heart

Rub your head so your cloud is smart like you

Rub your nose so the cloud knows who you are

Rub your back so it will always have your back and protect you

Shake your hands up high in the air to give your CyberBear Range high hopes to explore and learn great things

Jump up and down to get the CyberBear Range heart pumping

Give your heart a kiss, close your eyes and make a wish

==============================================
==============================================

Hosts
--------------------------------------------------------------------------------------
big_bear: 
    public ip: ${aws_instance.big_bear.public_ip}
   private ip: ${local.big_bear_private_ip}
          -->  ${local.ssh_prefix} ec2-user@${aws_instance.big_bear.public_ip}


--------------------------------------------------------------------------------------
Have fun with your new CyberBear Range!

What will you build next?

EOF
}

