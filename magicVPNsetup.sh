#!/bin/bash

[ `id -u` -eq 0 ] || {
    echo "Execute o script como root. Digite:"
    echo "sudo su"
    echo "Saindo..."
    exit 0
}

EXPECT=`which expect`

installPkgs(){
    cp -r geradorDeChaves ~/
    apt-get update
    apt-get install net-tools openvpn expect dnsmasq ufw -y
}

makeDirs(){
    cd
    mkdir CA VPN
}

populate(){
    [ -f /root/autoVPN/EasyRSA-3.0.4.tgz ] || {
        wget -P ~/ https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.4/EasyRSA-3.0.4.tgz
    }
    [ -f /root/autoVPN/EasyRSA-3.0.4.tgz ] && {
	cp /root/autoVPN/EasyRSA-3.0.4.tgz ~/
    }
    tar zxvf EasyRSA-3.0.4.tgz
    cp -r EasyRSA-3.0.4 CA/
    cp -r EasyRSA-3.0.4 VPN/

    cd CA/EasyRSA-3.0.4/
    cp vars.example vars

    sed -i -re 's/#set_var EASYRSA_REQ_COUNTRY(.*)/set_var EASYRSA_REQ_COUNTRY\t"BR"/; s/#set_var EASYRSA_REQ_PROVINCE(.*)/set_var EASYRSA_REQ_PROVINCE\t"Sao Paulo"/;s/#set_var EASYRSA_REQ_CITY(.*)/set_var EASYRSA_REQ_CITY\t"Sao Paulo"/;s/#set_var EASYRSA_REQ_ORG(.*)/set_var EASYRSA_REQ_ORG\t\t"ORGANIZACAO"/;s/#set_var EASYRSA_REQ_EMAIL(.*)/set_var EASYRSA_REQ_EMAIL\t"seu_email@dominio.com"/;s/#set_var EASYRSA_REQ_OU(.*)/set_var EASYRSA_REQ_OU\t\t"UM_NOME"/' vars
}

buildCA(){
    ./easyrsa init-pki

    #./easyrsa build-ca nopass
    cp /root/autoVPN/build-ca.exp /root/CA/EasyRSA-3.0.4/
    cd /root/CA/EasyRSA-3.0.4
    ./build-ca.exp

    [ -f pki/ca.crt -a -f pki/private/ca.key ] || {
        echo "Ocorreu algum erro na criacao do CA (em buildCA). Saindo..."
        exit 0
    }
}

onVPN(){
    if [ "$1" = "server" ]; then
        cd ~/VPN/EasyRSA-3.0.4
        ./easyrsa init-pki

        #./easyrsa gen-req server nopass #[enter]
	    cp /root/autoVPN/gen-req-server-vpn.exp /root/VPN/EasyRSA-3.0.4/

	    ./gen-req-server-vpn.exp

        cp pki/private/server.key /etc/openvpn/
        cp pki/reqs//server.req /tmp/

    elif [ "$1" = "cpOne" ]; then
        cd /root/VPN/EasyRSA-3.0.4/
        cp /tmp/{server.crt,ca.crt} /etc/openvpn/
        ./easyrsa gen-dh
        openvpn --genkey --secret ta.key
        cp ta.key /etc/openvpn/
        cp pki/dh.pem /etc/openvpn/

        mkdir -p ~/client-configs/{keys,files}
        chmod -R 700 ~/client-configs

	#PODE APAGAR ESSES ARQUIVOS AO FINAL DO PROCESSO OU TROQUE POR UM NOME QUALQUER
	#SE FOR TROCAR, TROQUE TAMBEM NO ARQUIVO first-user.exp
        #./easyrsa gen-req djames-suhanko-first nopass #[enter]
	    cp /root/autoVPN/first-user.exp /root/VPN/EasyRSA-3.0.4/

	    ./first-user.exp

        cp pki/private/djames-suhanko-first.key ~/client-configs/keys/
        cp pki/reqs/djames-suhanko-first.req /tmp/
    fi
}

onCA(){
    if [ "$1" = "server" ]; then
        cd /root/CA/EasyRSA-3.0.4/
        ./easyrsa import-req /tmp/server.req server


        #./easyrsa sign-req server server #[yes] [enter]
	    cp /root/autoVPN/sign-req-server-ca.exp /root/CA/EasyRSA-3.0.4/
	    ./sign-req-server-ca.exp

        cp pki/issued/server.crt /tmp/
        cp pki/ca.crt /tmp/

    elif [ "$1" = "cpOne" ]; then
        cd /root/CA/EasyRSA-3.0.4/
        ./easyrsa import-req /tmp/djames-suhanko-first.req djames-suhanko-first


        #./easyrsa sign-req client djames-suhanko-first #[yes] [enter]
	    cp /root/autoVPN/sign-first.exp /root/CA/EasyRSA-3.0.4/

	    ./sign-first.exp

        cp pki/issued/djames-suhanko-first.crt /tmp/
        cp /tmp/djames-suhanko-first.crt ~/client-configs/keys/
        cd /root/VPN/EasyRSA-3.0.4/
        cp ta.key ~/client-configs/keys/
        cp /etc/openvpn/ca.crt ~/client-configs/keys/
        #(Não havendo erro até aqui, segue a configuração - NAO ESQUECA DE APAGAR QUALQUER ARQUIVO DE TESTE djames-suhanko* OU O NOME QUE VOCE TENHA DADO) 
    fi
}

