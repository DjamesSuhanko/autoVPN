# autoVPN
Install and configure OpenVPN with 1 shot.
Works fine in Debian 10 on AWS EC2 and can works in another environments and architectures , like Raspberry Pi (ARM)

## How to use
Clone this repository directly to /root or move it to there after to clone it.
Go to directory and execute the magicVPNsetup.sh.

```
sudo su
mv autoVPN /root
cd /root/autoVPN
./magicVPNsetup.sh
```

## To create new ovpn access files
Inside /root directory there is a a directory named geradorDeChaves.
Access /root directory and execute this command below:
```
./criar_credencial_para.exp nome-que-quiser
```
The ovpn file will be created automatically and then process is finished, you will receive additional information about that file.

