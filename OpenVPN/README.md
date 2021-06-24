## Setting up the VPN with EasyRSA
I'm adding these instructions for future me. 

#### Prereqs
* install easyrsa

### Create root ca
1. create primary pki
easyrsa init-pki

2. create ca
easyrsa --days=1826 build-ca

Common name: RootCA


### Creating intermediate ca 
1.  create new PKI
easyrsa --pki-dir=InterCA1 init-pki

2. build new intermediate CA request
easyrsa --pki-dir=InterCA1 build-ca subca

Common name: InterCA1

The request should be at IntermedicateCA/reqs/ca.req

3. Sign request using root ca
copy ca.req to request directory of root ca (pki/reqs/) (to avoid confusion I renamed it to InterCA1.req) and run the following
easyrsa --days=1826 sign-req ca InterCA1

4. This will generate a crt file in the "issued" folder. Copy that file back to the intermediate ca. (If you renamed your file then you might have to rename it back to ca.crt)

5. Copy that intermediate ca to wherever you'll be generating your VPN certificates


### Generating the VPN certificates

To generate a new VPN certificate/key for a user run the following command:  
`sudo easyrsa --pki-dir=InterCA1 build-client-full <username>`

1. You will be prompted to create a password for the user (make sure that you write it down so you can provide it to them)
2. This will also require the password for the InterCA1 certificate.

Once this completes you can bundle the VPN certificate/key into a zip file by running:  
`./bundle <username>`

This will save a zip file <username>-vpn.zip in the configs folder. It will prompt you for the passphrase for the user. 

This script expects that you'll be running it from the easy-rsa directory and that your pki is named InterCA1. It also will add the certificate/key to an open vpn file based on a template file provided (template.ovpn)

### Other commands that might be helpful to someone

To generate the fingerprint for a certificate  
`openssl x509 -in InterCA1/issued/<user>.crt -fingerprint -noout`

To generate the public key  
`openssl x509 -in InterCA1/issued/<user>.crt -pubkey`

To generate just the certificate  
`openssl x509 -in InterCA1/issued/<user>.crt -pubkey`

To output just the encoded data  
`openssl x509 -in InterCA1/issued/<user>.crt -out InterCA1/issued/<user>.cer`