setupOpenVPN(){
    cp /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz /etc/openvpn/
    gzip -d /etc/openvpn/server.conf.gz
    egrep -v '^$|^#|^;' /etc/openvpn/server.conf >/etc/openvpn/server_conf.new
    sed -i -re 's/(cipher AES-256-CBC)/\1 \nauth SHA256\nuser nobody\ngroup nogroup/;s/^dh dh2048.pem/dh dh.pem/' /etc/openvpn/server_conf.new

    IP_IF=$(ifconfig eth0|egrep inet|egrep netmask|awk '{print $2}')

    sed -i -re "s/#?(listen-address=)/\1$IP_IF/" /etc/dnsmasq.conf
    #PERSONAL: TROQUE OS PUSHES PARA AS CONFIGURACOES DE SUA REDE
    sed -i -re "s/(keepalive 10 120)/push \"route 172.31.0.0 255.255.0.0\"\npush \"dhcp-option DNS 172.31.0.2\"\npush \"dhcp-option DNS 8.8.8.8\"\nkeepalive 10 120/" /etc/openvpn/server_conf.new

    mv /etc/openvpn/server_conf.new /etc/openvpn/server.conf

    sed -i -re 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    sysctl -p
    #PERSONAL: TROQUE OS ENDERECAMENTOS CONFORME SUA REDE
    echo "
# START OPENVPN RULES
# NAT table rules
*nat
:POSTROUTING ACCEPT [0:0]
# Allow traffic from OpenVPN client to eth0 (change to the interface you discovered!)
-A POSTROUTING -s 10.8.0.0/8 -o eth0 -j MASQUERADE
COMMIT
# END OPENVPN RULES" >/tmp/rules.tmp
echo "" >>/tmp/rules.tmp

    [ -f /etc/ufw/before.rules ] && {
        cat /etc/ufw/before.rules >>/tmp/rules.tmp
        mv /tmp/rules.tmp /etc/ufw/before.rules
        sed -i -re 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
    }

    echo '#!/bin/bash
echo "1" >/proc/sys/net/ipv4/ip_forward
IPT=`which iptables`
$IPT -P FORWARD DROP
$IPT -t nat -A POSTROUTING -d 172.31.0.0/16 -j MASQUERADE
$IPT -A FORWARD -s 172.31.0.0/16 -j ACCEPT
$IPT -A FORWARD -d 172.31.0.0/16 -mstate --state ESTABLISHED,RELATED -j ACCEPT
$IPT -A FORWARD -s 10.8.0.0/24 -j ACCEPT
$IPT -A INPUT -p udp --dport 1194 -j ACCEPT
$IPT -A FORWARD -p udp --dport 53 -j ACCEPT
' >~/frw.sh

    chmod 750 ~/frw.sh

    ufw allow 1194/udp
    ufw allow OpenSSH

    cp ~/frw.sh /sbin/

    echo "[Unit]
Description=Firewall rules for OpenVPN tun
After=network.target

[Service]
Type=simple
ExecStart=/sbin/frw.sh
RemainAfterExit=true
StandardOutput=journal
User=root

[Install]
WantedBy=multi-user.target" >frw4tun.service

    mv frw4tun.service /etc/systemd/system

    systemctl enable frw4tun
    systemctl start frw4tun

    systemctl start openvpn@server
    ifconfig tun0 2>/dev/null
    sleep 2
    systemctl enable openvpn@server

    cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf ~/client-configs/base.conf

    IP_PUBLICO=`curl ifconfig.me`

    cd ~/client-configs

    egrep -v '^$|^#|^;|ca.crt|client.crt|client.key|tls-auth' base.conf |sed -re "s/(remote )(.* )(1194)/\1$IP_PUBLICO \3/;s/nobind/nobind\nuser nobody\ngroup nogroup/;s/(cipher AES-256-CBC)/\1\nauth SHA256\nkey-direction 1/" >base2.conf

    printf "# script-security 2\n# up /etc/openvpn/update-resolv-conf\n# down /etc/openvpn/update-resolv-conf\n" >>base2.conf

    mv base2.conf base.conf

    echo "VERIFIQUE SE O ARQUIVO /etc/hosts ESTA COM OS HOSTS CERTOS, SENAO, TROQUE-OS. Seguindo..."
    sleep 5
}

installPkgs
makeDirs
populate
buildCA
onVPN "server"
onCA "server"
onVPN "cpOne"
onCA "cpOne"
setupOpenVPN

echo "Finalizado. Para criar credenciais, entre no diretorio geradorDeChaves e execute:"
echo "./criar_credential_para.exp NOME_DESEJADO"
