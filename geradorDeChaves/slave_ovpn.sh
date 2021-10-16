#!/bin/bash

#TODO: verificar se nao tem que digitar a senha mesmo (nopass)

[ $# -eq 1 ] || {
    echo "Ops. Passe o nome como parametro. Saindo..."
    exit 0
}

#Para nao usar duas maquinas, foram criadas duas estrutras. Isso facilita
#a migracao para o modelo de uma maquina CA e uma maquina VPN.
#O processo de criacao pode parecer estranho, mas eh uma simulacao de 
#2 maquinas, por isso o processo de transporte para /tmp algumas vezes.
#Ficara  mais claro adiante

DIR_VPN="/root/VPN/EasyRSA-3.0.4"
DIR_CA="/root/CA/EasyRSA-3.0.4"


CLIENT_CONFIGS="/root/client-configs"
DIR_KEYS="$CLIENT_CONFIGS/keys"
DIR_PKI_PRIVATE="pki/private"
DIR_PKI_ISSUED="pki/issued"
DIR_PKI_REQS="pki/reqs"
CERT_TA="$DIR_VPN/ta.key"
CERT_CA="/etc/openvpn/ca.crt"

#Esse arquivo já recebeu todas as configurações anteriormente. Se por alguma razão ele for perdido, deve-se seguir o procedimento descrito no tutorial da digitalocean. Uma cópia desse material será salva para o caso de uma reimplementação.
# https://www.digitalocean.com/community/tutorials/how-to-set-up-an-openvpn-server-on-debian-9-pt

BASE_FILE="$CLIENT_CONFIGS/base.conf"

#4 - Gerar um certificado de cliente e um par de chaves
cd $DIR_VPN
./easyrsa gen-req $1 nopass

cp "$DIR_PKI_PRIVATE/$1.key" "$DIR_KEYS/"
cp "$DIR_PKI_REQS/$1.req" /tmp/

#MAQUINA CA AGORA
cd $DIR_CA
./easyrsa import-req /tmp/$1.req $1
./easyrsa sign-req client $1

cp "$DIR_PKI_ISSUED/$1.crt" /tmp/

#VOLTANDO PRA MAQUINA VPN
cp "/tmp/$1.crt" "$DIR_KEYS/"
cp "$CERT_TA" "$DIR_KEYS/"
cp "$CERT_CA" "$DIR_KEYS/"

#gerando o arquiivo ovpn

KEY_DIR=/root/client-configs/keys
OUTPUT_DIR=/root/client-configs/files
BASE_CONFIG=/root/client-configs/base.conf
USER_HOME_OVPN=$(ls /home)
cd "$CLIENT_CONFIGS"

cat ${BASE_CONFIG} \
    <(echo -e '<ca>') \
    ${KEY_DIR}/ca.crt \
    <(echo -e '</ca>\n<cert>') \
    ${KEY_DIR}/${1}.crt \
    <(echo -e '</cert>\n<key>') \
    ${KEY_DIR}/${1}.key \
    <(echo -e '</key>\n<tls-auth>') \
    ${KEY_DIR}/ta.key \
    <(echo -e '</tls-auth>') \
    > ${OUTPUT_DIR}/${1}.ovpn


cp "$OUTPUT_DIR/$1.ovpn" /home/$USER_HOME_OVPN/
chown  $USER_HOME_OVPN.$USER_HOME_OVPN /home/$USER_HOME_OVPN/$1.ovpn

echo "Se o sistema usar resolvconf, lembrar de descomentar:"
echo "script-security 2"
echo "up /etc/openvpn/update-resolv-conf"
echo "down /etc/openvpn/update-resolv-conf"

echo "Entregue o arquivo /home/$USER_HOME_OVPN/$1.ovpn"
