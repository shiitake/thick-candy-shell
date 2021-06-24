#! /bin/bash

# set -u
user=$1
[[ ! "$#" == 1 ]] && { echo "Please include the name for the certificate you want to generate." >&2; exit 1; }

# check permissions
[[ $EUID -ne 0 ]] && { echo "$0 is not running as root. Try using sudo." >&2; exit 1; }

zip_file="configs/$user-vpn"
config_template="template.ovpn"
client_key_file="InterCA1/private/$user.key"
client_crt_file="InterCA1/issued/$user.crt"
config_temp="/tmp/$user-vpn.ovpn"
client_key_temp="/tmp/client.key"
client_crt_temp="/tmp/client.crt"
setup_file="vpn-setup.md"
setup_temp="/tmp/$user-vpn-setup-instructions.md"

echo "Bundling files into zip folder"
# check that files exist
[[ ! -e $setup_file ]] && { echo "$setup_file does not exist or is in an inaccessible directory" >&2; exit 1; }
[[ ! -e $config_template ]] && { echo "$config_template does not exist or is in an inaccessible directory" >&2; exit 1; }
[[ ! -e $client_key_file ]] && { echo "$client_key_file does not exist or is in an inaccessible directory" >&2; exit 1; }
[[ ! -e $client_crt_file ]] && { echo "$client_crt_file does not exist or is in an inaccessible directory" >&2; exit 1; }

# make temp copied of config and key
cp $config_template $config_temp
cp $client_key_file $client_key_temp
cp $setup_file $setup_temp

# add passphrase to setup file
echo -n "Enter the password associated with $user: "
read -s password
sed -i "s/\$passphrase/$password/g" $setup_temp

# export crt in x509 format
openssl x509 -in $client_crt_file -out $client_crt_temp

# append crt and key to config file
cert=`cat $client_crt_temp`
echo -e "\n<cert>\n$cert\n</cert>\n" >> $config_temp
key=`cat $client_key_temp`
echo -e "\n<key>\n$key\n</key>\n" >> $config_temp
# create zip file
zip -j $zip_file $config_temp $setup_temp

# make sure caadmin can edit the file
chown caadmin $zip_file.zip
chown caadmin $client_crt_file

# clean up temp files
rm $config_temp
rm $client_key_temp
rm $client_crt_temp

echo "VPN config file $zip_file.zip has been copied to the configs folder"
echo "Please make note of the SHA1 Fingerprint"
openssl x509 -in $client_crt_file -fingerprint -noout